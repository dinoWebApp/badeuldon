# 스텝 산정·발송 스캔(F-REM — REM-2/3/4·PROMISE-3·REM-12/13·SHARE-5) — 매일 14:00 평일
# (Reminders::DispatchJob)이 호출하는 무상태 스캔. 스케줄을 저장하지 않고 오늘 도래한 스텝을
# 매번 재계산한다.
# - 기본 트랙: invoice_notice(만기 D-1) → confirm_d1|confirm_d1_opened(D+1 — 열람 이력 분기
#   REM-4·SHARE-5, 1회 발송 후 분기 고정) → requeue_d7(D+7) → final_d14(D+14 — 발송 성공 후
#   finish_sequence! REM-12, SendService 훅)
# - 약속 트랙(PROMISE-3): 최신 약속(this_week·date_selected) 보유 건은 기본 트랙을 대체 →
#   promise_d1(약속일-1) → promise_overdue(약속일+1 — 발송 성공 후 종결 REM-13 + U1 통보
#   NOTI-1, SendService 훅). 재약속 시 최신 약속 기준으로 스텝이 재계산된다.
# - 소급 창(REM-3): 스텝은 nominal 날짜부터 다음 평일까지만 발송(토·일 스텝의 자연 이연·장애
#   다음날 회복 허용). 넘어간 스텝은 PAST_WINDOW로 1회만 기록해 업그레이드 등으로 인한 과거
#   스텝 일괄 소급 발송을 차단한다.
# 스텝 산정의 단일 출처 — 오늘 발송 예정 판정(steps_due_today — 사전통보 REM-11 공용), 수동
# 발송 산정(manual_step_key — REM-8), 재개 가능 판정(restartable? — REM-12/13)이 모두
# call의 발송 스캔과 같은 steps_for·소급 창 판정을 공유한다(C-2·W-1 — 이원화 차단).
module Reminders
  class DispatchService
    # 소급 창 경과 스텝의 스킵 사유(MessageLog.error_code)
    PAST_WINDOW = "PAST_WINDOW"
    # 기본 트랙의 연체 단계(REM-2) — D+1 분기 후보 템플릿
    CONFIRM_KEYS = %w[ confirm_d1 confirm_d1_opened ].freeze
    # REM-11 사전통보 대상 = 연체·도과 단계(D+1·D+7·D+14 상당). 만기 예정 안내(invoice_notice)
    # 와 약속 전날 안내(promise_d1)는 NOTI-1 만기 임박(noti_due_soon) 계열로 시점이 겹치며
    # "연체 단계" 명세(REM-11)에 없다. promise_overdue는 발송이 실제 일어나는 도과 단계라
    # 취소 창(REM-11) 보장을 위해 포함한다.
    PRENOTICE_KEYS = (%w[ requeue_d7 final_d14 promise_overdue ] + CONFIRM_KEYS).freeze

    # client — 솔라피 래퍼 주입 지점(W-7 — 자동 스캔 경로까지 stub 주입 가능하게
    # perform_send가 SendService로 전달). 미주입 시 SendService가 기본 래퍼를 지연 생성한다.
    def initialize(client: nil)
      @client = client
    end

    def call
      dispatchable_invoices.find_each { |invoice| dispatch(invoice) }
    end

    # ── 공개 산정 진입점(발송 스캔과 동일 논리 — 이원화 금지) ──────────────────

    # 오늘(소급 창 포함) 발송 예정인 연체·도과 단계의 template_key 목록 — PrenoticeService의
    # 공용 판정점(REM-11·C-2). 발송 스캔(call)이 실제 발송에 쓰는 steps_for·소급 창 판정과
    # 같은 산정이므로 주말 nominal의 월요일 소급분도 09시 사전통보가 커버한다. 이미 발송된
    # 단계(origin 무관 — 수동 재발송분 포함)는 예정이 없으므로 제외한다.
    def steps_due_today(invoice)
      today = Date.current
      steps_for(invoice).filter_map do |template_key, nominal_on|
        next unless PRENOTICE_KEYS.include?(template_key)
        next if step_sent?(invoice, template_key)

        template_key if nominal_on <= today && today <= window_end(nominal_on)
      end
    end

    # 수동 재개(REM-12·13) 가능 판정 — 종결 해소 시 발송될 미발송 스텝이 소급 창 내에 남아
    # 있는가. 전부 창 경과면 재개해도 발송이 없으므로(멱등 skip·PAST_WINDOW) 재개 불가로
    # 안내한다. 종결 시점(final_d14·promise_overdue 성공 후)에는 만기 예정(D-1)·약속 전날
    # 스텝이 창 내일 수 없어 연체·도과 단계 판정(steps_due_today)과 같은 모집합이다.
    def restartable?(invoice)
      !steps_due_today(invoice).empty?
    end

    # 수동 발송(REM-8)의 "현재 상황에 맞는 다음 1통" — RemindersContext(컨트롤러 관심사)의
    # 단일 출처(W-1). 자동 스캔과 같은 트랙·분기 판정(latest_promise·confirm_template_key)을
    # 공유하며, 시점 버킷팅만 수동 특유다(만기 당일까지 만기 예정 안내). 최종 가드(보류·
    # 수신거부·상한·발송 창)는 Reminders::SendService가 다시 확인한다.
    def manual_step_key(invoice)
      promise = latest_promise(invoice)
      if promise&.promised_on
        return promise.promised_on >= Date.current ? "promise_d1" : "promise_overdue"
      end

      due = invoice.due_on
      today = Date.current
      if due >= today
        "invoice_notice"
      elsif due + 6 >= today
        confirm_template_key(invoice)
      elsif due + 13 >= today
        "requeue_d7"
      else
        "final_d14"
      end
    end

    private

    # 가드의 상류 필터(Invoice.reminders_dispatchable) — 미수·링크 유효·보류/수신거부/종결 아님.
    # 마감 경합·자격·상한·발송 창은 SendService가 발송 직전 재확인한다(REM-11 취소 창 흡수).
    def dispatchable_invoices
      Invoice.reminders_dispatchable.includes(:client, :view_events)
    end

    def dispatch(invoice)
      steps_for(invoice).each do |template_key, nominal_on|
        dispatch_step(invoice, template_key, nominal_on)
      end
    end

    # 스텝 판정 — nominal(스텝 기준일)이 미래면 대기, 소급 창 경과면 기록, 창 내면 발송.
    def dispatch_step(invoice, template_key, nominal_on)
      today = Date.current
      return if nominal_on > today  # 아직 도래하지 않은 스텝

      if today > window_end(nominal_on)
        record_past_window_skip(invoice, template_key)
      else
        perform_send(invoice, template_key)
      end
    end

    def perform_send(invoice, template_key)
      Reminders::SendService.new(invoice: invoice, template_key: template_key,
                                 recipient_role: :debtor, client: @client).call
    rescue Solapi::ApiError => e
      # SendService는 실패를 기록한 뒤 모호 실패(TIMEOUT/CONNECTION)만 재상승한다 — 스캔 전체가
      # 한 건으로 멈추지 않게 단건 잡으로 재시도를 넘긴다(DeliverJob이 같은 실행기를 재사용).
      Rails.logger.warn("[Reminders::DispatchService] invoice=#{invoice.id} " \
                        "template=#{template_key} code=#{e.code}")
      Reminders::DeliverJob.perform_later(invoice.id, template_key, "debtor")
    end

    # ── 스텝 산정 ────────────────────────────────────────────────────────────
    # 한 청구서는 한 번에 하나의 트랙만(ALIMTALK_TEMPLATES 발송 트랙) — 최신 약속이 있으면
    # 약속 트랙이 기본 트랙을 대체한다(PROMISE-3 기존 시퀀스 중단). promised_on이 비어 있는
    # 이력 데이터는 스텝 산정 불가 — 기본 트랙으로 되돌린다(스캔 방어).
    def steps_for(invoice)
      promise = latest_promise(invoice)
      return promise_steps(promise) if promise&.promised_on

      base_steps(invoice)
    end

    def base_steps(invoice)
      due = invoice.due_on
      {
        "invoice_notice" => due - 1,
        confirm_template_key(invoice) => due + 1,
        "requeue_d7" => due + 7,
        "final_d14" => due + 14
      }
    end

    # REM-4·SHARE-5 — D+1 분기: 미발송이면 현재 열람 이력 기준(미열람 confirm_d1·열람
    # confirm_d1_opened). 한 번 발송되면 같은 템플릿을 유지한다 — 발송 후 열림이 바뀌어 다른
    # 분기 템플릿이 D+1에 재발송되는 것을 막는다(SEC-5 동일 단계 1회). 발송 여부 판정은
    # origin 무관이다(C-1 — 수동 재발송이 보낸 분기도 확정으로 본다).
    def confirm_template_key(invoice)
      sent = MessageLog.find_by(invoice_id: invoice.id, recipient_role: :debtor,
                                template_key: CONFIRM_KEYS, status: :sent)
      return sent.template_key if sent

      invoice.view_events.any? ? "confirm_d1_opened" : "confirm_d1"
    end

    # 이 단계가 이미 발송됐는가 — origin 무관(수동 재발송분 포함 — SEC-5·C-1). U1 향은
    # 단계별 반복이 정상이라 채무자 향만 판정한다.
    def step_sent?(invoice, template_key)
      MessageLog.where(invoice_id: invoice.id, template_key: template_key,
                       recipient_role: :debtor, status: :sent).exists?
    end

    def promise_steps(promise)
      { "promise_d1" => promise.promised_on - 1,
        "promise_overdue" => promise.promised_on + 1 }
    end

    def latest_promise(invoice)
      invoice.promises
             .where(kind: Promise.kinds.slice(:this_week, :date_selected).values)
             .order(:created_at, :id).last
    end

    # ── 소급 창 ─────────────────────────────────────────────────────────────
    # 소급 허용 마지막 날 = nominal 다음 날부터 첫 평일(토→월·일→월·평일→익일 평일).
    # 평일 전용 cron이므로 주말 스텝은 이 창 안에서 월요일에 자연 이연된다.
    def window_end(nominal_on)
      date = nominal_on + 1.day
      date += 1.day while date.saturday? || date.sunday?
      date
    end

    # 소급 창 경과 스텝 — 발송 차단 사실을 이력당 1회만 기록한다(어떤 경로의 기록이든 이
    # 단계의 기록이 있으면 재기록하지 않는다 — C-1 정합·매일의 재기록 churn 방지). P4 —
    # 스킵도 발송 이력이다.
    def record_past_window_skip(invoice, template_key)
      return if MessageLog.exists?(invoice_id: invoice.id, template_key: template_key,
                                   recipient_role: :debtor)

      MessageLog.create!(
        invoice_id: invoice.id, user_id: invoice.user_id, recipient_role: :debtor,
        origin: :auto, status: :skipped, template_key: template_key,
        error_code: PAST_WINDOW,
        error_message: "발송 가능 시점(스텝 기준일부터 다음 평일)이 경과하여 소급 발송을 차단했습니다"
      )
    rescue ActiveRecord::RecordNotUnique
      nil  # 극단 경합 방어 — 기록이 겹치면 선점 기록이 존재하는 것이므로 무시한다
    end
  end
end

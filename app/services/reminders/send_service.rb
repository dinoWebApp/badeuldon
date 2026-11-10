# 단일 알림톡 발송 실행(F-REM) — 자동·수동·채무자·U1 모든 발송의 공통 실행기. 가드(수신거부→
# 보류→종결→상태→자격→상한→수신번호)를 통과해야 솔라피 발송으로 진행하며, 가드 실패는
# MessageLog에 skipped+사유로, API 실패는 failed+오류 코드로 기록한다(P4 — 모든 발신 시도는
# 기록). 자동 채무자 발송의 멱등(SEC-5)은 origin 무관 sent 판정 + 슬롯 선점(부분 유니크
# 인덱스 — debtor×pending)으로 보장하고, 채무자 향은 REM-3 발송 창(평일 09~18시 KST) 밖이면
# 다음 평일 09시로 재예약한다(02_prd_update 확정 해석 3·4 — U1 향은 창 무관 즉시). 모호
# 실패(TIMEOUT/CONNECTION)는 기록 후 재상승해 잡 계층(DeliverJob retry_on)의 제한된 재시도로
# 넘긴다.
module Reminders
  class SendService
    # REM-3 — 발송 창(평일 09~18시 KST 고정, 해제 불가). 채무자 향만 적용한다.
    WINDOW_START_HOUR = 9
    WINDOW_END_HOUR = 18
    # 선점 슬롯의 진행 중 판정 창 — 이 안에 갱신된 pending은 다른 실행이 발송 중으로 본다.
    IN_FLIGHT_WINDOW = 1.minute
    # 솔라피 알림톡 버튼 웹링크 호스트(운영 도메인). 템플릿 버튼이 `https://#{url}` 규격으로
    # 등록돼 있어 스킴이 템플릿에 박혀 있다 — 변수값은 스킴 없이 host부터 시작한다.
    LINK_HOST = "badeuldon.kr"

    # client — 솔라피 래퍼 주입 지점(W-7 — PortOne::ClientService 주입 패턴 준용 —
    # Subscriptions::UpgradeService와 같은 생성자 키워드 주입). 미주입 시 첫 발송 시점에
    # 기본 래퍼를 지연 생성한다(lazy — credentials 접근은 실제 발송 시점으로 이연).
    def initialize(invoice:, template_key:, recipient_role:, origin: :auto, scheduled_at: nil,
                   client: nil)
      @invoice = invoice
      @template_key = template_key
      @recipient_role = recipient_role.to_s
      @origin = origin.to_s
      @scheduled_at = scheduled_at
      @client = client
    end

    # 반환: :sent / :failed / :skipped / :rescheduled(창 밖 — 다음 평일 09시로 재예약) /
    # :duplicate(이미 발송됐거나 다른 실행이 진행 중 — SEC-5 흡수)
    def call
      return reschedule! if debtor? && outside_window?

      log = claim_log
      return :duplicate unless log

      failure = guard_failure
      return skip!(log, failure) if failure

      deliver!(log)
    end

    private

    # ── 발송 슬롯 확보(SEC-5) ─────────────────────────────────────────────────
    # 자동 채무자 발송의 멱등 판정("이미 이 단계를 보냈는가")은 origin 무관으로 본다 —
    # 수동 재발송이 보낸 단계를 자동 스캔이 다시 보내지 않는다(SEC-5 동일 청구·동일 단계
    # 1회). 수동(REM-8)은 재발송이 허용되어 멱등 판정 밖이며 이력을 누적하고, U1 향 이벤트
    # 알림(scheduled_at 없음)은 이벤트마다 1통이 정상이므로 중복 판정 없이 새 이력을 만든다.
    # 사전통보류(scheduled_at 지정)는 같은 예정시각의 재실행만 흡수한다(스텝별 반복이 정상).
    # DB 부분 유니크 인덱스(debtor×pending)는 "동시 진행 슬롯 1개"(경합 선점)만 보장한다.
    def claim_log
      return new_log! if manual? || (user_role? && @scheduled_at.nil?)

      log = find_existing_log
      return nil if log&.sent?
      return nil if step_sent?  # 다른 경로(수동 재발송 등)가 이미 이 단계를 발송함 — 재발송 금지
      return nil if log && in_flight?(log)

      log || new_log!  # failed·skipped·부실 pending — 갱신 경로로 재시도
    end

    def find_existing_log
      scope = MessageLog.where(invoice_id: @invoice.id, template_key: @template_key,
                               recipient_role: @recipient_role)
      scope = scope.where(scheduled_at: @scheduled_at) if user_role?
      scope.order(:id).first
    end

    # SEC-5 — origin 무관 sent 판정은 채무자 향에 한정한다. U1 향은 단계별 반복이 정상
    # (noti_prenotice D+1/7/14 3회·재약속 재알림)이라 막지 않는다.
    def step_sent?
      return false unless debtor?

      MessageLog.where(invoice_id: @invoice.id, template_key: @template_key,
                       recipient_role: @recipient_role, status: :sent).exists?
    end

    def new_log!
      MessageLog.create!(invoice_id: @invoice.id, user_id: @invoice.user_id,
                         recipient_role: @recipient_role, origin: @origin,
                         template_key: @template_key, status: :pending,
                         scheduled_at: @scheduled_at)
    rescue ActiveRecord::RecordNotUnique
      # 경합 — 선점자가 처리 중이다. 이미 발송됐거나 진행 중이면 흡수, 그 외(실패·스킵)는 갱신 경로.
      log = find_existing_log
      return nil if log.nil? || log.sent? || in_flight?(log)

      log
    end

    def in_flight?(log)
      log.pending? && log.updated_at > IN_FLIGHT_WINDOW.ago
    end

    # ── 가드(스킵 사유의 단일 출처) ───────────────────────────────────────────
    # 채무자 향만 시퀀스 가드를 적용한다. U1 향 통보는 보류·종결·수신거부 상태에서도 받아야
    # 한다(입금 완료 회신 — PROMISE-7, 수신거부 접수 — VIEW-7). 수신거부·보류는 전 채무자 향
    # 발송에, 종결·상태·상한은 시퀀스성 템플릿에 적용한다. 1회성 3종(issue_notice SHARE-6·
    # partial_paid PAY-2·paid_thanks PAY-4)은 각 이벤트 시점의 상태가 곧 발송 전제다 —
    # issue_notice는 issued 전환 직후, partial_paid는 partially_paid 상태, paid_thanks는
    # paid 전환 직후다(B-1 — unsettled?·종결 판정은 발송 전제와 양립 불가). 자격(REM-8)은
    # 자동 시퀀스성 발송에 한정된다 — 수동 발송은 Free 포함 플랜 무관(REM-8·PLAN-1)이고,
    # 1회성 3종은 자격 제한 명세가 없다.
    def guard_failure
      if debtor?
        return "REFUSED" if @invoice.client.refused?
        return "SUSPENDED" if @invoice.reminders_suspended? || @invoice.client.reminders_suspended?
        return "FINISHED" if sequence_step? && @invoice.sequence_finished?
        return "INVALID_STATUS" if sequence_step? && !@invoice.unsettled?
        return "INELIGIBLE_PLAN" if auto_sequence_step? && !@invoice.user.reminder_eligible?
        # PLAN-3 "하드리밋(수동 포함)"·REM-8 "동일 템플릿 수동 발송·상한 내" — 수동 발송은
        # 템플릿 무관으로 상한을 적용한다(Phase 6 C-1). 수동 issue_notice 반복 선택이 1회성
        # 전제를 깨고 총량 5통을 넘기는 우회를 차단한다. 수동 집계는 채무자 향 sent 전체(템플릿
        # 무관 — 시퀀스성·1회성 혼합 총량도 5통을 넘지 않게 한다). 자동 시퀀스성은 기존대로
        # sequence_step? 한정, 자동 1회성 3종(issue_notice·partial_paid·paid_thanks)은 기존대로
        # 집계 밖이다(Q10과의 긴장은 오케스트레이터가 PRD에 기록 예정).
        return "CAP_REACHED" if @origin == "manual" && manual_cap_reached?
        return "CAP_REACHED" if sequence_step? && cap_reached?
      elsif @invoice.user.phone.blank?
        return "NO_PHONE"
      end
      nil
    end

    # PLAN-3 — 시퀀스성 발송(기본·약속 트랙 + 수동)만 상한 집계 대상. 1회성 3종과 U1 알림은 밖.
    def sequence_step?
      debtor? && MessageLog::SEQUENCE_TEMPLATE_KEYS.include?(@template_key)
    end

    # REM-8 — 자격 판정 대상 발송 = 자동(origin=auto) 시퀀스성 스텝. 수동 재발송과 1회성 3종은
    # 자격 가드를 통과한다(플랜 무관 발송).
    def auto_sequence_step?
      @origin == "auto" && sequence_step?
    end

    def cap_reached?
      MessageLog.sequence_sent_count(@invoice.id) >= MessageLog::SEQUENCE_CAP
    end

    # 수동 발송(Phase 6 C-1)의 상한 집계 — 채무자 향 sent 전체(템플릿 무관). PLAN-3 하드리밋.
    def manual_cap_reached?
      MessageLog.where(invoice_id: @invoice.id, recipient_role: :debtor, status: :sent)
                .count >= MessageLog::SEQUENCE_CAP
    end

    # ── 가드 실패 기록 ──────────────────────────────────────────────────────
    # origin은 최초 생성 경로가 아니라 마지막 실행 주체를 기록한다(W-6 — 갱신 경로로
    # 재사용한 슬롯을 실행 주체 값으로 덮어쓴다. REM-6 채널 표기 정합 — 자동 스캔이 보낸
    # 발송이 수동 재시도의 「직접 발송」으로 남는 왜곡을 막는다. 발송 사실·시점·상한 집계는
    # 불변).
    def skip!(log, reason)
      log.update!(status: :skipped, origin: @origin, error_code: reason)
      :skipped
    end

    # ── 발송·기록 ────────────────────────────────────────────────────────────
    def deliver!(log)
      variables = build_variables
      response = client.send_alimtalk(template_key: @template_key, to: recipient_phone,
                                      variables: variables)
      log.update!(status: :sent, origin: @origin, sent_at: Time.current,
                  phone: recipient_phone, variables: variables,
                  provider_message_id: provider_message_id(response))
      after_send_hook
      :sent
    rescue Solapi::ApiError => e
      log.update!(status: :failed, origin: @origin, error_code: e.code,
                  error_message: e.message, phone: recipient_phone, variables: variables)
      raise if e.retryable?  # 모호 실패 — 잡 계층 재시도로 넘긴다(기록은 완료됐다)

      :failed
    end

    # 발송 성공 후속 — 자동 채무자 발송 한정. 시퀀스 종결(REM-12·13)과 약속 도과 U1 통보
    # (NOTI-1)는 발송이 실제로 성공한 이 실행에서만 확정된다. 스캔 경로와 DeliverJob 재시도
    # 경로가 같은 판정점을 공유한다.
    def after_send_hook
      return unless @origin == "auto" && debtor?

      case @template_key
      when "final_d14"
        @invoice.finish_sequence!
      when "promise_overdue"
        @invoice.finish_sequence!
        Reminders::NotifyUserService.new(invoice: @invoice,
                                         template_key: "noti_promise_unkept",
                                         client: @client).call
      end
    end

    # ── REM-3 발송 창 ────────────────────────────────────────────────────────
    def outside_window?
      now = Time.current
      now.saturday? || now.sunday? ||
        now.hour < WINDOW_START_HOUR || now.hour >= WINDOW_END_HOUR
    end

    # 창 밖 접수분 — 다음 평일 09시로 재예약한다(예약/스킵 정책 중 예약 선택 — 해석 3·4).
    # 재예약분은 접수 시점의 origin을 그대로 전달한다(B-2 — Free 수동 재예약이 origin=auto로
    # 실행돼 INELIGIBLE_PLAN skip되던 경로 해소). 예약 시점에 pending+scheduled_at 이력을
    # 먼저 남긴다(W-4 — REM-6 가시성·잡 유실 시 흔적. 동일 단계 중복 예약은 부분 유니크
    # 인덱스로 흡수되며 첫 예약이 유효 — 예약 대상 시각은 항상 다음 평일 09시로 동일).
    def reschedule!
      next_at = next_window_at
      create_scheduled_log(next_at)
      Reminders::DeliverJob.set(wait_until: next_at).perform_later(
        @invoice.id, @template_key, @recipient_role, @origin
      )
      :rescheduled
    end

    def create_scheduled_log(scheduled_at)
      MessageLog.create!(invoice_id: @invoice.id, user_id: @invoice.user_id,
                         recipient_role: @recipient_role, origin: @origin,
                         template_key: @template_key, status: :pending,
                         scheduled_at: scheduled_at)
    rescue ActiveRecord::RecordNotUnique
      nil  # 동일 단계 예약이 이미 존재 — 첫 예약이 유효(같은 다음 평일 09시 대상)
    end

    # 다음 창 개방 시각 — 평일 09:00(평일 창 개방 전이면 당일 09시). TIME-1(KST).
    def next_window_at
      now = Time.current
      today_open = now.change(hour: WINDOW_START_HOUR, min: 0)
      return today_open if weekday?(now) && now < today_open

      date = now.to_date + 1.day
      date += 1.day while date.saturday? || date.sunday?
      Time.zone.local(date.year, date.month, date.day, WINDOW_START_HOUR)
    end

    # ── 변수 조립 ────────────────────────────────────────────────────────────
    # ALIMTALK_TEMPLATES.md의 #{변수명}과 동일 키를 쓴다(솔라피 검수본 기준). 금액은 천단위
    # 구분, 날짜는 KST 기준 "M월 D일(요)" 포맷(TIME-1). 템플릿에 없는 변수는 솔라피가 무시한다
    # [INFERENCE] — 단일 base 맵으로 18종을 모두 커버한다. 버튼 웹링크 변수(url·complete_url·
    # pending_url)는 전 발송에 실어 보낸다 — 미실어 발송은 치환 실패로 거부되거나 `#{url}` 원문이
    # 노출될 위험이 있고, 템플릿에 없는 키는 무시되므로 무해하다.
    def build_variables
      variables = {
        "발행인명" => @invoice.issuer_display_name,
        "거래처명" => @invoice.client.name,
        "청구서명" => @invoice.issue_number,
        "금액" => delimited(@invoice.total_amount),
        "잔액" => delimited(@invoice.remaining_amount),
        "입금금액" => delimited(@invoice.payments.order(:id).last&.amount.to_i),
        "만기일" => format_date(@invoice.due_on),
        "약속일" => promise_label,
        "url" => button_url
      }
      if @template_key == "noti_prenotice"
        variables["complete_url"] = prenotice_button_url
        variables["pending_url"] = prenotice_button_url
      end
      variables
    end

    # 버튼 웹링크 — 솔라피 템플릿의 `https://#{url}` 버튼 치환값(ALIMTALK_TEMPLATES.md 버튼 명세).
    # 채무자 향은 전 템플릿 뷰어 /b/{토큰}(VIEW-8 — 뷰어 밖 링크·앱 내비 금지·SURF-4). U1 향은
    # noti_due_soon만 /app 전체 현황, 나머지 noti는 해당 청구서 상세(「대시보드에서 확인」 버튼).
    def button_url
      if debtor?
        "#{LINK_HOST}#{Rails.application.routes.url_helpers.viewer_path(@invoice.token)}"
      elsif @template_key == "noti_due_soon"
        "#{LINK_HOST}/app"
      else
        "#{LINK_HOST}#{Rails.application.routes.url_helpers.app_invoice_path(@invoice)}"
      end
    end

    # REM-11 사전통보 전용 버튼 2종 — 마감하기(PAY-1 원클릭 마감)·보류하기(REM-7) 액션이 함께
    # 있는 청구서 상세로 보낸다(버튼 라벨만 다르고 목적지는 동일).
    def prenotice_button_url
      "#{LINK_HOST}#{Rails.application.routes.url_helpers.app_invoice_path(@invoice)}"
    end

    # PROMISE-4·ALIMTALK_TEMPLATES — U1 향 noti_promise의 this_week 약속은 날짜 대신
    # "이번 주 내"로 치환한다. 채무자 향 템플릿(promise_d1·promise_overdue)은 실제 날짜를 유지.
    def promise_label
      promise = latest_promise
      return "" unless promise&.promised_on
      return "이번 주 내" if @template_key == "noti_promise" && promise.this_week?

      format_date(promise.promised_on)
    end

    def latest_promise
      @latest_promise ||= @invoice.promises
                                  .where(kind: Promise.kinds.slice(:this_week, :date_selected).values)
                                  .order(:created_at, :id).last
    end

    def format_date(date)
      "#{date.mon}월 #{date.day}일(#{WEEKDAY_NAMES[date.wday]})"
    end

    def delimited(amount)
      ActiveSupport::NumberHelper.number_to_delimited(amount.to_i)
    end

    # [INFERENCE] 솔라피 응답의 메시지 식별자 위치 — v4 단일 발송 응답 최상위 messageId 가정.
    def provider_message_id(response)
      return unless response.is_a?(Hash)

      response[:messageId] || response.dig(:message, :messageId)
    end

    # 솔라피 래퍼 — client: 미주입 시 첫 사용 시점에 기본 래퍼를 지연 생성한다(W-7 주석 참조).
    def client
      @client ||= Solapi::ClientService.new
    end

    def recipient_phone
      debtor? ? @invoice.client.phone : @invoice.user.phone
    end

    def debtor?
      @recipient_role == "debtor"
    end

    def user_role?
      @recipient_role == "user"
    end

    def manual?
      @origin == "manual"
    end

    def weekday?(time)
      !time.saturday? && !time.sunday?
    end

    WEEKDAY_NAMES = %w[일 월 화 수 목 금 토].freeze
  end
end

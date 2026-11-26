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
    # REM-3 — 발송 창 상한 경계(평일 09~18시 KST 고정, 확장 불가). 2026-11-16부터 사용자가
    # 이 경계 **내에서만** 요일·시간대를 축소 설정한다(User.remind_start_hour·remind_end_hour·
    # remind_allowed_wdays — 판정은 User#remind_window_open? 단일 출처). 채무자 향만 적용한다.
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
      # 이미 발송된 자동 단계는 재예약하지 않는다(W-1 마감 리뷰 — REM-3 재예약분 실행 정합
      # 2026-11-26). 창 판정(outside_window?)이 먼저면 스캔 시각이 회원 허용 시간 밖일 때
      # 이미 sent인 단계에도 예약 슬롯이 생기고, 다음 날 실행은 step_sent?로 duplicate가
      # 되어 슬롯이 영구 pending으로 남는다(유령 「예정」 행). 수동·U1 향·1회성(partial_paid)
      # 은 이 판정 밖이다 — claim_log 이후의 기존 경로가 그대로 처리한다. 창 안의 정상 경로는
      # claim_log가 같은 판정(step_sent?)을 하므로 동작 변화가 없다.
      return :duplicate if auto_sequence_step? && step_sent?
      return reschedule! if debtor? && outside_window?

      log = claim_log
      return :duplicate unless log
      mark_execution_started!(log)

      failure = guard_failure
      return skip!(log, failure) if failure

      deliver!(log)
    end

    private

    # ── 발송 슬롯 확보(SEC-5) ─────────────────────────────────────────────────
    # 자동 채무자 발송의 멱등 판정("이미 이 단계를 보냈는가")은 origin 무관으로 본다 —
    # 수동 재발송이 보낸 단계를 자동 스캔이 다시 보내지 않는다(SEC-5 동일 청구·동일 단계
    # 1회). 수동(REM-8)은 재발송이 허용되어 멱등 판정 밖이며 이력을 누적한다 — 단, 창 밖
    # 재예약분이 남긴 pending 예약 슬롯(REM-3 선기록)은 예외로 재사용해 이력을 늘리지 않는다
    # (new_log!의 유니크 복구 — 재예약분 실행 정합 2026-11-26). U1 향 이벤트 알림
    # (scheduled_at 없음)은 이벤트마다 1통이 정상이므로 중복 판정 없이 새 이력을 만든다.
    # 사전통보류(scheduled_at 지정)는 같은 예정시각의 재실행만 흡수한다(스텝별 반복이 정상).
    # Q23(2026-11-16 확정) — partial_paid도 이벤트성이다: 부분입금이 추가로 발생할 때마다
    # 재발송이 정상이므로(1회성 발송 — PLAN-3 상한 집계 밖 유지, Q10) sent·스텝 중복 판정을
    # 통과해 건마다 새 이력을 만든다. 경합 선점은 아래 부분 유니크 인덱스가 그대로 담당한다.
    # DB 부분 유니크 인덱스(debtor×pending)는 "동시 진행 슬롯 1개"(경합 선점)만 보장한다.
    def claim_log
      return new_log! if manual? || (user_role? && @scheduled_at.nil?) || per_event_debtor_notice?

      log = find_existing_log
      return nil if log&.sent?
      return nil if step_sent?  # 다른 경로(수동 재발송 등)가 이미 이 단계를 발송함 — 재발송 금지
      return nil if log && in_flight?(log)

      # 예약 슬롯 우선(REM-3 재예약분 실행 정합 — 2026-11-26) — 갱신 경로 대상(failed·skipped)
      # 보다 pending 슬롯이 남아 있으면 그 슬롯을 실행한다. 더 오래된 failed·skipped 이력을
      # 재사용하면 발송 자체는 일어나도 예약 슬롯이 영구 pending으로 남는다(발송 이력의
      # 「발송 예정」 유령 행·이후 reschedule! 예약 흡수). 슬롯이 방금 갱신됐다면 다른 실행이
      # 발송 중이므로 duplicate로 흡수한다(SEC-5).
      # 슬롯 우선은 채무자 향 부분 유니크 인덱스(debtor×pending — 같은 청구·템플릿의 pending
      # 슬롯 0 또는 1행) 전제다. U1 향 예정 알림에는 그 인덱스가 없어 다른 예정 시각의
      # pending 이력이 공존할 수 있고(예: 전날 실행 크래시 잔여) 멱등 규칙은 "같은 예정 시각의
      # 재실행만 흡수"(find_existing_log의 scheduled_at 필터)이므로 예정 시각 무관 슬롯
      # 재사용을 하지 않는다(6차 한정 — 2026-11-26) — 재사용하면 오늘 scheduled_at의 이력이
      # 남지 않아 잡 재시도 시 같은 알림이 재발송된다(SEC-5·P4). U1 향은 아래에서
      # log || new_log!의 5차 이전 경로를 그대로 탄다.
      slot = find_pending_slot if debtor?
      return nil if slot && in_flight?(slot)

      slot || log || new_log!  # failed·skipped·부실 pending — 갱신 경로로 재시도
    end

    def find_existing_log
      scope = MessageLog.where(invoice_id: @invoice.id, template_key: @template_key,
                               recipient_role: @recipient_role)
      scope = scope.where(scheduled_at: @scheduled_at) if user_role?
      scope.order(:id).first
    end

    # 같은 청구·템플릿·역할의 pending 슬롯(예약 슬롯 포함). 부분 유니크 인덱스(debtor×pending)가
    # "동시 진행 슬롯 1개"를 보장하므로 0 또는 1행이다. new_log!의 유니크 위반 복구와 갱신
    # 경로의 슬롯 우선에서 사용한다. U1 향은 인덱스 대상이 아니라 예약 슬롯 개념이 없다 —
    # 호출 전제가 어긋나도 nil로 수렴시킨다(방어).
    def find_pending_slot
      return nil unless debtor?

      MessageLog.where(invoice_id: @invoice.id, template_key: @template_key,
                       recipient_role: @recipient_role, status: :pending)
                .order(:id).first
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
      # 유니크 위반이 뜻하는 것은 "같은 청구·템플릿(채무자)의 pending 슬롯이 이미 있다"는
      # 것(부분 유니크 인덱스 — debtor×pending)이다. 복구는 가장 오래된 이력이 아니라 그
      # 슬롯을 찾아 돌려준다 — 창 밖 재예약(예약 슬롯 선기록, REM-3)분의 실행이 과거 sent
      # 이력을 "이미 보냄"으로 착각해 흡수하고 예약 슬롯을 영구 pending으로 남기던 결함의
      # 수정(재예약분 실행 정합 — 2026-11-26). 수동 발송은 재발송이 허용되므로(REM-8) 같은
      # 템플릿의 sent 이력이 있어도 슬롯을 발송해야 회원 안내("다음 평일 오전 9시에
      # 발송됩니다")와 일치한다. 슬롯이 없거나(경합에서 이미 처리됨) 진행 중이면 duplicate로
      # 흡수하고, 그 외에는 슬롯을 갱신 경로로 이어 발송한다.
      slot = find_pending_slot
      return nil if slot.nil? || in_flight?(slot)

      slot
    end

    # 선점 슬롯의 진행 중 판정(SEC-5). pending이고 최근 IN_FLIGHT_WINDOW 안에 갱신된 행을
    # "다른 실행이 발송 중"으로 본다. 예약 슬롯(scheduled_at 있음)은 한 단계를 더 거친다 —
    # updated_at >= scheduled_at(실행 시작 표시가 있을 때)만 진행 중이다(C-1 마감 리뷰 —
    # 재예약분 실행 정합 2026-11-26). 예약 슬롯은 접수 시각에 생성되므로 창 시작 직전 1분에
    # 접수된 슬롯(예: 08:59:30 접수·09:00 예약)은 updated_at < scheduled_at이라 진행 중이
    # 아니게 되고, 그렇지 않으면 다음 실행이 :duplicate로 흡수돼 슬롯이 영구 pending으로
    # 남았다. 실행 시작 표시(mark_execution_started!의 touch) 뒤에는 updated_at >=
    # scheduled_at이 돼 1분 창이 다시 유효해진다 — 같은 예약 슬롯에 대한 두 번째 실행은
    # duplicate로 흡수된다(SEC-5). U1 향 예정 알림(오늘 09시 예약·09시 생성)은 생성 직후
    # updated_at >= scheduled_at이라 기존과 같이 생성 후 1분간 진행 중 취급이다.
    def in_flight?(log)
      return false unless log.pending?
      return false unless log.updated_at > IN_FLIGHT_WINDOW.ago
      return true if log.scheduled_at.blank?

      log.updated_at >= log.scheduled_at
    end

    # 예약 슬롯의 실행 시작 표시(C-1) — touch로 updated_at을 실행 시점으로 올려 in_flight?의
    # "진행 중" 근거를 만든다. 예약 슬롯(scheduled_at 있음)만 표시한다 — 표시가 없는 슬롯
    # (즉시 발송 신규 이력 등)의 1분 창 동작은 바꾸지 않는다.
    def mark_execution_started!(log)
      log.touch if log.scheduled_at.present?
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
        # 무관 — 시퀀스성·1회성 혼합 총량도 5통을 넘지 않게 한다). 자동 시퀀스성의 집계는
        # cap_reached?(Q28 — 시퀀스성 origin 무관 + 수동 템플릿 무관 합산)로, 수동 발송이
        # 많은 청구의 다음 자동 단계도 5통에서 막힌다(Q11). 자동 1회성 3종(issue_notice·
        # partial_paid·paid_thanks)은 이벤트성이라 양쪽 집계 모두 밖이다(Q10).
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

    # Q23 — 부분입금 안내(partial_paid)는 이벤트성 발송이다. 추가 부분입금마다 재발송이
    # 정상이므로 스텝 sent 판정(step_sent?)·갱신 경로를 거치지 않고 건마다 새 이력으로
    # 진행한다. PLAN-3 상한 집계 밖(1회성 3종 제외 — Q10)은 기존 guard 로직이 유지한다.
    def per_event_debtor_notice?
      debtor? && @template_key == "partial_paid"
    end

    # PLAN-3·Q28 — 자동 시퀀스 단계의 상한 판정. 판정의 단일 출처는
    # Invoice#reminder_cap_reached?(집계는 MessageLog.cap_sent_count — 채무자 향 sent 중
    # 시퀀스성 템플릿 origin 무관 + 수동 발송 템플릿 무관 — Q11)다. 사전통보·재개 판정
    # (DispatchService#steps_due_today)과 상세 화면 컨텍스트도 같은 모델 메서드에 위임하므로
    # 이곳에서 집계 로직을 복제하지 않는다. 자동 1회성 3종은 sequence_step?가 아니어도 되고
    # 집계에도 없다(Q10 — 이벤트성 발송은 상한과 무관).
    def cap_reached?
      @invoice.reminder_cap_reached?
    end

    # 수동 발송(Phase 6 C-1)의 상한 집계 — 채무자 향 sent 전체(템플릿 무관). PLAN-3 하드리밋.
    # 자동 상한(cap_reached?·Q28)과 달리 origin·템플릿 구분 없는 총량이다. 판정의 단일 출처는
    # Invoice#manual_reminder_cap_reached?다 — 상세 화면의 「지금 1통 보내기」·「다음 안내」
    # 숨김 판정(RemindersContext @manual_cap_reached)도 같은 메서드에 위임한다(W-3 마감 리뷰
    # 2026-11-26 — 자동 1회성만으로 수동 상한에 걸린 청구의 죽은 버튼 방지).
    def manual_cap_reached?
      @invoice.manual_reminder_cap_reached?
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
      # Q15·NOTI-3(W-2 방침 (b)) — credentials에 템플릿 코드가 없는 키(noti_recurring_issued/
      # held 등 등록 전 초안)는 확정 실패가 아니라 "등록 전" 상태다. failed로 남기면 재시도
      # 잡 노이즈·P4 이력 왜곡이 생기므로 skipped(NO_TEMPLATE)로 기록하고 정상 종료한다 —
      # 발신 측(예: 반복 청구 발행)은 무영향이며, 템플릿이 등록되면 다음 발행부터 자동 활성화.
      return skip_no_template!(log, e) if e.code == "MISSING_TEMPLATE"

      log.update!(status: :failed, origin: @origin, error_code: e.code,
                  error_message: e.message, phone: recipient_phone, variables: variables)
      raise if e.retryable?  # 모호 실패 — 잡 계층 재시도로 넘긴다(기록은 완료됐다)

      :failed
    end

    # 등록 전 템플릿의 skipped 기록 — P4(모든 발신 시도는 기록)의 흡수 경로. 멱등 재실행은
    # claim_log가 skipped 슬롯을 갱신 경로로 재사용해 이력이 누적되지 않는다.
    def skip_no_template!(log, error)
      log.update!(status: :skipped, origin: @origin, error_code: "NO_TEMPLATE",
                  error_message: error.message, phone: recipient_phone)
      :skipped
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

    # ── REM-3 발송 창(2026-11-16 확정 — 사용자별 허용 요일·시간대 설정) ──────
    # 고정 경계(평일 09:00~18:00) 내에서 사용자가 축소 설정한 허용 창 판정. 경계 확장(야간·주말)
    # 불가는 User 모델 검증으로 보장되고, 창 밖 접수분은 다음 허용 슬롯으로 이월된다.
    def outside_window?
      !@invoice.user.remind_window_open?(Time.current)
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

    # 다음 창 개방 시각 — 사용자 설정 허용 요일·시간대의 다음 슬롯(User#next_remind_slot).
    # 기본 설정(월~금 9~18시)에서는 기존과 동일하게 "평일 09:00(개방 전이면 당일 09시)"로
    # 계산된다. TIME-1(KST).
    def next_window_at
      @invoice.user.next_remind_slot(Time.current)
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
      # NOTI-3(Q15·B-5 21번) — 반복 청구 보류 사유. 직전 발행 청구(last_invoice)에 연결된
      # 스케줄의 last_skip_reason을 읽는다(등록 전 템플릿이므로 실발송은 등록 후부터).
      if @template_key == "noti_recurring_held"
        variables["보류사유"] = recurring_schedule&.last_skip_reason.to_s
      end
      variables
    end

    # U1 향 noti_recurring_*의 문맥 스케줄 — last_invoice로 역조회한다. held 인큐는
    # last_invoice가 있는 스케줄에 한정되므로(IssueService#enqueue_notifications) nil 여지는
    # 레지스트리 방어로만 남는다.
    def recurring_schedule
      @recurring_schedule ||= RecurringInvoice.find_by(last_invoice_id: @invoice.id)
    end

    # 버튼 웹링크 — 솔라피 템플릿의 `https://#{url}` 버튼 치환값(ALIMTALK_TEMPLATES.md 버튼 명세).
    # 채무자 향은 전 템플릿 뷰어 /b/{토큰}(VIEW-8 — 뷰어 밖 링크·앱 내비 금지·SURF-4). U1 향은
    # noti_due_soon만 /app 전체 현황, 나머지 noti는 해당 청구서 상세(「대시보드에서 확인」 버튼).
    def button_url
      if debtor?
        "#{LINK_HOST}#{Rails.application.routes.url_helpers.viewer_path(@invoice.token)}"
      elsif @template_key == "noti_due_soon"
        "#{LINK_HOST}/app"
      elsif @template_key == "noti_recurring_held"
        # NOTI-3(Q15·B-5 21번) — "설정 확인하기"는 반복 청구 스케줄 상세. 문맥 스케줄이
        # 조회되지 않는 비정상 경로에서는 목록으로 폴백한다.
        schedule = recurring_schedule
        url_helpers = Rails.application.routes.url_helpers
        "#{LINK_HOST}#{schedule ? url_helpers.app_recurring_invoice_path(schedule) : url_helpers.app_recurring_invoices_path}"
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

    WEEKDAY_NAMES = %w[일 월 화 수 목 금 토].freeze
  end
end

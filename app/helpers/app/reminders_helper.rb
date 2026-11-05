module App
  # F-REM 화면 공용(REM-6/7/8·VIEW-7) — 알림톡 템플릿 한글 라벨·발송 상태 배지·스킵 사유 문구·
  # 안내 상태 배지의 단일 출처. 뷰와 컨트롤러 플래시(`helpers.` 프록시)가 함께 사용한다.
  # template_key는 credentials solapi.template_ids의 키(ALIMTALK_TEMPLATES.md)와 동일 문자열이다.
  module RemindersHelper
    # REM-6 — template_key의 U1용 한글 라벨(ALIMTALK_TEMPLATES.md 18종). 미지 키는 원문 폴백.
    TEMPLATE_LABELS = {
      "invoice_notice" => "만기 예정 안내",
      "confirm_d1" => "입금 확인 안내",
      "confirm_d1_opened" => "입금 확인 안내(열람 건)",
      "requeue_d7" => "재안내(만기 7일 후)",
      "final_d14" => "최종 안내(만기 14일 후)",
      "issue_notice" => "발행 안내",
      "promise_d1" => "약속일 전날 안내",
      "promise_overdue" => "약속일 경과 안내",
      "partial_paid" => "부분입금 확인·잔액 안내",
      "paid_thanks" => "마감 확인·감사 안내",
      "noti_opened" => "열람 알림",
      "noti_promise" => "약속 접수 알림",
      "noti_deposit_reply" => "입금 완료 회신 알림",
      "noti_inquiry" => "문의 접수 알림",
      "noti_refusal" => "수신 거부 접수 알림",
      "noti_prenotice" => "발송 예정 사전 통보",
      "noti_promise_unkept" => "약속 미이행 알림",
      "noti_due_soon" => "만기 임박 알림"
    }.freeze

    # REM-6 — 스킵 사유(error_code — Reminders::SendService·DispatchService)의 U1용 문구.
    # 문구는 "독촉·연체" 대신 "안내" 어휘를 쓴다(LP-12·REM-2 톤 준칙 — U1 향 UI 문구).
    SKIP_REASON_LABELS = {
      "REFUSED" => "거래처가 추가 안내 수신을 거부하여 발송하지 않았습니다",
      "SUSPENDED" => "안내가 보류 중이어서 발송하지 않았습니다",
      "FINISHED" => "정기 안내가 종결되어 발송하지 않았습니다",
      "INVALID_STATUS" => "발송할 수 없는 청구서 상태여서 발송하지 않았습니다",
      "INELIGIBLE_PLAN" => "무료 플랜은 자동 안내 대상이 아니어서 발송하지 않았습니다",
      "CAP_REACHED" => "청구 건당 안내 상한(5통)에 도달하여 발송하지 않았습니다",
      "NO_PHONE" => "알림 수신 번호가 없어 발송하지 않았습니다",
      "PAST_WINDOW" => "발송 가능 시점이 경과하여 발송하지 않습니다"
    }.freeze

    def message_template_label(template_key)
      TEMPLATE_LABELS.fetch(template_key.to_s, template_key)
    end

    def message_log_skip_reason(error_code)
      SKIP_REASON_LABELS.fetch(error_code.to_s, "발송하지 않았습니다")
    end

    # REM-6 — 발송 상태 배지(DESIGN-2 상태색 3종 준용: 성공 녹색·실패 주황·예정/제외 중립).
    def message_log_status_badge(log)
      spec = {
        "pending" => [ "예정", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ],
        "sent" => [ "발송됨", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200" ],
        "failed" => [ "실패", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ],
        "skipped" => [ "제외", "bg-stone-100 text-stone-500 ring-1 ring-inset ring-stone-200" ]
      }.fetch(log.status)
      content_tag :span, spec.first,
                  class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{spec.last}"
    end

    # 발송 이력 한 줄의 수신자·경로 표기 — 거래처 향은 자동/직접(origin)을 함께 안내한다(REM-8).
    def message_log_channel_label(log)
      if log.user?
        "나에게 알림"
      elsif log.manual?
        "거래처 · 직접 발송"
      else
        "거래처 · 자동 발송"
      end
    end

    # REM-7·VIEW-7 — 청구서의 안내 상태 배지 묶음(수신거부 주황·보류/종결 중립·진행 녹색).
    def reminder_state_badges(invoice)
      badges = []
      if invoice.client.refused?
        badges << [ "수신 거부", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ]
      end
      if invoice.reminders_suspended? || invoice.client.reminders_suspended?
        badges << [ "보류", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ]
      end
      badges << [ "종결", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200" ] if invoice.sequence_finished?
      if badges.empty? && invoice.unsettled? && invoice.reminders_active?
        badges << [ "자동 안내 중", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200" ]
      end
      safe_join(badges.map { |label, tone| reminder_badge_span(label, tone) }, " ")
    end

    # REM-7·VIEW-7 — 거래처의 안내 상태 배지(상세 화면 공용).
    def client_reminder_badge(client)
      if client.refused?
        reminder_badge_span("수신 거부", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200")
      elsif client.reminders_suspended?
        reminder_badge_span("보류", "bg-stone-100 text-stone-600 ring-1 ring-inset ring-stone-200")
      else
        reminder_badge_span("자동 안내 중", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200")
      end
    end

    private

    def reminder_badge_span(label, tone)
      content_tag :span, label,
                  class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{tone}"
    end
  end
end

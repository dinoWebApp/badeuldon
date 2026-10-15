module App
  # 요금제 페이지(F-PLAN) 뷰 헬퍼 — 현재 플랜 배지·상태 설명 문구. 표현 로직을 뷰에서 떼어낸다.
  module BillingsHelper
    # 현재 플랜 배지 — Free/Plus + 생명주기 상태(체험·이용·해지·만료).
    def plan_badge_label(subscription)
      if subscription.plus?
        { trialing: "Plus 체험 중", active: "Plus 이용 중", cancelled: "Plus 해지 예정",
          expired: "만료" }.fetch(subscription.status.to_sym)
      else
        "Free 이용 중"
      end
    end

    # 배지 색 — Plus 계열은 딥 그린, 만료·Free는 무채색(DESIGN-2 강조 규칙 준용).
    def plan_badge_classes(subscription)
      if subscription.plus? && !subscription.expired?
        "bg-emerald-800 text-white"
      else
        "bg-stone-100 text-stone-600"
      end
    end

    # 상태 설명 — 체험 종료일·결제 주기·해지 예정일을 사용자 언어로 안내한다(TIME-1 KST 표기).
    def plan_status_description(subscription)
      case subscription.status.to_sym
      when :trialing
        "#{display_date(subscription.trial_ends_at)}까지 무료입니다. 이전에 카드를 등록하면 자동 결제로 전환됩니다."
      when :active
        if subscription.plus?
          "결제 주기: #{display_datetime(subscription.current_period_start)} ~ #{display_datetime(subscription.current_period_end)}"
        else
          "월 청구 #{Invoice::FREE_MONTHLY_INVOICE_LIMIT}건 · 거래처 #{Client::FREE_CLIENT_LIMIT}개 한도로 이용 중입니다."
        end
      when :cancelled
        "#{display_datetime(subscription.current_period_end)}까지 Plus로 이용할 수 있습니다. 이후 Free로 전환됩니다."
      else
        "만료되었습니다. 카드를 등록하면 Plus를 다시 이용할 수 있습니다."
      end
    end

    # 수금 패스 한 줄 요약 — "잔여 7/10 · 2026-12-30까지"
    def payment_pass_summary(pass)
      "잔여 #{pass.remaining_uses}/#{pass.total_uses} · #{display_date(pass.expires_at)}까지"
    end
  end
end

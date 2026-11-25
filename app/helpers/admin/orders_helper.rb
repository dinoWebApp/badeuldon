# ADMIN-4·11 — 주문 상품 라벨·환불 실행 확인 문구(표현 로직을 뷰에서 떼어내는 헬퍼).
# 내용증명·세금계산서 주문은 product가 collection_pass라 item_type으로만 구분된다(Order 주석).
module Admin::OrdersHelper
  ITEM_TYPE_LABELS = { "pass" => "수금 패스", "legal_doc" => "내용증명 양식",
                       "tax_invoice" => "전자세금계산서 발행" }.freeze

  def order_item_label(order)
    ITEM_TYPE_LABELS.fetch(order.item_type, order.item_type.humanize)
  end

  # ADMIN-11(Q27) — 상품별 환불 실행 효과 요약(폼 안내 문구·확인 대화창 공용. W-5 —
  # 기간 몰수·차감 대상·재다운로드 불가를 상품별로 정확히 고지한다).
  def refund_effect_summary(order)
    if order.plus_monthly?
      "해당 회원의 Plus 구독이 즉시 Free로 바뀌고 남은 결제 기간은 소멸됩니다" \
      "(이 주문 금액만 환불 — 다른 결제는 환불되지 않습니다)"
    elsif order.collection_pass? && order.pass?
      "이 주문으로 발급된 패스가 아니라 회원이 보유한 수금 패스 중 만료가 임박한 것부터 " \
      "#{PaymentPass::TOTAL_USES}건 차감됩니다(잔여가 모자라면 남은 만큼만 차감)"
    else
      "이미 발급·발행된 문서는 그대로입니다. 환불 뒤에는 회원이 앱에서 다시 내려받을 수 없습니다"
    end
  end

  # ADMIN-11(Q27) — 제출 전 확인 대화창에 실행 효과(환불 금액·상품별 되돌리기)를 보여준다.
  def refund_confirm_message(order)
    "환불을 실행할까요? #{number_to_currency(order.amount, unit: "₩", precision: 0)}이 포트원으로 전액 즉시 환불되고 #{refund_effect_summary(order)}. 이 작업은 되돌릴 수 없습니다."
  end
end

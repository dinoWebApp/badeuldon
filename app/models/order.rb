# 주문(F-PLAN — PLAN-2/4/5) — 포트원(KG이니시스) 결제 단위. 구독(Plus 월)·수금 패스(단건) 모두
# 주문 레코드로 남는다(P4 발신·거래 기록 영구 보존과 같은 원칙). pg_order_id는 서버가 생성한
# UUID로, 위젯 결제 요청(paymentId)·승인 confirm·웹훅 정합 확인이 모두 이 값 기준이다.
class Order < ApplicationRecord
  # PLAN-4 — 수금 패스: 10건 4,000원(부가세 포함)
  PRODUCT_AMOUNTS = { plus_monthly: Subscription::PLUS_MONTHLY_PRICE, collection_pass: 4_000 }.freeze

  belongs_to :user

  enum :product, { plus_monthly: 0, collection_pass: 1 }
  enum :status, { pending: 0, paid: 1, failed: 2, cancelled: 3 }, default: :pending

  validates :pg_order_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # 상품별 정가 — 주문 생성은 항상 이 금액으로 한다(클라이언트 값 신뢰 금지).
  def self.amount_for(product)
    PRODUCT_AMOUNTS.fetch(product.to_sym)
  end
end

# 주문(F-PLAN — PLAN-2/4/5) — 포트원(KG이니시스) 결제 단위. 구독(Plus 월)·수금 패스(단건) 모두
# 주문 레코드로 남는다(P4 발신·거래 기록 영구 보존과 같은 원칙). pg_order_id는 서버가 생성한
# UUID로, 위젯 결제 요청(paymentId)·승인 confirm·웹훅 정합 확인이 모두 이 값 기준이다.
class Order < ApplicationRecord
  # PLAN-4 — 수금 패스: 10건 4,000원(부가세 포함)
  PRODUCT_AMOUNTS = { plus_monthly: Subscription::PLUS_MONTHLY_PRICE, collection_pass: 4_000 }.freeze

  belongs_to :user

  # LEGAL-2(Q5) — 내용증명 양식 건당 5,000원. 결제 체인(위젯→callback→PurchaseService·웹훅)은
  # 수금 패스 주문과 동일한 orders 레코드로 흐르며 item_type으로만 구분한다. product 컬럼은
  # null: false 제약이라 내용증명 주문에도 단건 결제 채널 동작상 collection_pass 값을 채운다
  # (channel·승인 로직은 product를 읽지 않고, 상품별 확정 분기는 전부 item_type 기준 —
  # FulfillPassService·Webhooks::PortOneController 참조).
  LEGAL_DOC_PRICE = 5_000

  enum :product, { plus_monthly: 0, collection_pass: 1 }
  enum :status, { pending: 0, paid: 1, failed: 2, cancelled: 3 }, default: :pending
  # LEGAL-2 — 주문 품목 구분(pass=기존 결제 전부 / legal_doc=내용증명 양식 1건).
  enum :item_type, { pass: 0, legal_doc: 1 }, default: :pass

  # ADMIN-4 — 관리자 목록 필터용 스코프. refunded는 refunded_at 기준(환불 제외 매출 집계와 정합).
  scope :paid, -> { where(status: :paid) }
  scope :failed, -> { where(status: :failed) }
  scope :refunded, -> { where.not(refunded_at: nil) }
  scope :not_refunded, -> { where(refunded_at: nil) }
  # LEGAL-2 — 내용증명 양식 주문 목록(App::LegalDocumentsController#index)
  scope :legal_docs, -> { where(item_type: :legal_doc) }

  validates :pg_order_id, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # ADMIN-4 — 환불 기록(PLAN-6 CS 예외 절차). 실제 PG 환불은 포트원 콘솔에서 수동 수행(PLAN-5)하며
  # 이 메서드는 그 결과를 서비스 측에 기록한다(refunded_at·refund_reason — 감사·매출 집계 제외용).
  # 감사 로그 기록은 모델이 하지 않는다(§4.2 — 컨트롤러가 AuditLogs::RecordService 경유).
  def mark_refunded!(reason)
    raise ArgumentError, "환불 사유는 필수입니다" if reason.blank?
    return false if refunded?

    update!(refunded_at: Time.current, refund_reason: reason)
    true
  end

  # ADMIN-4 — 환불 여부 판정(refunded_at 존재 기준 — 상태 enum과 분리해 paid 이력을 보존한다).
  def refunded?
    refunded_at.present?
  end

  # 상품별 정가 — 주문 생성은 항상 이 금액으로 한다(클라이언트 값 신뢰 금지).
  def self.amount_for(product)
    PRODUCT_AMOUNTS.fetch(product.to_sym)
  end
end

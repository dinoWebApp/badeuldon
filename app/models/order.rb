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
  # LEGAL-2 — 주문 품목 구분(pass=기존 결제 전부 / legal_doc=내용증명 양식 1건 /
  # tax_invoice=전자세금계산서 발행 수수료 1건 — TAX-1·Q21, 기존 pass(0)·legal_doc(1) 불변).
  enum :item_type, { pass: 0, legal_doc: 1, tax_invoice: 2 }, default: :pass

  # ADMIN-4 — 관리자 목록 필터용 스코프. refunded는 refunded_at 기준(환불 제외 매출 집계와 정합).
  scope :paid, -> { where(status: :paid) }
  scope :failed, -> { where(status: :failed) }
  scope :refunded, -> { where.not(refunded_at: nil) }
  scope :not_refunded, -> { where(refunded_at: nil) }
  # LEGAL-2 — 내용증명 양식 주문 목록(App::LegalDocumentsController#index)
  scope :legal_docs, -> { where(item_type: :legal_doc) }
  # TAX-1(Q21) — 전자세금계산서 발행 수수료 주문 목록(App::TaxInvoicesController)
  scope :tax_invoices, -> { where(item_type: :tax_invoice) }

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

  # PLAN-5 결제 확정 검증 실패(재리뷰 R-1·R-2·R2-5) — 금액·채널·통화가 주문과 일치하지 않아
  # 확정점(Orders::FulfillPassService)이 거절한 결제의 표식. 코드·안내 문구의 단일 출처다
  # (PurchaseService·Webhooks::PortOneController가 이 메서드로 기록 — 관리자 주문 상세와
  # 회원 안내 분기(R2-2)가 metadata.code로 판정한다).
  VERIFICATION_FAILED_CODE = "PAYMENT_VERIFICATION_FAILED"
  # F-4(마감 리뷰 2026-11-25) — 검증 항목에 통화를 명시한다(PortOne::PaymentVerifier#verify_currency!).
  VERIFICATION_FAILED_MESSAGE = "결제 금액·결제 채널·결제 통화가 주문과 일치하지 않습니다"

  # F-2(마감 리뷰 2026-11-25) — 검증 실패 주문의 회원 안내(두 컨트롤러 상세 착지 flash 공용).
  # 자동 확인·관리자 알림이 없으므로 "확인 중"이라는 함축 없이 사실대로 안내하고 문의(티켓)로
  # 행동을 유도한다(뷰 본문은 이 문장의 뒤 절을 제목+본문으로 나눠 쓴다).
  VERIFICATION_FAILED_USER_NOTICE = "결제 확인에 실패했습니다. 다시 결제하지 말고 고객지원(문의)으로 연락해 주세요."

  # F-1(마감 리뷰 2026-11-25) — 재주문 차단 안내(주문 생성 3곳의 create 가드 공용 — 상세 화면
  # 밖 진입: 내용증명 목록·청구서 상세 발행·요금제 수금 패스).
  VERIFICATION_FAILED_REORDER_NOTICE = "결제 확인에 실패한 주문이 있습니다. 고객지원(문의)으로 연락해 주세요."

  # F-3(마감 리뷰 2026-11-25) — pending 회복 대기 착지 안내(PurchaseService#recovery_message와
  # 같은 취지 — 결제 확정 경로는 건드리지 않고 컨트롤러 착지 안내만 같은 취지로 맞춘다).
  PENDING_RECOVERY_NOTICE = "결제 확인이 지연되고 있습니다. 승인 결과는 잠시 후 자동으로 반영됩니다."

  # 검증 실패 주문 판정 — failed 상태이고 metadata.code가 검증 실패 코드인 건. 명확한 PG 거절
  # 실패(record_failure!)와 구분한다(검증 실패는 재결제를 유도하면 안 된다 — R2-2).
  def verification_failed?
    failed? && metadata.is_a?(Hash) && metadata["code"] == VERIFICATION_FAILED_CODE
  end

  # F-3(마감 리뷰 2026-11-25) — pending 회복 대기 판정: 승인이 됐거나 될 수 있는데 재조회가
  # 실패해 웹훅 회복을 기다리는 주문(PurchaseService#keep_pending_for_webhook_recovery!가
  # metadata.pending_recovery를 남긴다). 상세 착지 안내가 "다시 시도"로 덮어쓰지 않게
  # 컨트롤러가 이 판정으로 분기한다. 검증 실패(verification_failed?) 판정이 더 우선이다.
  def pending_recovery_waiting?
    pending? && metadata.is_a?(Hash) && metadata["pending_recovery"].present?
  end

  # 결제 확정 검증 실패 기록(R2-5 — PurchaseService·웹훅 컨트롤러의 중복 구현을 한 곳으로).
  # with_lock 안에서 reload 뒤 pending일 때만 failed로 바꾼다(이미 확정·실패된 주문은 그대로
  # 둔다 — 경합 멱등). 결제 ID 스냅샷(pg_payment_id)과 사유(metadata.verification)를 남겨
  # CS·관리자 조사 대상으로 식별한다(B-1 선례 — 기존 metadata 키는 보존하고 병합). 적용
  # 여부를 돌려준다. 내부 값(금액·채널)은 로그 전용 — 회원 안내 문구에는 노출하지 않는다.
  def mark_verification_failed!(reason:, detail:)
    applied = false
    with_lock do
      reload
      next unless pending?

      update!(status: :failed, pg_payment_id: pg_order_id,
              metadata: (metadata || {}).stringify_keys.merge(
                code: VERIFICATION_FAILED_CODE,
                message: VERIFICATION_FAILED_MESSAGE,
                verification: { reason: reason, detail: detail }
              ))
      applied = true
    end
    if applied
      Rails.logger.error("[PaymentVerifier] order=#{pg_order_id} 결제 확정 검증 실패(#{reason}): #{detail}")
    end
    applied
  end

  # 상품별 정가 — 주문 생성은 항상 이 금액으로 한다(클라이언트 값 신뢰 금지).
  def self.amount_for(product)
    PRODUCT_AMOUNTS.fetch(product.to_sym)
  end

  # TAX-1 — metadata.invoice_id 역참조로 세금계산서 주문을 조회한다(Phase 6 C-2 — 이중 결제
  # 가드·청구 상세 패널의 "결제 완료·발행 기록 미생성" 분기가 공용). paid: true면 결제 완료 건만.
  # invoice.user_id로 한정해 소유권을 격리한다(청구 소유자 이외의 주문은 대상 아님).
  def self.tax_invoice_order_for(invoice, paid: false)
    scope = tax_invoices.where(user_id: invoice.user_id)
                        .where("JSON_EXTRACT(metadata, '$.invoice_id') = ?", invoice.id)
    scope = scope.paid if paid
    scope.order(:id).first
  end

  # F-1(마감 리뷰 2026-11-25) — 검증 실패 주문 재주문 차단용 조회. 상세 화면 밖의 재주문
  # 진입(내용증명 목록·청구서 상세 발행·요금제 수금 패스의 create)을 막는 3곳의 컨트롤러
  # 가드가 공용으로 쓴다. 회원의 주문을 품목(item_type)·청구(invoice_id)로 좁힌 뒤 루비에서
  # verification_failed?로 재판정한다(회원별 failed 주문은 소수 — JSON 질의 불요·간단 구현).
  # 해제 조건(운영): verification_failed?는 failed 상태를 요구하므로 운영자가 콘솔(runner)로
  # 그 주문의 상태를 다른 값(예: cancelled — 포트원 콘솔 환불 확정 후)으로 바꾸면 차단이
  # 풀린다. 관리자 화면은 범위 밖이다.
  def self.verification_failed_for(user, item_type: nil, invoice_id: nil)
    scope = where(user: user)
    scope = scope.where(item_type: item_type) if item_type
    if invoice_id
      scope = scope.where("JSON_EXTRACT(metadata, '$.invoice_id') = ?", invoice_id)
    end
    scope.order(:id).detect(&:verification_failed?)
  end
end

# 알림톡 발송 이력(F-REM — REM-6·P4·SEC-5·PLAN-3) — 모든 발신 시도(성공·실패·스킵)의 영구 기록.
# 사용자 임의 삭제 경로가 없다(P4). recipient_role로 채무자(debtor)/프리랜서(user) 수신을 구분하고,
# template_key는 credentials solapi.template_ids의 키(ALIMTALK_TEMPLATES.md)와 동일 문자열이다.
# 채무자 향은 [invoice_id, template_key] 부분 유니크 인덱스(recipient_role=debtor AND
# status=pending)로 "동시 진행 슬롯 1개"(경합 선점)가 DB에서 보장된다(SEC-5). 동일 단계
# 1회 판정 자체는 SendService의 origin 무관 sent 조회가 담당한다(리뷰 C-1 — 수동 재발송이
# 보낸 단계를 자동 스캔이 다시 보내지 않는다). 사용자 향 알림과 수동 재발송(sent·failed·
# skipped는 인덱스 밖)은 인덱스 제약 없이 단계별 반복·재발송·이력 누적이 허용된다.
class MessageLog < ApplicationRecord
  # PLAN-3 상한 산정 대역 — 시퀀스성 템플릿(기본·약속 트랙). 1회성 3종(issue_notice·partial_paid·
  # paid_thanks)과 U1 알림(noti_*)은 상한 집계 밖이다(02_prd_update 확정 해석 1·결정 기록 Q10).
  SEQUENCE_TEMPLATE_KEYS = %w[
    invoice_notice confirm_d1 confirm_d1_opened requeue_d7 final_d14
    promise_d1 promise_overdue
  ].freeze
  # PLAN-3 — 청구 건당 시퀀스 상한 5통(대체문자 포함·수동 발송 포함 하드리밋 — REM-12와 정합)
  SEQUENCE_CAP = 5

  # invoice는 optional로 완화(F-ADMIN Run C — 티켓 답변 알림 noti_ticket_reply는 invoice가
  # 없다). invoice_id가 채워지는 기존 발송 경로(Reminders::SendService)는 변경 없음 —
  # nil 허용만 추가됐다. invoice·ticket 동시 지정은 오기록이므로 검증으로 막는다(아래).
  belongs_to :invoice, optional: true
  belongs_to :ticket, optional: true # ADMIN-8 티켓 답변 알림의 대상
  belongs_to :user  # 소유 U1 — REM-6 이력의 소유자. invoice.user와 일치를 검증한다.

  enum :recipient_role, { debtor: 0, user: 1 }, default: :debtor
  enum :origin, { auto: 0, manual: 1 }, default: :auto
  enum :status, { pending: 0, sent: 1, failed: 2, skipped: 3 }, default: :pending

  validates :template_key, presence: true
  validate :user_must_own_invoice
  validate :single_subject

  # variables — 발송 시 조립한 #{변수명} 치환값 기록(REM-6 문구 버전 추적의 보조 증거)
  serialize :variables, coder: JSON

  # PLAN-3 상한 카운트 — 채무자 향 시퀀스성 sent(auto+manual 합산). origin 조건 없음이 의도다.
  scope :sent_sequence, ->(invoice_id) {
    where(invoice_id: invoice_id, recipient_role: :debtor,
          template_key: SEQUENCE_TEMPLATE_KEYS, status: :sent)
  }

  def self.sequence_sent_count(invoice_id)
    sent_sequence(invoice_id).count
  end

  private

  # Run C — 티켓 알림(invoice nil·ticket 있음)과 청구 발송(invoice 있음)은 배타적이다.
  # 양쪽 모두 비거나 양쪽 다 채워진 기록은 우회 경로의 오기록으로 차단한다(P4 기록의 정합성).
  def single_subject
    if invoice_id.present? == ticket_id.present?
      errors.add(:ticket_id, "청구서와 티켓 중 정확히 하나만 지정해야 합니다")
    end
  end

  # 데이터 무결성 — 이력의 소유자는 청구서 소유자(U1)와 일치해야 한다. 발송 계층(SendService)이
  # invoice.user_id로만 생성하지만, 콘솔·러너 등 우회 경로의 오기록을 차단한다.
  def user_must_own_invoice
    return if invoice.nil? || user_id == invoice.user_id

    errors.add(:user_id, "발송 이력의 소유자는 청구서 소유자와 일치해야 합니다")
  end
end

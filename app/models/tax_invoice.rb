# 전자세금계산서 발행 기록(TAX-1/2 — 2026-11-16) — paid 청구 건당 1발행(invoice_id unique).
# status 전이: pending(발행 요청 후 바로빌 처리 확인 중) → issued(국세청 승인번호 수신) /
# canceled(발급 취소) / failed(전송 실패). 취소·실패도 레코드를 유지한다(P4 — 발행 요청·
# 결과 전부 기록). 재발행은 이번 런 스코프 밖(PRD 후속 — canceled 후 발행 버튼 비활성).
class TaxInvoice < ApplicationRecord
  ISSUE_FEE = 300 # Q21 — 건당 300원(원가 100원 + 취소율 감안 마진). 주문 생성은 이 상수만 사용.

  # TAX-4 — 기능 꺼짐 안내 문구의 단일 출처(리뷰 W-2 — 컨트롤러 게이트·패널·pending 주문
  # 차단이 같은 문구를 쓴다). 뒤에 붙는 보조 문장("준비가 되면…")은 화면 맥락에 맞게 뷰가 덧붙인다.
  FEATURE_DISABLED_NOTICE = "전자세금계산서 발행은 현재 준비 중입니다."

  # TAX-4 — 운영 준비 게이트 단일 판정점(Q26 — 기본 꺼짐·fail-closed). ENV는 초기자
  # (config/initializers/tax_invoice.rb)가 부팅 시 한 번 읽어 config.x에 고정하므로 여기서는
  # config 값만 읽는다(ENV 직접 읽기 금지 — 테스트는 이 값을 바꿔 토글한다).
  def self.feature_enabled?
    Rails.application.config.x.tax_invoice_enabled
  end

  belongs_to :invoice
  belongs_to :user
  belongs_to :order, optional: true # Q21 — 발행 수수료 결제 주문(결제 완료 후 발행)

  # TAX-2 — 국세청 승인번호(NTSSendKey)·전송 상태·발행일(write_date)을 청구 이력에서 조회한다.
  enum :status, { pending: 0, issued: 1, canceled: 2, failed: 3 }, default: :pending

  validates :mgt_num, presence: true, uniqueness: true, length: { maximum: 24 }
  validates :supply_total, :tax_total, :grand_total,
            presence: true, numericality: { only_integer: true }

  # 1건 1발행 불변식의 응용 계층 단일 판정점 — 컨트롤러 가드·IssueService가 공유한다.
  # canceled 레코드도 발행 이력이므로 재발행을 막는다(런 스코프 확정 사항).
  scope :for_invoice, ->(invoice) { where(invoice_id: invoice.id) }

  def issuance_requested?
    persisted? && !canceled?
  end

  # TAX-2 — 청구서 상세 노출용 발행 상태 문구(뷰 표현 로직 3줄+ → 모델·헬퍼 경유 대신
  # 여기서 단일 출처로 둔다 — VIEW-8 화이트리스트 렌더는 뷰에서 수행).
  def status_label
    {
      "pending" => "발행 처리 중", "issued" => "발행 완료",
      "canceled" => "발행 취소", "failed" => "발행 실패"
    }.fetch(status)
  end
end

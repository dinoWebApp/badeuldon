# 탈퇴·계정 삭제 회원의 결제 기록 비식별 사본(AUTH-1.5·ADMIN-3 — 결정 기록 Q33, 2026-11-26).
# 회원 행이 삭제되기 직전 User#archive_payment_records 콜백(prepend)이 채운다. 원본 주문은
# 기존대로 연쇄 삭제되고(개인정보 즉시 파기), 이 행만 전자상거래법·개인정보처리방침 §3의
# 계약·결제 기록 5년 보존을 위해 남는다. 관리 화면은 없다(콘솔·runner 조회 전용).
class WithdrawnPaymentRecord < ApplicationRecord
  # 보존 기간 — 탈퇴 시각부터 5년(가장 보수적인 법정 기준). PurgeJob의 단일 출처.
  RETENTION = 5.years

  # Order와 같은 enum 정의(Order를 복사한 리터럴 — Order의 enum 값 변경 시 양쪽 동기화 필수).
  # 값 자체는 Order 모델이 단일 출처다. 접두어 충돌이 없어 그대로 선언한다.
  enum :product, { plus_monthly: 0, collection_pass: 1 } # rubocop:disable Layout/HashAlignment
  enum :status, { pending: 0, paid: 1, failed: 2, cancelled: 3 }, default: :pending
  enum :item_type, { pass: 0, legal_doc: 1, tax_invoice: 2 }, default: :pass

  # 5년 경과 행 — WithdrawnPaymentRecords::PurgeJob이 매일 삭제한다.
  scope :expired, -> { where(withdrawn_at: ...RETENTION.ago) }

  # 보관 멱등 키.
  validates :pg_order_id, presence: true, uniqueness: true

  # 회원의 주문 전체(paid·pending·failed·cancelled 포함 — 결제 시도 사실 자체가 기록)를
  # 위 컬럼으로 복사한다. 복사하지 않는 컬럼: user_id·pg_billing_key·metadata·refund_reason
  # (식별자·자유 텍스트 — Q33 화이트리스트). enum 컬럼은 `read_attribute`로 라벨 문자열을
  # 읽어 복사하며, insert_all이 보관 모델의 enum 매핑으로 Order와 같은 정수로 직렬화한다 —
  # 매핑 드리프트는 모델 테스트 ①(원본↔사본 값 대조)이 잡는다. `attribute_before_type_cast`
  # 로 바꾸지 않는다(enum 재매핑 시 과거 행의 의미가 깨진다).
  # 멱등: 이미 보관된 pg_order_id는 제외하고
  # insert_all한다(유니크 인덱스 이중 방어 — 같은 회원 삭제가 재시도돼도 2중 보관 없음).
  # 주문 0건인 회원은 보관 행 0건. 돌려주는 값은 새로 보관한 행 수.
  def self.archive!(user)
    already_archived = where(pg_order_id: user.orders.select(:pg_order_id)).pluck(:pg_order_id)
    rows = user.orders.where.not(pg_order_id: already_archived).map do |order|
      {
        product: order.read_attribute(:product),
        item_type: order.read_attribute(:item_type),
        amount: order.amount,
        status: order.read_attribute(:status),
        pg_order_id: order.pg_order_id,
        pg_payment_id: order.pg_payment_id,
        order_created_at: order.created_at,
        paid_at: order.paid_at,
        refunded_at: order.refunded_at,
        withdrawn_at: Time.current
      }
    end
    return 0 if rows.empty?

    insert_all(rows, record_timestamps: true).length
  end
end

require "test_helper"

# AUTH-1.5·ADMIN-3(결정 기록 Q33) — 회원 삭제 시 결제 기록 비식별 보관. 시나리오:
# ① 주문 상태 섞은 회원 destroy! → 주문 수만큼 보관 행 + 컬럼 값 원본 일치 ② 보관 행의
# 컬럼 화이트리스트(user_id·pg_billing_key·metadata·refund_reason 없음)·개인정보 문자열
# 미포함 ③ 원본 Order 연쇄 삭제 유지 ④ 주문 0건 회원은 보관 0건 ⑤ 멱등(pg_order_id 유니크)
# ⑥ expired 스코프 5년 경계 ⑦ 콜백 순서 — prepend 누락 시 ①이 깨진다(before_destroy가
# dependent: :destroy보다 늦게 돌면 주문이 이미 지워져 보관 행이 0건이 된다) ⑧ 트랜잭션
# 롤백 시 보관 행도 원복(탈퇴 서비스의 user.transaction 안 보장).
class WithdrawnPaymentRecordTest < ActiveSupport::TestCase
  setup do
    # 전역 카운트 단언이 다른 테스트가 커밋한 잔여 행에 흔들리지 않도록 빈 테이블에서 시작한다
    # (이 클래스는 트랜잭션 롤백이라 setup의 delete_all도 원복된다 — 오염원은
    # CommittedCleanupTestHelper 주석 참고).
    WithdrawnPaymentRecord.delete_all
    @user = User.create!(email: "withdraw-archive@example.com", password: "password",
                         display_name: "보관테스트스튜디오", business_type: :freelancer)
  end

  def create_order!(attrs)
    Order.create!({ user: @user, product: :collection_pass, amount: 4_000,
                    status: :paid, pg_order_id: "order-archive-#{SecureRandom.hex(8)}",
                    paid_at: Time.current }.merge(attrs))
  end

  test "주문 상태 섞은 회원을 destroy! 하면 주문 수만큼 식별 불가능 사본이 남는다 (Q33 — 콜백 순서 prepend 검증)" do
    paid = create_order!(status: :paid, pg_payment_id: "pay-arch-0001")
    pending = create_order!(status: :pending, product: :plus_monthly, amount: 9_900)
    failed = create_order!(status: :failed)
    cancelled = create_order!(status: :cancelled, item_type: :legal_doc, amount: 5_000,
                              refunded_at: Time.current)

    @user.destroy!

    assert_equal 4, WithdrawnPaymentRecord.count
    [ paid, pending, failed, cancelled ].each do |order|
      record = WithdrawnPaymentRecord.find_by!(pg_order_id: order.pg_order_id)
      assert_equal order.read_attribute(:product), record.read_attribute(:product)
      assert_equal order.read_attribute(:item_type), record.read_attribute(:item_type)
      assert_equal order.amount, record.amount
      assert_equal order.read_attribute(:status), record.read_attribute(:status)
      # pg_payment_id는 nullable — assert_equal(nil, ·)은 이 minitest에서 assert_nil 힌트
      # 예외를 던지므로 nil 여부를 분기해 비교한다.
      if order.pg_payment_id.nil?
        assert_nil record.pg_payment_id
      else
        assert_equal order.pg_payment_id, record.pg_payment_id
      end
      # SQLite datetime 왕복은 초 미만을 버린다 — 1초 이내 일치로 판정한다.
      assert_in_delta order.created_at, record.order_created_at, 1.second
      assert_in_delta order.paid_at || order.created_at, record.paid_at || order.created_at, 1.second
      assert_equal order.refunded_at.present?, record.refunded_at.present?
      if order.refunded_at
        assert_in_delta order.refunded_at, record.refunded_at, 1.second
      end
      assert_not_nil record.withdrawn_at
    end
  end

  test "보관 행은 화이트리스트 컬럼만 가지고 개인정보 문자열이 어디에도 없다 (Q33 — 식별 불가능성)" do
    order = create_order!(status: :paid)

    @user.destroy!

    forbidden = %w[user_id pg_billing_key metadata refund_reason]
    assert_empty(WithdrawnPaymentRecord.column_names & forbidden,
                 "보관 테이블에 개인정보·빌링키·메타데이터 컬럼이 있으면 안 된다")
    record = WithdrawnPaymentRecord.find_by!(pg_order_id: order.pg_order_id)
    string_values = WithdrawnPaymentRecord.column_names
                                          .select { |c| WithdrawnPaymentRecord.type_for_attribute(c).type == :string }
                                          .flat_map { |c| WithdrawnPaymentRecord.pluck(c).compact }
    [ @user.email, @user.display_name ].each do |personal|
      assert_not string_values.any? { |v| v.include?(personal) },
                 "보관 행의 문자열 컬럼에 개인정보(#{personal})가 있으면 안 된다"
    end
  end

  test "원본 주문은 기존대로 연쇄 삭제된다 (개인정보 즉시 파기 유지 — AUTH-1.5)" do
    create_order!(status: :paid)
    create_order!(status: :pending)

    assert_equal 2, Order.where(user_id: @user.id).count
    @user.destroy!
    assert_equal 0, Order.where(user_id: @user.id).count
    assert_equal 2, WithdrawnPaymentRecord.count
  end

  test "주문 0건인 회원은 보관 행도 0건이다" do
    @user.destroy!
    assert_equal 0, WithdrawnPaymentRecord.count
  end

  test "멱등 — 같은 pg_order_id를 두 번 보관해도 1건이다 (pg_order_id 유니크)" do
    order = create_order!(status: :paid)

    assert_equal 1, WithdrawnPaymentRecord.archive!(@user)
    assert_equal 0, WithdrawnPaymentRecord.archive!(@user) # 재보관 시도 — 제외되어 0건
    assert_equal 1, WithdrawnPaymentRecord.count
    assert WithdrawnPaymentRecord.exists?(pg_order_id: order.pg_order_id)
  end

  test "expired 스코프 — 탈퇴 시각부터 5년 경계(4년 1일 전 행은 유지·5년+1초 만료)" do
    travel_to Time.zone.local(2026, 11, 26, 12, 0, 0) do
      kept = WithdrawnPaymentRecord.create!(product: :collection_pass, item_type: :pass,
                                            amount: 4_000, status: :paid,
                                            pg_order_id: "order-exp-keep", withdrawn_at: 4.years.ago - 1.day)
      expired = WithdrawnPaymentRecord.create!(product: :collection_pass, item_type: :pass,
                                               amount: 4_000, status: :paid,
                                               pg_order_id: "order-exp-gone", withdrawn_at: 5.years.ago - 1.second)

      assert WithdrawnPaymentRecord.exists?(kept.id)
      assert WithdrawnPaymentRecord.expired.exclude?(kept.id), "4년 364일 행은 만료가 아니다"
      assert_includes WithdrawnPaymentRecord.expired, expired, "5년+1초 행은 만료다"
    end
  end

  test "트랜잭션 롤백 시 보관 행도 원복된다 (탈퇴 서비스 user.transaction 정합)" do
    create_order!(status: :paid)

    User.transaction do
      @user.destroy!
      assert_equal 1, WithdrawnPaymentRecord.count
      raise ActiveRecord::Rollback
    end

    assert User.exists?(@user.id), "회원이 살아 있어야 한다"
    assert_equal 0, WithdrawnPaymentRecord.count, "보관 행도 롤백돼야 한다"
    assert_equal 1, Order.where(user_id: @user.id).count
  end
end

require "test_helper"

# ADMIN-3 ④ 계정 삭제·데이터 파기(Q13) — 시나리오:
# ① 이메일 2중 확인 불일치 거부 ② 미수 청구(issued) 차단 — 완납·무효·초안만 허용
# ③ 정상 삭제 — dependent 연쇄 전수 0건 + audit_logs 보존(admin 소유) ④ 실패 시 아무것도 삭제 안 됨.
class Admins::AccountPurgeServiceTest < ActiveSupport::TestCase
  setup do
    @admin = admins(:ops)
    @user = users(:alpha) # fixture는 after_create 우회 — Free 구독 행 수동 보장(1인 1구독)
    @subscription = @user.subscription || Subscription.create!(user: @user, plan: :free)
    # alpha fixture는 거래처 5개(PLAN-1 Free 한도) — 신규 생성을 위해 1개를 정리한다.
    @user.clients.first&.destroy!
    @client = Client.create!(user: @user, name: "삭제전용거래처", contact_name: "담당자", phone: "010-0000-0000")
  end

  test "이메일 2중 확인 불일치면 거부되고 아무것도 삭제되지 않는다 (Q13)" do
    result = Admins::AccountPurgeService.call(admin: @admin, user: @user, confirm_email: "wrong@example.com")

    assert_not result.success?
    assert_predicate @user.reload, :present?
    assert_equal 0, AuditLog.where(action: "account_purge").count
  end

  test "미수 청구서(issued)가 있으면 차단되고 계정이 유지된다 (Q13)" do
    create_invoice! { |inv| inv.issue! }

    result = Admins::AccountPurgeService.call(admin: @admin, user: @user, confirm_email: @user.email)

    assert_not result.success?
    assert_match(/미수/, result.errors.first)
    assert_predicate @user.reload, :present?
    assert_equal 0, AuditLog.where(action: "account_purge").count
  end

  test "초안 전용 계정은 삭제되고 연쇄 대상이 전부 0건이며 감사 로그는 보존된다 (Q13·AUTH-1.5)" do
    create_invoice!
    NoticeRead.create!(user: @user, notice: notices(:general_active))
    Ticket.create!(user: @user, title: "삭제 테스트", status: :closed)
    Session.create!(user: @user)

    result = Admins::AccountPurgeService.call(admin: @admin, user: @user, confirm_email: @user.email)

    assert result.success?
    assert_not User.exists?(@user.id)
    # 연쇄 삭제 전수 실측 — dependent: :destroy + DB FK cascade
    assert_equal 0, Client.where(user_id: @user.id).count
    assert_equal 0, Invoice.where(user_id: @user.id).count
    assert_equal 0, Item.where(user_id: @user.id).count
    assert_equal 0, Subscription.where(user_id: @user.id).count
    assert_equal 0, Order.where(user_id: @user.id).count
    assert_equal 0, PaymentPass.where(user_id: @user.id).count
    assert_equal 0, NoticeRead.where(user_id: @user.id).count
    assert_equal 0, Ticket.where(user_id: @user.id).count
    assert_equal 0, Session.where(user_id: @user.id).count
    assert_equal 0, MessageLog.where(user_id: @user.id).count
    # 감사 로그 보존(Q13) — admin 소유, user 삭제로 소멸하지 않음
    purge_log = AuditLog.find_by(action: "account_purge", target_type: "User", target_id: @user.id)
    assert_predicate purge_log, :present?
    assert_match(@user.email, purge_log.detail)
    assert_equal @admin.id, purge_log.admin_id
  end

  test "완납·무효 청구서만 있는 계정은 삭제 가능하다 (Q13 — 완납·무효·초안만 허용)" do
    paid = create_invoice! { |inv| inv.issue! }
    paid.mark_paid!
    voided = create_invoice! { |inv| inv.issue! }
    voided.void!

    result = Admins::AccountPurgeService.call(admin: @admin, user: @user, confirm_email: @user.email)

    assert result.success?
    assert_not User.exists?(@user.id)
    assert_equal 0, Invoice.where(user_id: @user.id).count
  end

  private

  # 품목 1행 초안 생성(검증 통과) — 상태 전이는 블록에서 수행(issue! 등).
  def create_invoice!(due_on: 30.days.from_now.to_date, &)
    invoice = Invoice.new(user: @user, client: @client, status: :draft, due_on:,
                          tax_mode: :separate, withholding_enabled: false,
                          issuer_display_name: "테스트발행자", bank_name: "신한은행",
                          account_number: "110-234-567890", account_holder: "김알파",
                          items_attributes: [ { description: "디자인 작업", quantity: 1, unit_price: 300_000 } ])
    invoice.save!
    yield(invoice) if block_given?
    invoice.reload
  end
end

require "test_helper"

# 반복 청구 스케줄 상태 전이(W-1) — 불가 전이의 서버 가드. pause는 active만·resume는
# paused만 허용하며 cancelled 재활성은 UI confirm("해지한 스케줄은 다시 활성화할 수 없습니다")
# 및 컨트롤러 주석 불변식과 동일하게 HTTP 경계에서도 거부된다.
class App::RecurringTransitionsTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients

  setup do
    @user = users(:gamma)
    sign_in_as @user
    @client = @user.clients.first || @user.clients.create!(name: "전이테스트", contact_name: "홍담당", phone: "010-2222-3333")
    @schedule = RecurringInvoice.new(user: @user, client: @client, day_of_month: 10)
    @schedule.items.build(name: "월정액", quantity: 1, unit_price: 100_000)
    @schedule.save!
  end

  test "cancelled 스케줄의 resume은 거부되고 상태가 유지된다 (W-1)" do
    @schedule.update!(status: :cancelled)

    patch resume_app_recurring_invoice_path(@schedule)

    assert_response :see_other
    assert_predicate flash[:alert], :present?
    assert_equal "cancelled", @schedule.reload.status
  end

  test "paused가 아닌 스케줄의 resume은 거부된다 (W-1 — active 중복 재개)" do
    patch resume_app_recurring_invoice_path(@schedule)

    assert_response :see_other
    assert_predicate flash[:alert], :present?
    assert_equal "active", @schedule.reload.status
  end

  test "active가 아닌 스케줄의 pause는 거부된다 (W-1)" do
    @schedule.update!(status: :paused)

    patch pause_app_recurring_invoice_path(@schedule)

    assert_response :see_other
    assert_predicate flash[:alert], :present?
    assert_equal "paused", @schedule.reload.status
  end

  test "정상 전이는 통과한다 — active→paused→active" do
    patch pause_app_recurring_invoice_path(@schedule)
    assert_response :see_other
    assert_equal "paused", @schedule.reload.status
    assert_predicate flash[:notice], :present?

    patch resume_app_recurring_invoice_path(@schedule)
    assert_response :see_other
    assert_equal "active", @schedule.reload.status
    assert_predicate flash[:notice], :present?
  end
end

require "test_helper"

# 반복 청구 스케줄 CRUD HTTP 경계(INV-7) — 등록 성공(303·next 초기화)·발행일 29일 거부(422)·
# 소유권 격리(타인 스케줄 404)·해지(303·이력 보존 P4)·상세 hold 사유 배너(NOTI-3 — 등록 전
# 알림톡 대체 UI). 전이 가드는 recurring_transitions_test(W-1)가 담당하므로 여기선 제외한다.
class App::RecurringInvoicesControllerTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients

  setup do
    @user = users(:gamma)
    sign_in_as @user
    @client = @user.clients.first || @user.clients.create!(name: "CRUD테스트", contact_name: "김담당", phone: "010-3333-4444")
  end

  def valid_params(client_id: @client.id, day: 10)
    {
      recurring_invoice: {
        client_id: client_id, day_of_month: day, tax_mode: "separate",
        withholding_enabled: "1", hold_if_unpaid: "1",
        items_attributes: { "0" => { name: "월정액", quantity: "1", unit_price: "100000" } }
      }
    }
  end

  test "index·new는 200을 반환한다" do
    get app_recurring_invoices_path
    assert_response :ok

    get new_app_recurring_invoice_path
    assert_response :ok
  end

  test "create 성공 — 303·스케줄 생성·next_issue_on 초기화" do
    assert_difference "RecurringInvoice.count", 1 do
      post app_recurring_invoices_path, params: valid_params
    end

    assert_response :see_other
    schedule = RecurringInvoice.order(:id).last
    assert_equal "active", schedule.status
    assert_equal 1, schedule.items.count # 품목 스냅샷 소스 저장
    assert_not_nil schedule.next_issue_on # initialize_next_issue_on!
    assert_equal @user.id, schedule.user_id
  end

  test "create 경계 — day 29는 거부되고 422로 재렌더된다(INV-7 발행일 1~28)" do
    assert_no_difference "RecurringInvoice.count" do
      post app_recurring_invoices_path, params: valid_params(day: 29)
    end

    assert_response :unprocessable_entity
  end

  test "타인 소유 스케줄 조회는 404로 격리된다" do
    other_user = users(:delta)
    other_client = other_user.clients.first || other_user.clients.create!(name: "타인거래처", contact_name: "이담당", phone: "010-5555-6666")
    schedule = RecurringInvoice.create!(
      user: other_user, client: other_client, day_of_month: 5,
      items_attributes: [ { name: "외주", quantity: 1, unit_price: 50_000 } ]
    )

    get app_recurring_invoice_path(schedule)

    assert_response :not_found # show_exceptions = :rescuable — 미들웨어가 404 렌더
  end

  test "cancel — 303·cancelled 전이·발행 이력은 보존된다(P4)" do
    schedule = RecurringInvoice.create!(
      user: @user, client: @client, day_of_month: 10,
      items_attributes: [ { name: "월정액", quantity: 1, unit_price: 100_000 } ]
    )
    schedule.update!(last_issued_on: Date.new(2026, 10, 10))

    patch cancel_app_recurring_invoice_path(schedule)

    assert_response :see_other
    assert_equal "cancelled", schedule.reload.status
    assert_equal Date.new(2026, 10, 10), schedule.reload.last_issued_on # 이력 보존 — 해지는 전이만
  end

  test "상세 화면은 hold 사유 배너를 렌더한다(NOTI-3 — 사유 기록 시)" do
    schedule = RecurringInvoice.create!(
      user: @user, client: @client, day_of_month: 10,
      items_attributes: [ { name: "월정액", quantity: 1, unit_price: 100_000 } ]
    )
    schedule.hold!("직전 청구가 미수 상태여서 이번 달 발행을 보류했습니다.")

    get app_recurring_invoice_path(schedule)

    assert_response :ok
    assert_match "이번 달 발행이 보류되었습니다", response.body
    assert_match "직전 청구가 미수 상태", response.body
  end

  test "상세 화면은 사유가 없으면 배너를 렌더하지 않는다" do
    schedule = RecurringInvoice.create!(
      user: @user, client: @client, day_of_month: 10,
      items_attributes: [ { name: "월정액", quantity: 1, unit_price: 100_000 } ]
    )

    get app_recurring_invoice_path(schedule)

    assert_response :ok
    assert_no_match "이번 달 발행이 보류되었습니다", response.body
  end
end

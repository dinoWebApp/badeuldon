require "test_helper"

# AUTH-1.5 회원 탈퇴 뒤 청구 링크(/b/:token) 회귀 — 05_review §T1 Tester 중점 제안.
# 탈퇴로 청구서 행이 연쇄 삭제되면 링크는 "존재하지 않는 토큰"으로 수렴해 만료·폐기·미존재
# 공용 안내(VIEW-6)와 404로 응답해야 하고 500이 되어서는 안 된다. 초안(링크 발급 전)·무효
# (voided — void!가 토큰을 즉시 폐기한다, INV-6)도 링크가 성립하지 않는 같은 상태다.
# 열람 기록(ViewEvent)은 없는 토큰에 남지 않는다(삭제 대상과 짝 — P4 무결성).
# 외부 API 호출 없음.
class ViewerWithdrawalRegressionTest < ActionDispatch::IntegrationTest
  DESKTOP_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
               "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  setup do
    @user = users(:gamma) # gamma는 청구서 fixture가 없다 — 탈퇴 전용 데이터를 만든다
    @client = Client.create!(user: @user, name: "탈퇴뷰어거래처", contact_name: "담당자",
                             phone: "010-7777-0000")
    @invoice = create_issued_invoice
  end

  test "탈퇴 뒤 발행 청구 링크는 만료·폐기 공용 안내와 404로 응답하고 열람 기록을 남기지 않는다 (AUTH-1.5·VIEW-6)" do
    token = @invoice.reload.token
    assert_predicate token, :present?
    assert_equal 200, get_status_of(token) # 탈퇴 전에는 정상 열람

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")
    assert result.success?, result.message

    assert_no_difference -> { ViewEvent.count } do
      get viewer_path(token), headers: { "User-Agent" => DESKTOP_UA }
    end
    assert_response :not_found
    assert_includes response.body, "링크가 만료되었거나 폐기되었습니다"
    assert_equal 0, Invoice.where(user_id: @user.id).count
  end

  test "초안(링크 발급 전)·무효 청구는 링크가 성립하지 않고 탈퇴 뒤에도 404·동일 본문으로 수렴한다 (VIEW-6)" do
    issued_token = @invoice.reload.token # 탈퇴 뒤엔 reload가 불가하다(연쇄 삭제) — 미리 캡처

    # 초안 — 토큰이 아직 없어 링크 자체가 성립하지 않는다(발행 전 자국)
    draft = Invoice.new(user: @user, client: @client, status: :draft, due_on: 30.days.from_now.to_date,
                        tax_mode: :separate, withholding_enabled: false,
                        issuer_display_name: "뷰어발행자", bank_name: "신한은행",
                        account_number: "110-234-567890", account_holder: "김감마",
                        items_attributes: [ { description: "유지보수", quantity: 1, unit_price: 100_000 } ])
    draft.save!
    assert_nil draft.reload.token, "초안은 토큰이 없어 탈퇴와 무관하게 링크가 없다"

    # 무효 — 발행 뒤 폐기하면 토큰이 즉시 폐기된다(INV-6) — 초안과 같은 "링크 없음" 상태
    voided = create_issued_invoice
    voided.void!
    assert_predicate voided.reload, :voided?
    assert_nil voided.token, "무효 처리 시 토큰이 즉시 폐기된다(INV-6)"

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")
    assert result.success?, result.message

    # 탈퇴 뒤 — 삭제된 청구의 옛 토큰과 미존재 토큰이 같은 404·동일 본문으로 수렴한다
    withdrawn_body = get_body_of(issued_token)
    assert_equal 404, response.status
    missing_body = get_body_of("does-not-exist-000000")
    assert_equal 404, response.status
    assert_equal withdrawn_body, missing_body, "VIEW-6 — 만료·폐기·미존재는 본문까지 동일하다"
    assert_includes withdrawn_body, "링크가 만료되었거나 폐기되었습니다"
  end

  private

  def create_issued_invoice
    invoice = Invoice.new(user: @user, client: @client, status: :draft, due_on: 30.days.from_now.to_date,
                          tax_mode: :separate, withholding_enabled: false,
                          issuer_display_name: "뷰어발행자", bank_name: "신한은행",
                          account_number: "110-234-567890", account_holder: "김감마",
                          items_attributes: [ { description: "유지보수", quantity: 1, unit_price: 100_000 } ])
    invoice.save!
    invoice.issue!
    invoice.reload
  end

  def get_status_of(token)
    get viewer_path(token), headers: { "User-Agent" => DESKTOP_UA }
    response.status
  end

  def get_body_of(token)
    get viewer_path(token), headers: { "User-Agent" => DESKTOP_UA }
    response.body
  end
end

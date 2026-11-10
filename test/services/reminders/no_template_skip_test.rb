require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"

# Q15·NOTI-3(W-2 방침 (b)) — credentials에 등록 전인 템플릿 키(noti_recurring_issued 등)의
# MISSING_TEMPLATE은 failed·재시도가 아니라 skipped(NO_TEMPLATE) MessageLog 기록 후 정상
# 종료다(발신 측 무영향·P4 이력 보존·등록 후 자동 활성화).
class Reminders::NoTemplateSkipTest < ActiveSupport::TestCase
  fixtures :users, :clients, :invoices

  def setup
    @fake = FakeSolapiClient.new(raise_on: { "noti_recurring_issued" => Solapi::ApiError.new(
      status: nil, code: "MISSING_TEMPLATE", message: "솔라피 템플릿 코드가 credentials에 없습니다"
    ) })
    @invoice = invoices(:delta_issued) # 미수 발행 계열 fixture
  end

  test "등록 전 템플릿은 skipped(NO_TEMPLATE)로 기록되고 예외가 상승하지 않는다" do
    result = Reminders::SendService.new(invoice: @invoice, template_key: "noti_recurring_issued",
                             recipient_role: :user, client: @fake).call

    assert_equal :skipped, result
    log = MessageLog.find_by(invoice_id: @invoice.id, template_key: "noti_recurring_issued",
                             recipient_role: "user")
    assert_predicate log, :present?
    assert log.skipped?
    assert_equal "NO_TEMPLATE", log.error_code
    # 실발송은 이뤄지지 않았다(FakeSolapiClient가 기록 1건 = raise 전 진입 시도)
    assert_equal 1, @fake.calls.count
    assert_nil log.sent_at
  end
end

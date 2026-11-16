require "test_helper"
require_relative "../../test_helpers/fake_baro_bill_client"

# 발급 취소(TAX-1 — CancelService·W-5 문구 분기) 서비스 테스트. 정상 취소(5031 기록)·
# 일시 전송 오류("SOAP") vs 확정 오류(바로빌 음수 코드) 문구 분리·재취소 차단을 검증한다.
# 바로빌 SOAP는 FakeBaroBillClient 주입으로 대체한다(실호출 금지).
class TaxInvoices::CancelServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)
    @tax_invoice = TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-CANCEL-1",
                                      status: :pending, supply_total: 100_000,
                                      tax_total: 10_000, grand_total: 110_000)
    @client = FakeBaroBillClient.new
  end

  test "정상 취소 — ProcTaxInvoice(ISSUE_CANCEL) 호출 후 canceled·barobill_state 5031 (P4 레코드 유지)" do
    result = TaxInvoices::CancelService.new(tax_invoice: @tax_invoice, client: @client).call

    assert_equal @tax_invoice.reload, result
    assert_predicate @tax_invoice, :canceled?
    assert_equal 5031, @tax_invoice.barobill_state
    assert_equal({ corp_num: @user.corp_num, mgt_num: "TI-CANCEL-1" },
                 @client.calls[:cancel_tax_invoice].sole)
    assert TaxInvoice.exists?(@tax_invoice.id)                 # 레코드는 유지된다
  end

  test "재취소는 차단된다 — '이미 취소된 발행입니다' (외부 호출 없음)" do
    @tax_invoice.update!(status: :canceled)

    error = assert_raises(TaxInvoices::CancelService::NotCancelable) do
      TaxInvoices::CancelService.new(tax_invoice: @tax_invoice, client: @client).call
    end

    assert_equal "이미 취소된 발행입니다.", error.message
    assert_empty @client.calls.values.flatten
  end

  # W-5 — 전송 계열("SOAP") 일시 오류는 재시도 안내 문구다(종결 단정 금지).
  test "W-5: SOAP 일시 오류는 재시도 안내 문구로 분기된다" do
    client = FakeBaroBillClient.new(raise_on: { cancel_tax_invoice:
      BaroBill::ClientService::ApiError.new(code: "SOAP", message: "네트워크 오류") })

    error = assert_raises(TaxInvoices::CancelService::NotCancelable) do
      TaxInvoices::CancelService.new(tax_invoice: @tax_invoice, client: client).call
    end

    assert_match(/잠시 후 다시 시도해 주세요/, error.message)
    assert_nothing_raised { @tax_invoice.reload }
    assert_predicate @tax_invoice, :pending?                   # 상태 미전이 — 재시도 가능
  end

  # W-5 — 바로빌 음수 코드(국세청 전송 완료 등 확정 오류)는 수정세금계산서 정정 안내.
  test "W-5: 바로빌 음수 오류는 수정세금계산서 정정 안내로 분기된다" do
    client = FakeBaroBillClient.new(raise_on: { cancel_tax_invoice:
      BaroBill::ClientService::ApiError.new(code: "-871802", message: "취소 불가") })

    error = assert_raises(TaxInvoices::CancelService::NotCancelable) do
      TaxInvoices::CancelService.new(tax_invoice: @tax_invoice, client: client).call
    end

    assert_match(/오류코드 -871802/, error.message)
    assert_match(/수정세금계산서로 정정/, error.message)
  end

  test "canceled 후 같은 청구의 재발행은 IssueService 가드로 차단된다 (1건 1발행)" do
    @tax_invoice.update!(status: :canceled)
    @user.update!(corp_num: "1234567890", corp_name: "델타디자인", ceo_name: "김델타",
                  corp_addr: "서울시 강남구", contact_name: "김델타",
                  barobill_id: "bd001", barobill_cert_registered: true)
    order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                 amount: TaxInvoice::ISSUE_FEE, pg_order_id: SecureRandom.uuid,
                                 status: :paid, metadata: { invoice_id: @invoice.id })

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: order, client: @client).call
    end

    assert_match(/이미 발행 요청된 청구서입니다/, error.message)
  end
end

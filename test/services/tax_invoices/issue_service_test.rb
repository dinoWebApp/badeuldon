require "test_helper"
require_relative "../../test_helpers/fake_baro_bill_client"

# 전자세금계산서 발행(TAX-1 — 03_implementation §IssueService) 서비스 테스트.
# 가드 사슬 5종·휴폐업 차단·정상 경로(레코드·mgt_num·폴링 인계)·C-3 품목 합계 정합을 검증한다.
# 바로빌 SOAP는 FakeBaroBillClient 주입으로 대체한다(실호출 금지).
class TaxInvoices::IssueServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:delta)
    make_ready!(@user)
    @invoice = invoices(:delta_paid)                       # paid 청구(subtotal 100_000·tax 10_000)
    @order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                  amount: TaxInvoice::ISSUE_FEE, pg_order_id: SecureRandom.uuid,
                                  status: :paid, metadata: { invoice_id: @invoice.id })
    @client = FakeBaroBillClient.new
  end

  test "정상 경로 — 발행 기록 생성·mgt_num 채번·폴링 잡 인계 (TAX-1·TAX-2)" do
    tax_invoice = nil
    before = enqueued_poll_jobs.size
    tax_invoice = TaxInvoices::IssueService.new(invoice: @invoice, order: @order,
                                                client: @client).call
    assert_equal before + 1, enqueued_poll_jobs.size
    assert_equal [ tax_invoice.id ], enqueued_poll_jobs.last

    assert_predicate tax_invoice, :pending?
    assert_equal "TI#{@user.id}I#{@invoice.id}", tax_invoice.mgt_num
    assert_equal @invoice.subtotal, tax_invoice.supply_total
    assert_equal @invoice.tax_amount, tax_invoice.tax_total
    assert_equal @invoice.total_amount, tax_invoice.grand_total
    assert_equal @invoice.settled_paid_on, tax_invoice.write_date
    assert_equal @order.id, tax_invoice.order_id
    assert_equal [ { corp_num: @user.corp_num, check_corp_num: "8888888888" } ],
                 @client.calls[:get_corp_state]
    assert_equal 1, @client.calls[:regist_and_issue_tax_invoice].count
  end

  test "가드: 발행 설정 미완료(공동인증서 미마킹)는 GuardFailed다" do
    @user.update!(barobill_cert_registered: false)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_match(/발행 설정을 먼저 완료/, error.message)
    assert_empty @client.calls.values.flatten
  end

  # TAX-3 ④(2026-11-24·Q25) — 결제 완료 뒤 경로의 최종 방어선. 자격 가드는 가드 사슬의
  # 맨 앞이므로 설정 미완료가 함께 있어도 자격 문구가 먼저 나오고, 기록·바로빌 호출은 없다.
  test "가드(TAX-3): 간이과세 사용자는 GuardFailed다 — 기록·바로빌 호출 없음" do
    @user.update!(tax_type: :simplified)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_equal @user.tax_invoice_ineligibility_notice, error.message
    assert_nil TaxInvoice.find_by(invoice_id: @invoice.id)      # 발행 레코드 미생성
    assert_empty @client.calls.values.flatten                    # SOAP 미호출
  end

  test "가드(TAX-3): 면세사업자 사용자도 GuardFailed다" do
    @user.update!(tax_type: :exempt)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_equal @user.tax_invoice_ineligibility_notice, error.message
    assert_nil TaxInvoice.find_by(invoice_id: @invoice.id)
    assert_empty @client.calls.values.flatten
  end

  test "가드(TAX-3): 자격 가드는 설정 미완료 가드보다 앞선다 — 부적격+미설정은 자격 문구다" do
    @user.update!(tax_type: :simplified, barobill_cert_registered: false)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_equal @user.tax_invoice_ineligibility_notice, error.message
    assert_no_match(/발행 설정을 먼저 완료/, error.message)
  end

  test "가드: 거래처 사업자번호 없음(개인 거래처)은 GuardFailed다" do
    clients(:delta_main).update!(business_number: nil)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_match(/개인 거래처는 비대상/, error.message)
  end

  test "가드: 주문 미결제(paid 아님)는 GuardFailed다" do
    @order.update!(status: :pending)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_match(/결제가 완료되지 않았습니다/, error.message)
  end

  test "가드: 수금 마감 전 청구(paid 아님)는 GuardFailed다" do
    invoice = invoices(:delta_issued)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: invoice, order: @order, client: @client).call
    end

    assert_match(/수금이 마감된 청구서만/, error.message)
  end

  test "가드: 이미 발행 요청된 청구는 GuardFailed다 — canceled 레코드도 재발행을 막는다" do
    TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-CANCELED-1",
                       status: :canceled, supply_total: 100_000, tax_total: 10_000,
                       grand_total: 110_000)

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: @client).call
    end

    assert_match(/이미 발행 요청된 청구서입니다/, error.message)
  end

  test "휴폐업: 거래처가 폐업(state 3)이면 발행을 차단한다" do
    client = FakeBaroBillClient.new(returns: { get_corp_state: { state: 3, corp_name: "폐업처" } })

    error = assert_raises(TaxInvoices::IssueService::GuardFailed) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: client).call
    end

    assert_match(/폐업 상태여서 발행할 수 없습니다/, error.message)
    assert_empty client.calls[:regist_and_issue_tax_invoice]   # 전송 미수행
    assert_nil TaxInvoice.find_by(invoice_id: @invoice.id)     # 레코드 미생성
  end

  # C-3 — 별건 모드: Σ품목.Amount == AmountTotal(=subtotal)·Σ품목.Tax == TaxTotal.
  # 다중 행에서 행별 10% 반올림 잔액이 마지막 행으로 수렴한다(정수 연산 — Float 배제).
  test "C-3: 별건 모드 다중 품목의 Σ품목 금액이 총액 상위 필드와 정확히 일치한다" do
    invoice = create_paid_invoice(tax_mode: :separate, rows: [ [ 1, 33_333 ], [ 2, 10_000 ], [ 1, 7_777 ] ])
    tax_invoice = TaxInvoices::IssueService.new(invoice: invoice, order: @order, client: @client).call

    rows = captured_line_items(invoice)
    assert_equal invoice.subtotal, rows.sum { |r| r[:Amount].to_i }
    assert_equal invoice.tax_amount, rows.sum { |r| r[:Tax].to_i }
    assert_equal invoice.subtotal, tax_invoice.reload.supply_total
  end

  # C-3 — 포함 모드: 행 총액을 11분해한 공급가액 합계가 invoice.subtotal과 정확히 일치한다
  # (행에 세포함 총액을 그대로 Amount로 보내던 교정 전 버그의 회귀 방지).
  test "C-3: 부가세 포함 모드의 Σ품목 금액이 총액 상위 필드와 정확히 일치한다" do
    invoice = create_paid_invoice(tax_mode: :included, rows: [ [ 1, 33_333 ], [ 2, 10_000 ] ])
    TaxInvoices::IssueService.new(invoice: invoice, order: @order, client: @client).call

    rows = captured_line_items(invoice)
    assert_equal invoice.subtotal, rows.sum { |r| r[:Amount].to_i }
    assert_equal invoice.tax_amount, rows.sum { |r| r[:Tax].to_i }
  end

  test "C-3: 단일 품목 경계 — 포함 모드에서도 잔액 조정으로 합계가 일치한다" do
    invoice = create_paid_invoice(tax_mode: :included, rows: [ [ 3, 12_345 ] ])
    TaxInvoices::IssueService.new(invoice: invoice, order: @order, client: @client).call

    rows = captured_line_items(invoice)
    assert_equal invoice.subtotal, rows.sum { |r| r[:Amount].to_i }
    assert_equal invoice.tax_amount, rows.sum { |r| r[:Tax].to_i }
  end

  test "SOAP 전송 실패(ApiError)는 예외로 올라가 주문 paid는 유지된다 (P4 — Fulfill 계층이 흡수)" do
    client = FakeBaroBillClient.new(raise_on: { regist_and_issue_tax_invoice:
      BaroBill::ClientService::ApiError.new(code: "-871202", message: "전송 실패") })

    assert_raises(BaroBill::ClientService::ApiError) do
      TaxInvoices::IssueService.new(invoice: @invoice, order: @order, client: client).call
    end

    assert_predicate @order.reload, :paid?                     # 결제 성립은 되돌리지 않는다
    assert_predicate TaxInvoice.find_by(invoice_id: @invoice.id), :pending?
  end

  private

  def make_ready!(user)
    user.update!(corp_num: "1234567890", corp_name: "델타디자인", ceo_name: "김델타",
                 corp_addr: "서울시 강남구 테헤란로 1", contact_name: "김델타",
                 barobill_id: "bd#{format('%018d', user.id)}", barobill_cert_registered: true)
  end

  def captured_line_items(invoice)
    payload = @client.calls[:regist_and_issue_tax_invoice].sole[:invoice]
    assert_equal invoice.subtotal.to_s, payload[:AmountTotal]
    assert_equal invoice.tax_amount.to_s, payload[:TaxTotal]
    payload[:TaxInvoiceTradeLineItems].map { |row| { Amount: row[:Amount], Tax: row[:Tax] } }
  end

  # paid 청구를 품목 행 구성으로 만든다 — 금액 컬럼은 Invoice.compute_amounts 산식 스냅샷.
  # 품목은 생성 시점 nested attributes로 넣는다(청구 생성 검증 — 행 1개 이상).
  def create_paid_invoice(tax_mode:, rows:)
    invoice = Invoice.create!(
      user: @user, client: @invoice.client, status: :paid,
      issue_number: "BD-TAXTEST-#{rows.hash.abs}", due_on: Date.current,
      tax_mode: tax_mode, withholding_enabled: false,
      issuer_display_name: "테스트발행자", bank_name: "신한은행",
      account_number: "110-234-567890", account_holder: "김델타",
      items_attributes: rows.map { |(quantity, unit_price)|
        { description: "테스트 품목 #{quantity}x#{unit_price}", quantity: quantity,
          unit_price: unit_price }
      },
      **amounts_for(rows, tax_mode)
    )
    invoice
  end

  def amounts_for(rows, tax_mode)
    Invoice.compute_amounts(rows.map { |q, p| q * p }, tax_mode: tax_mode,
                            withholding_enabled: false)
           .slice(:subtotal, :tax_amount, :total_amount, :withholding_amount, :net_amount)
  end

  def job_enqueued_args(job_class)
    enqueued_jobs.select { |j| j[:job] == job_class }.sole.fetch(:args)
  end

  def enqueued_poll_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { |j| j[:job] == TaxInvoices::PollStateJob }
        .map { |j| j[:args] }
  end
end

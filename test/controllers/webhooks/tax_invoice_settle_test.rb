require "test_helper"
require_relative "../../test_helpers/portone_stubbing"
require_relative "../../test_helpers/fake_portone_client"
require_relative "../../test_helpers/baro_bill_stubbing"
require_relative "../../test_helpers/fake_baro_bill_client"

# 세금계산서 주문 웹훅 확정(POST /webhooks/portone — Q21·SEC-5·PLAN-5 재사용) HTTP 통합 테스트.
# Transaction.Paid 중복 수신 → TaxInvoice 1건·PollStateJob 인계 1회·패스 발급 없음
# (product=collection_pass 함정 값 반응 없음)·위조 재조회 무변경·GuardFailed 흡수를 검증한다.
class Webhooks::TaxInvoiceSettleTest < ActionDispatch::IntegrationTest
  include PortOneStubbing
  include BaroBillStubbing

  setup do
    @user = users(:delta)
    @user.update!(corp_num: "1234567890", corp_name: "델타디자인", ceo_name: "김델타",
                  corp_addr: "서울시 강남구", contact_name: "김델타",
                  barobill_id: "bd#{format('%018d', @user.id)}", barobill_cert_registered: true)
    @invoice = invoices(:delta_paid)
    @order = @user.orders.create!(product: :collection_pass, item_type: :tax_invoice,
                                  amount: TaxInvoice::ISSUE_FEE,
                                  pg_order_id: "order-webhook-ti-1",
                                  metadata: { invoice_id: @invoice.id })
  end

  def post_paid_event
    fake = FakePortOneClient.new(
      get_payment: FakePortOneClient.paid_payment(id: @order.pg_order_id,
                                                  amount: TaxInvoice::ISSUE_FEE)
    )
    with_portone_client(fake) do
      post "/webhooks/portone",
           params: { type: "Transaction.Paid", data: { paymentId: @order.pg_order_id } }.to_json,
           headers: { "Content-Type" => "application/json" }
    end
    assert_response :ok
  end

  test "Transaction.Paid는 세금계산서 주문을 확정하고 발행 기록을 1건 만든다 (Q21)" do
    with_baro_bill_client(FakeBaroBillClient.new) do
      assert_enqueued_with job: TaxInvoices::PollStateJob do
        post_paid_event
      end
    end

    assert_predicate @order.reload, :paid?
    assert_equal @invoice.id, @order.metadata["invoice_id"]     # B-1 — 병합 보존
    assert_equal 1, TaxInvoice.where(invoice_id: @invoice.id).count
    # 함정 값(product=collection_pass)에 반응 없음 — 패스 발급 없음(fixture 1건 불변)
    assert_equal 1, @user.payment_passes.count
    assert_equal 10, @user.payment_passes.sole.remaining_uses
  end

  test "웹훅 중복 수신은 멱등으로 흡수된다 — 발행 기록 1건·폴링 인계 1회 (SEC-5)" do
    with_baro_bill_client(FakeBaroBillClient.new) do
      assert_enqueued_with job: TaxInvoices::PollStateJob do
        2.times { post_paid_event }
      end
    end

    assert_equal 1, TaxInvoice.where(invoice_id: @invoice.id).count
    assert_equal 1, @user.payment_passes.count                  # 패스 발급 없음
    assert_equal 1, enqueued_jobs.count { |j| j[:job] == TaxInvoices::PollStateJob }
  end

  test "재조회 응답이 타 결제면 무변경으로 흡수한다 (위조 이벤트 차단)" do
    fake = FakePortOneClient.new(get_payment: { id: "payment-of-other-order", status: "PAID" })

    with_portone_client(fake) do
      with_baro_bill_client(FakeBaroBillClient.new) do
        post "/webhooks/portone",
             params: { type: "Transaction.Paid", data: { paymentId: @order.pg_order_id } }.to_json,
             headers: { "Content-Type" => "application/json" }
      end
    end
    assert_response :ok

    assert_predicate @order.reload, :pending?
    assert_equal 0, TaxInvoice.count
    assert_equal 1, @user.payment_passes.count                  # 패스 발급 없음
  end

  test "발행 설정 미완료 주문도 결제 확정은 수행한다 — 가드 위반은 흡수(500 없음, C-2 전제)" do
    @user.update!(barobill_cert_registered: false)            # 설정 미완료

    with_baro_bill_client(FakeBaroBillClient.new) do
      assert_nothing_raised { post_paid_event }
    end

    assert_predicate @order.reload, :paid?
    assert_equal 0, TaxInvoice.count                           # 발행 기록 미생성 — C-2 가드 대상 상태
    assert_equal 1, @user.payment_passes.count                  # 패스 발급 없음
  end

  # TAX-3 ④(2026-11-24·Q25) — 부적격 사용자의 결제 완료 뒤 경로 최종 방어선. 결제는
  # 성립하되(되돌리지 않음) 발행 기록·바로빌 전송은 없다(GuardFailed 흡수).
  test "TAX-3: 부적격(간이과세) 사용자의 웹훅 확정은 결제만 수행하고 발행은 막는다" do
    @user.update!(tax_type: :simplified)
    client = FakeBaroBillClient.new

    with_baro_bill_client(client) do
      assert_nothing_raised { post_paid_event }
    end

    assert_predicate @order.reload, :paid?                     # 결제 성립은 유지
    assert_equal 0, TaxInvoice.count                           # 발행 기록 미생성
    assert_empty client.calls[:regist_and_issue_tax_invoice]   # 바로빌 전송 미수행
  end

  # TAX-4 회귀 — settle 경로는 운영 준비 게이트 스위치와 무관하게 동작한다(리뷰 중점 9).
  # 꺼짐이어도 이미 열려 있는 결제의 확정·발행이 끊기지 않는다(4 문언의 취지).
  test "TAX-4: 스위치가 꺼져 있어도 웹훅 확정·발행은 정상 수행된다" do
    client = FakeBaroBillClient.new

    with_tax_invoice_feature(false) do
      with_baro_bill_client(client) do
        assert_enqueued_with job: TaxInvoices::PollStateJob do
          post_paid_event
        end
      end
    end

    assert_predicate @order.reload, :paid?
    assert_equal 1, TaxInvoice.where(invoice_id: @invoice.id).count
    assert_equal 1, client.calls[:regist_and_issue_tax_invoice].count
  end
end

require "test_helper"
require_relative "../../test_helpers/fake_baro_bill_client"
require_relative "../../test_helpers/baro_bill_stubbing"

# 발행 상태 폴링(TaxInvoices::PollStateJob — TAX-2·C-4 상태 머신) 테스트.
# 3014+NTS4 → issued(승인번호 캡처)·NTS5 → failed·진행 중 재시도·10회 소진 → failed(C-4)·
# 종결 상태 재실행 no-op(멱등)을 검증한다. 바로빌 조회는 BaroBillStubbing으로 스텁(실호출 금지).
class TaxInvoices::PollStateJobTest < ActiveSupport::TestCase
  include BaroBillStubbing
  include ActiveJob::TestHelper
  setup do
    @user = users(:delta)
    @invoice = invoices(:delta_paid)
    @tax_invoice = TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-POLL-1",
                                      status: :pending, supply_total: 100_000,
                                      tax_total: 10_000, grand_total: 110_000)
  end

  def enqueued_poll_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs
        .select { |j| j[:job] == TaxInvoices::PollStateJob }
        .map { |j| j[:args] }
  end

  def fake_state(barobill_state:, nts_send_state:, nts_send_key: "20261116123456789012345678")
    FakeBaroBillClient.new(returns: { get_tax_invoice_state: {
      barobill_state: barobill_state, nts_send_state: nts_send_state,
      nts_send_key: nts_send_key
    } })
  end

  test "3014 + NTS 전송완료(4)면 issued로 확정하고 승인번호를 캡처한다 (TAX-2)" do
    with_baro_bill_client(fake_state(barobill_state: 3014, nts_send_state: 4)) do
      TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
    end

    @tax_invoice.reload
    assert_predicate @tax_invoice, :issued?
    assert_equal "20261116123456789012345678", @tax_invoice.nts_send_key
    assert_equal 3014, @tax_invoice.barobill_state
    assert_equal 4, @tax_invoice.nts_send_state
  end

  test "NTS 전송실패(5)면 failed로 확정한다" do
    with_baro_bill_client(fake_state(barobill_state: 3014, nts_send_state: 5,
                                     nts_send_key: "")) do
      TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
    end

    @tax_invoice.reload
    assert_predicate @tax_invoice, :failed?
    assert_nil @tax_invoice.nts_send_key                        # 승인번호 없음 — presence nil
  end

  test "진행 중(NTS 1~3)이면 재시도를 걸고 상태는 pending 유지" do
    before = enqueued_poll_jobs.size
    with_baro_bill_client(fake_state(barobill_state: 3014, nts_send_state: 2)) do
      TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)    # retry_on이 예외를 흡수해 재큐한다
    end

    assert_predicate @tax_invoice.reload, :pending?
    assert_equal 3014, @tax_invoice.barobill_state              # 조회 원값은 기록된다(P4)
    assert_equal before + 1, enqueued_poll_jobs.size            # 재시도 1회 인계
  end

  # C-4 — retry 10회 소진 시 failed 확정(영구 "발행 처리 중" 방지). executions를 소진 직전(9)으로
  # 세팅해 재시도 핸들러의 소진 분기(attempts: 10)를 직접 구동한다.
  test "C-4: 폴링 재시도 10회 소진 시 status가 failed로 확정된다" do
    client = FakeBaroBillClient.new(raise_on: { get_tax_invoice_state:
      BaroBill::ClientService::ApiError.new(code: "SOAP", message: "조회 실패") })

    job = TaxInvoices::PollStateJob.new(@tax_invoice.id)
    # 소진 시점 재현 — retry_on은 예외별 카운터(exception_executions)로 소진을 판정한다
    job.exception_executions["[BaroBill::ClientService::ApiError]"] = 9  # 이번 실행으로 10회 도달

    assert_raises(BaroBill::ClientService::ApiError) do
      with_baro_bill_client(client) { job.perform_now }
    end

    assert_predicate @tax_invoice.reload, :failed?              # 소진 핸들러가 failed 확정(C-4)
  end

  test "종결 상태(issued·canceled·failed) 재실행은 no-op이다 — 외부 조회 없음 (멱등)" do
    @tax_invoice.update!(status: :issued)
    client = FakeBaroBillClient.new

    with_baro_bill_client(client) do
      TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
    end

    assert_predicate @tax_invoice.reload, :issued?
    assert_empty client.calls.values.flatten
  end

  # 발행 완료 알림톡 훅(TAX-2·NOTI-1) — pending→issued 전이 확정 시 1회 호출. 잡은 서비스
  # 호출만 하고 발송 로직은 갖지 않는다(규약). 서비스를 스파이로 교체해 호출 인자·횟수만 검증.
  def with_notify_issued_spy
    calls = []
    original = TaxInvoices::NotifyIssuedService.method(:call)
    TaxInvoices::NotifyIssuedService.define_singleton_method(:call) do |**kwargs|
      calls << kwargs
      :sent
    end
    yield calls
  ensure
    TaxInvoices::NotifyIssuedService.define_singleton_method(:call, original)
  end

  test "pending→issued 전이 확정 시 발행 완료 알림 서비스를 1회 호출한다 (TAX-2·NOTI-1)" do
    with_notify_issued_spy do |calls|
      with_baro_bill_client(fake_state(barobill_state: 3014, nts_send_state: 4)) do
        TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
      end

      assert_equal 1, calls.size
      assert_equal @tax_invoice.reload, calls.sole[:tax_invoice], "확정(승인번호 캡처) 이후의 재적재본을 넘긴다"
    end
  end

  test "canceled·failed 전이에서는 발행 완료 알림 서비스를 호출하지 않는다 (트리거는 issued 한정)" do
    with_notify_issued_spy do |calls|
      with_baro_bill_client(fake_state(barobill_state: 5031, nts_send_state: 4,
                                       nts_send_key: "")) do
        assert_nothing_raised do
          TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
        end
      end
      # 5031(공급자 취소)은 issued·failed 어느 분기도 아니다 — PENDING 예외로 재시도 궤도.
      # 발행 완료 알림이 아닌 경로에서 호출이 없어야 한다.
      assert_empty calls

      @tax_invoice.reload
      return if @tax_invoice.issued? # 방어 — 전이 없이 pending이면 아래 failed 분기는 생략

      with_baro_bill_client(fake_state(barobill_state: 3014, nts_send_state: 5)) do
        TaxInvoices::PollStateJob.perform_now(@tax_invoice.id)
      end
      assert_empty calls, "failed 확정에서도 발행 완료 알림은 호출되지 않는다"
    end
  end

  test "삭제된 레코드의 폴링은 discard로 흡수된다" do
    tax_invoice_id = @tax_invoice.id
    @tax_invoice.destroy!

    assert_nothing_raised do
      with_baro_bill_client(FakeBaroBillClient.new) do
        TaxInvoices::PollStateJob.perform_now(tax_invoice_id)
      end
    end
  end
end

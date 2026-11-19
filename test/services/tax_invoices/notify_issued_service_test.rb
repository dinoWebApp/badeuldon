require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"

# TAX-2 · NOTI-1 — TaxInvoices::NotifyIssuedService(전자세금계산서 발행 완료 알림톡).
# sent(변수 5종·provider_message_id) / skipped(NO_PHONE) / skipped(NO_TEMPLATE — 등록 전
# 공백기 정상 경로) / failed(ApiError) / 멱등(확정 이력 존재 시 재발송 없음) 5분기를 검증한다.
# U1 이벤트 알림 — PLAN-3 상한·REM-3 발송 창 밖(noti_* 계열과 동일 범주). 솔라피는
# with_solapi_client로 차단 — 실호출 금지(AGENTS.md 테스트 전략).
class TaxInvoices::NotifyIssuedServiceTest < ActiveSupport::TestCase
  include SolapiStubbing
  setup do
    @user = users(:delta) # phone 등록 완료
    @invoice = invoices(:delta_paid)
    @tax_invoice = TaxInvoice.create!(invoice: @invoice, user: @user, mgt_num: "TI-NOTI-1",
                                      status: :issued, supply_total: 100_000,
                                      tax_total: 10_000, grand_total: 110_000,
                                      nts_send_key: "20261119123456789012345678")
    @fake = FakeSolapiClient.new
  end

  test "성공 — :sent 반환·MessageLog sent 기록·변수 5종·provider_message_id 캡처 (TAX-2·P4)" do
    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client @fake do
        result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
      end
    end

    assert_equal :sent, result
    log = MessageLog.last
    assert log.sent?
    assert_equal @tax_invoice.invoice_id, log.invoice_id
    assert_equal @user.id, log.user_id
    assert_equal "user", log.recipient_role
    assert_equal "noti_tax_issued", log.template_key
    assert_equal "010-5555-1111", log.phone # user.phone 원값 스냅샷(NOTI 선례 — 하이픈 유지)
    assert_equal "msg_fake_1", log.provider_message_id
    assert_not_nil log.sent_at

    talk = @fake.successful_calls.sole
    assert_equal "noti_tax_issued", talk[:template_key]
    assert_equal "010-5555-1111", talk[:to] # FakeSolapiClient는 원값 기록 — 하이픈 정규화는 래퍼 책임
    variables = log.variables
    assert_equal "델타디자인", variables["발행인명"]
    assert_equal "델타파트너스", variables["거래처명"]
    assert_equal "110,000", variables["금액"]
    assert_equal "20261119123456789012345678", variables["승인번호"]
    assert_equal "badeuldon.kr#{Rails.application.routes.url_helpers.app_invoice_path(@invoice)}",
                 variables["url"]
  end

  test "수신번호 미등록 — :skipped·NO_PHONE 기록·솔라피 호출 없음" do
    @user.update_columns(phone: nil)
    no_call = Object.new
    def no_call.send_alimtalk(**)
      raise "솔라피 호출이 발생해서는 안 된다"
    end

    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client no_call do
        result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
      end
    end

    assert_equal :skipped, result
    log = MessageLog.last
    assert log.skipped?
    assert_equal "NO_PHONE", log.error_code
    assert_nil log.phone
  end

  test "템플릿 미등록(MISSING_TEMPLATE) — failed가 아닌 :skipped·NO_TEMPLATE 기록 (등록 전 공백기)" do
    failing = FakeSolapiClient.new(
      raise_on: { "noti_tax_issued" => Solapi::ApiError.new(status: nil, code: "MISSING_TEMPLATE",
                                                            message: "템플릿 코드가 없습니다") }
    )

    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client failing do
        result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
      end
    end

    assert_equal :skipped, result
    log = MessageLog.last
    assert log.skipped?
    assert_equal "NO_TEMPLATE", log.error_code
    assert_equal "템플릿 코드가 없습니다", log.error_message
  end

  test "솔라피 실패(ApiError) — :failed 반환·failed 기록·폴링 잡으로 예외 누출 없음" do
    failing = FakeSolapiClient.new(
      raise_on: { "noti_tax_issued" => Solapi::ApiError.new(status: 400, code: "E400",
                                                            message: "검수중 템플릿") }
    )

    result = nil
    assert_difference -> { MessageLog.count }, 1 do
      with_solapi_client failing do
        result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
      end
    end

    assert_equal :failed, result
    log = MessageLog.last
    assert log.failed?
    assert_equal "E400", log.error_code
    assert_equal "검수중 템플릿", log.error_message
    assert_equal "010-5555-1111", log.phone
  end

  test "멱등 — 확정 이력(sent) 존재 시 재호출은 :skipped·재발송·신규 로그 없음 (폴링 재실행 대비)" do
    with_solapi_client @fake do
      assert_equal :sent, TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
    end

    # 재적재 후 재호출 — 폴링 잡 재실행 시나리오(연관 캐시 함정 회피를 위해 reload)
    count_after_first = MessageLog.count
    calls_after_first = @fake.calls.size
    result = nil
    with_solapi_client @fake do
      result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice.reload)
    end

    assert_equal :skipped, result
    assert_equal count_after_first, MessageLog.count, "확정 이력이 있으면 새 로그를 만들지 않는다"
    assert_equal calls_after_first, @fake.calls.size, "재발송이 일어나지 않는다"
  end

  test "failed 이력도 확정 이력으로 간주한다 — 무한 재시도 루프 방지 (멱등 가드)" do
    failing = FakeSolapiClient.new(
      raise_on: { "noti_tax_issued" => Solapi::ApiError.new(status: 400, code: "E400",
                                                            message: "검수중 템플릿") }
    )
    with_solapi_client failing do
      assert_equal :failed, TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
    end

    calls_after_first = failing.calls.size
    result = nil
    with_solapi_client failing do
      result = TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice.reload)
    end

    assert_equal :skipped, result
    assert_equal calls_after_first, failing.calls.size
  end

  test "세금계산서 알림은 PLAN-3 상한 집계 밖이다 (U1 이벤트 알림 — noti_* 계열)" do
    with_solapi_client @fake do
      TaxInvoices::NotifyIssuedService.call(tax_invoice: @tax_invoice)
    end
    assert_equal 0, MessageLog.sequence_sent_count(@invoice.id)
    refute_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "noti_tax_issued"
  end
end

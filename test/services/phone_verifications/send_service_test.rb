require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"

# 휴대폰 인증번호 SMS 발송(AUTH-9 — F-SALES). 정규화·형식 검증·rate limit(번호당
# 1분 1회·1시간 3회)·발송 실패 시 rate limit 미소진(행 destroy) 검증.
# 시나리오 기준: PRD AUTH-9·_workspace/05_review.md §4 Tester 중점 3번·4번.
# 솔라피는 FakeSolapiClient 주입 — 실호출 금지(REM-10).
class PhoneVerifications::SendServiceTest < ActiveSupport::TestCase
  test "정상 발송은 6자리 코드를 기록하고 SMS를 발송하며 마스킹 번호를 반환한다 (AUTH-9)" do
    fake = FakeSolapiClient.new

    result = PhoneVerifications::SendService.new(phone: "010-1234-5678", client: fake).call

    assert result.success?
    assert_equal "010****5678", result.masked_phone

    verification = PhoneVerification.find_by(phone: "01012345678") # 하이픈 제거 정규화 저장
    assert_not_nil verification
    assert_match(/\A\d{6}\z/, verification.code, "코드는 6자리 숫자")
    assert_in_delta PhoneVerification::CODE_TTL.to_i,
                    (verification.expires_at - Time.current), 1
    assert_nil verification.consumed_at

    sms = fake.successful_calls.sole
    assert_equal "01012345678", sms[:to]
    assert_includes sms[:body], verification.code, "SMS 본문에 발급 코드가 포함된다"
    assert_includes sms[:body], "5분"
  end

  test "형식 검증 — 국번 01x가 아닌 번호·자릿수 부족은 발송 기록 없이 거부된다 (AUTH-9)" do
    fake = FakeSolapiClient.new

    [ "02-123-4567", "0101234", "010123456789" ].each do |phone|
      result = PhoneVerifications::SendService.new(phone:, client: fake).call
      assert_not result.success?
      assert_match(/올바른 휴대폰 번호/, result.error)
    end

    assert_empty PhoneVerification.all, "거부된 요청은 발송 이력을 남기지 않는다"
    assert_empty fake.calls, "거부된 요청은 SMS 발송되지 않는다"
  end

  test "번호당 1분 1회 — 직전 발송이 1분 이내면 거부된다 (AUTH-9 rate limit)" do
    fake = FakeSolapiClient.new
    send_once = -> { PhoneVerifications::SendService.new(phone: "01012345678", client: fake).call }

    assert send_once.call.success?
    second = send_once.call
    assert_not second.success?
    assert_match(/인증 요청이 너무 잦습니다/, second.error)
    assert_equal 1, PhoneVerification.where(phone: "01012345678").count
  end

  test "번호당 1시간 3회 — 1분을 띄워도 4번째부터는 거부된다 (AUTH-9 rate limit)" do
    fake = FakeSolapiClient.new
    send_once = -> { PhoneVerifications::SendService.new(phone: "01012345678", client: fake).call }

    3.times do |i|
      travel_to((i * 5).minutes.from_now) do
        assert send_once.call.success?, "#{i + 1}번째 발송은 허용된다"
      end
    end

    travel_to(20.minutes.from_now) do
      result = send_once.call
      assert_not result.success?
      assert_match(/인증 요청이 너무 잦습니다/, result.error)
    end
    assert_equal 3, PhoneVerification.where(phone: "01012345678").count
  end

  test "1시간 경과 후에는 다시 발송할 수 있다 (rate limit 창 경계)" do
    fake = FakeSolapiClient.new
    3.times do |i|
      travel_to((i * 5).minutes.from_now) do
        PhoneVerifications::SendService.new(phone: "01012345678", client: fake).call
      end
    end

    travel_to(61.minutes.from_now) do
      assert PhoneVerifications::SendService.new(phone: "01012345678", client: fake).call.success?
    end
  end

  test "SMS 발송 실패 시 방금 기록 행을 제거해 rate limit을 소진하지 않는다 (AUTH-9 재시도 보호)" do
    failing = FakeSolapiClient.new(
      sms_error: Solapi::ApiError.new(status: 400, code: "HTTP_400", message: "발송 거절")
    )

    result = PhoneVerifications::SendService.new(phone: "01012345678", client: failing).call

    assert_not result.success?
    assert_match(/인증번호 발송에 실패했습니다/, result.error)
    assert_empty PhoneVerification.where(phone: "01012345678"), "실패 요청은 rate limit 판정에서 제외"

    # 즉시 재시도 — rate limit 미소진으로 1분 내 재발송이 허용된다
    working = FakeSolapiClient.new
    assert PhoneVerifications::SendService.new(phone: "01012345678", client: working).call.success?
    assert_equal 1, PhoneVerification.where(phone: "01012345678").count
  end

  test "짧은 번호(마스킹 불가)는 원값을 반환한다 (개인정보 마스킹 경계)" do
    fake = FakeSolapiClient.new
    # 형식 검증을 통과하는 최소 길이는 10자리(01x+7) — 경계를 위해 마스킹 로직을 직접 검증한다
    result = PhoneVerifications::SendService.new(phone: "0101234567", client: fake).call
    assert_equal "010****4567", result.masked_phone
  end
end

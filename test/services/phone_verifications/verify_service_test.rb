require "test_helper"

# 휴대폰 인증번호 확인(AUTH-9 — F-SALES). 없음/만료/시도 초과/불일치 분기·성공 시
# 1회용 소비(consumed)·실패 시 attempts 증가 추적.
# 시나리오 기준: PRD AUTH-9(1회용·5회 제한·5분 만료)·_workspace/05_review.md §4 Tester 중점 2번.
class PhoneVerifications::VerifyServiceTest < ActiveSupport::TestCase
  setup do
    @verification = PhoneVerification.create!(phone: "01012345678", code: "123456",
                                              expires_at: PhoneVerification::CODE_TTL.from_now)
  end

  test "일치 코드는 검증에 성공하고 consumed 마킹된다 (AUTH-9)" do
    result = PhoneVerifications::VerifyService.new(phone: "010-1234-5678", code: "123456").call

    assert result.verified?
    assert_equal :verified, result.status
    assert @verification.reload.consumed?
    assert_equal 0, @verification.attempts
  end

  test "발급 이력이 없는 번호는 no_request로 거부된다 (AUTH-9)" do
    result = PhoneVerifications::VerifyService.new(phone: "01099999999", code: "123456").call

    assert_not result.verified?
    assert_equal :no_request, result.status
    assert_match(/요청부터 다시/, result.error)
  end

  test "5분 경과한 코드는 만료로 거부된다 (AUTH-9 — TTL 경계)" do
    travel_to(PhoneVerification::CODE_TTL.from_now + 1.second) do
      result = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call
      assert_not result.verified?
      assert_equal :expired, result.status
      assert_nil @verification.reload.consumed_at, "만료 코드는 소비되지 않는다"
    end
  end

  test "TTL 직전(5분 - 1초)의 코드는 아직 유효하다 (AUTH-9 경계)" do
    travel_to(PhoneVerification::CODE_TTL.from_now - 1.second) do
      result = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call
      assert result.verified?
    end
  end

  test "불일치 코드는 attempts를 증가시키고 검증에 실패한다 (AUTH-9)" do
    result = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "999999").call

    assert_not result.verified?
    assert_equal :mismatch, result.status
    assert_equal 1, @verification.reload.attempts
    assert_nil @verification.consumed_at
  end

  test "시도 5회 초과 코드는 만료보다 나중에 판정되어 차단된다 (AUTH-9 — 5회 제한)" do
    5.times { @verification.record_attempt! }

    result = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call

    assert_not result.verified?
    assert_equal :attempts_exceeded, result.status, "정확한 코드라도 시도 초과면 차단"
    assert_nil @verification.reload.consumed_at
  end

  test "4회 실패 후 5회째 불일치로 한도에 도달하면 이후 정확한 코드도 차단된다 (AUTH-9 경계)" do
    4.times do
      PhoneVerifications::VerifyService.new(phone: "01012345678", code: "000000").call
    end
    assert_equal 4, @verification.reload.attempts

    fifth = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "000000").call
    assert_not fifth.verified?
    assert_equal 5, @verification.reload.attempts

    blocked = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call
    assert_not blocked.verified?
    assert_equal :attempts_exceeded, blocked.status
  end

  test "이미 소비된 정확한 코드의 재사용은 실패한다 (AUTH-9 — 1회용·SEC-5)" do
    first = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call
    assert first.verified?

    second = PhoneVerifications::VerifyService.new(phone: "01012345678", code: "123456").call
    assert_not second.verified?, "consumed 행은 consume! 실패로 재검증 불가"
    assert_equal 1, @verification.reload.attempts, "재사용 시도도 실패로 기록된다"
  end

  test "만료 후 신규 발급은 새 코드로 검증할 수 있다 — 이전 코드는 별개 행이다 (AUTH-9)" do
    travel_to(6.minutes.from_now) do
      PhoneVerifications::SendService.new(phone: "01012345678", client: FakeSolapiClient.new).call
    end
    new_code = PhoneVerification.where(phone: "01012345678").order(:created_at).last.code

    result = PhoneVerifications::VerifyService.new(phone: "01012345678", code: new_code).call
    assert result.verified?
    assert_equal new_code, PhoneVerification.where(phone: "01012345678").consumed_recently.sole.code
  end
end

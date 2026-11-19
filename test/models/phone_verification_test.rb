require "test_helper"

# 휴대폰 SMS 인증 모델(AUTH-9 — F-SALES). 5분 만료·시도 5회·1회용 consumed·
# 가입 이중 검증용 consumed_recently(30분 창) 경계 검증.
# 시나리오 기준: PRD AUTH-9·_workspace/05_review.md §4 Tester 중점 2번·3번.
class PhoneVerificationTest < ActiveSupport::TestCase
  setup do
    @verification = PhoneVerification.create!(phone: "01011112222", code: "123456",
                                              expires_at: PhoneVerification::CODE_TTL.from_now)
  end

  test "expired?는 5분 TTL 경계를 판정한다 (AUTH-9 — 5분 만료)" do
    assert_not @verification.expired?

    travel_to(PhoneVerification::CODE_TTL.from_now + 1.second) do
      assert @verification.expired?
    end

    travel_to(PhoneVerification::CODE_TTL.from_now - 1.second) do
      assert_not @verification.expired?
    end
  end

  test "attempts_exceeded?는 5회에서 참이 된다 (AUTH-9 — 시도 5회 제한)" do
    4.times { @verification.record_attempt! }
    assert_not @verification.attempts_exceeded?

    @verification.record_attempt!
    assert_equal 5, @verification.attempts
    assert @verification.attempts_exceeded?
  end

  test "consume!은 consumed 마킹으로 1회용을 보장한다 — 재호출은 false (SEC-5)" do
    assert @verification.consume!, "첫 소비는 성공"
    assert @verification.consumed?
    assert_not_nil @verification.consumed_at

    assert_not @verification.consume!, "이미 소비된 코드는 재사용 불가(1회용)"
  end

  test "consumed_recently는 30분 창 이내의 소비 행만 반환한다 (AUTH-9 가입 이중 검증)" do
    @verification.consume!

    assert_includes PhoneVerification.consumed_recently, @verification

    travel_to(29.minutes.from_now) do
      assert_includes PhoneVerification.consumed_recently, @verification, "창 이내(29분)는 유효"
    end

    travel_to(31.minutes.from_now) do
      assert_not_includes PhoneVerification.consumed_recently, @verification, "창 경과(31분)는 제외"
    end
  end

  test "consumed_recently는 미소비 행을 포함하지 않는다 (AUTH-9)" do
    assert_not_includes PhoneVerification.consumed_recently, @verification
    assert_empty PhoneVerification.consumed_recently
  end

  test "sent_within은 rate limit 조회용 최근 발송 이력을 반환한다 (AUTH-9)" do
    travel_to(2.minutes.from_now) do
      PhoneVerification.create!(phone: "01011112222", code: "654321",
                                expires_at: PhoneVerification::CODE_TTL.from_now)

      assert_equal 1, PhoneVerification.sent_within(1.minute).where(phone: "01011112222").count,
                   "1분 창은 신규 행만"
      assert_equal 2, PhoneVerification.sent_within(1.hour).where(phone: "01011112222").count,
                   "1시간 창은 전부"
    end
  end

  test "phone은 하이픈 없는 숫자로 정규화된다 (AUTH-9)" do
    row = PhoneVerification.create!(phone: "010-3333-4444", code: "999999",
                                    expires_at: PhoneVerification::CODE_TTL.from_now)
    assert_equal "01033334444", row.phone
  end
end

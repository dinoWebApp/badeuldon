require "test_helper"
require_relative "../test_helpers/portone_stubbing"
require_relative "../test_helpers/fake_portone_client"

# 일간 갱신 잡(F-PLAN — PLAN-2/5) — 채널 키 미등록(PLAN-5·리뷰 W-2) 내구성 테스트.
# 채널 키가 없어도(설정 오류) 잡 전체가 멈추지 않는다: ① 차감 대상 구독은 건너뛰되 선기록된
# pending 주문은 트랜잭션 롤백으로 남지 않고(ADMIN-4 실패 주문 오염 없음) ② 해지 후 주기 종료
# 구독의 만료 강등(클라이언트 호출 없는 경로)은 계속 처리된다 ③ 건너뛰기는 오류 로그를 남긴다
# ④ 전용 예외(MissingChannelKey)가 아닌 코드 오류는 삼키지 않는다.
#
# 가드(ClientService#ensure_channel_key!)는 HTTP 요청 전에 예외를 던지므로 전송 계층 대역 없이
# 실행해도 실호출이 일어나지 않는다 — 우발적 유출 시에는 TEST_GUARD(ApiError)가 잡 밖으로
# 나가 테스트를 실패시켜 노출한다. 코드 오류 경계(테스트 3)만 FakePortOneClient로 예외를 주입해
# 잡의 rescue 경계를 검증한다.
class SubscriptionRenewalJobTest < ActiveSupport::TestCase
  include PortOneStubbing

  setup do
    @charged_user = users(:gamma)
    @charged = @charged_user.create_subscription!(plan: :plus, status: :active,
                                                  pg_billing_key: "tok_billing_renew_guard",
                                                  current_period_start: Time.zone.parse("2026-10-01 09:00"),
                                                  current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    @cancelled_user = users(:delta)
    @cancelled = @cancelled_user.create_subscription!(plan: :plus, status: :cancelled,
                                                      current_period_start: Time.zone.parse("2026-10-01 09:00"),
                                                      current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    # epsilon fixture(active·주기 종료)의 간섭 제거 — 이 테스트의 대상은 위 두 구독이다
    Subscription.find_by(user_id: users(:epsilon).id)
                &.update_columns(current_period_end: Time.zone.parse("2027-10-31 23:59:59"))
  end

  test "채널 키가 없어도 차감 대상만 건너뛰고 해지 구독의 만료 강등은 계속 처리된다 (PLAN-5·리뷰 W-2)" do
    with_portone_channel_keys(billing: nil) do
      travel_to(Time.zone.parse("2026-11-01 06:00")) do
        assert_nothing_raised do
          SubscriptionRenewalJob.perform_now
        end
      end
    end

    # 차감 대상(gamma·빌링키 보유) — 키 없음: 가드가 API 호출 전에 막고 잡은 멈추지 않는다
    @charged.reload
    assert_predicate @charged, :active?
    assert_equal 0, @charged.dunning_stage                   # 카드 거절과 구분 — dunning 진입 없음
    assert_nil @charged.next_retry_at
    assert_equal Time.zone.parse("2026-10-31 23:59:59"), @charged.current_period_end
    # 차감 전 선기록 pending 주문은 롤백으로 남지 않는다(SEC-5 멱등 — 실패 주문 오염 없음)
    assert_empty @charged_user.orders

    # 해지 후 주기 종료(delta) — 만료 강등은 클라이언트 호출이 없어 키 부재와 무관하게 처리된다
    @cancelled.reload
    assert_predicate @cancelled, :expired?
    assert_predicate @cancelled, :free?
    assert_nil @cancelled.pg_billing_key
    assert_nil @cancelled.current_period_end
  end

  test "채널 키 미등록으로 건너뛴 구독은 오류 로그를 남긴다 (리뷰 W-2)" do
    io = StringIO.new
    captured = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(captured)
    begin
      with_portone_channel_keys(billing: nil) do
        travel_to(Time.zone.parse("2026-11-01 06:00")) do
          SubscriptionRenewalJob.perform_now
        end
      end
    ensure
      Rails.logger.stop_broadcasting_to(captured)
    end

    assert_includes io.string, "[SubscriptionRenewalJob]"
    assert_includes io.string, "user=#{@charged_user.id}"
  end

  test "전용 예외가 아닌 코드 오류는 잡이 삼키지 않고 실패한다 (범용 rescue 금지 — W-2)" do
    raising = FakePortOneClient.new(
      raise_on: { charge_billing_key: ArgumentError.new("코드 오류") }
    )

    with_portone_channel_keys(billing: "test-channel-billing-sentinel") do
      with_portone_client(raising) do
        travel_to(Time.zone.parse("2026-11-01 06:00")) do
          assert_raises(ArgumentError) do
            SubscriptionRenewalJob.perform_now
          end
        end
      end
    end

    # 코드 오류도 트랜잭션은 롤백된다 — pending 주문 오염 없음
    assert_empty @charged_user.reload.orders
    assert_predicate @charged.reload, :active?
  end
end

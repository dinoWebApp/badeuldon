require "test_helper"
require_relative "../../test_helpers/fake_portone_client"
require_relative "../../test_helpers/portone_stubbing"

# PLAN-5 dunning(구독 결제 실패 재시도 — T5·2026-11-16 확정) 테스트.
# 재리뷰 최우선 지시(05_review.md — C-1/C-2 회귀): dunning_active?가 status를 판정에 포함하는
# 1줄 수정이 renew·retry_charge·DunningRetryJob·갱신 스윕·ADMIN 뷰 전체에 파급되므로
# ① 진입 ② 재차감 성공 ③ 해지 후 무차감(C-1) ④ 3회 소진→cancelled→갱신 스윕 expire!(C-2)
# ⑤ 갱신 Job과의 경합 ⑥ ADMIN-4 표기 ⑦ 모호 실패·settle 회복을 고정한다.
# 포트원은 FakePortOneClient 주입 — 실호출 0건. 시간은 travel_to KST 고정(TIME-1).
class Subscriptions::DunningRetryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include PortOneStubbing

  fixtures :users

  FAILED = PortOne::ApiError.new(status: 400, code: "PG_PROVIDER_ERROR",
                                 message: "PG사 승인이 거절되었습니다",
                                 pg_code: "F1001", pg_message: "한도초과")
  AMBIGUOUS = PortOne::ApiError.new(status: nil, code: "TIMEOUT", message: "응답 시간 초과")

  setup do
    @user = users(:gamma)
    @sub = @user.create_subscription!(plan: :plus, status: :active,
                                      pg_billing_key: "tok_billing_dunning",
                                      current_period_start: Time.zone.parse("2026-10-01 09:00"),
                                      current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    @failing = FakePortOneClient.new(raise_on: { charge_billing_key: FAILED })
    @ok = FakePortOneClient.new(charge_billing_key: { payment: { id: "payment_retry_ok", status: "PAID" } })
  end

  # ── ① 진입 — 갱신 차감 명확 실패 → stage 1·D+1·Job 예약 ──

  test "갱신 차감 명확 실패는 dunning 1단계 진입과 D+1 재시도 Job 예약을 남긴다 (PLAN-5)" do
    error = nil
    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      assert_enqueued_with job: Subscriptions::DunningRetryJob, args: [ @sub.id ] do
        error = assert_raises(Subscriptions::UpgradeService::UpgradeError) do
          Subscriptions::UpgradeService.new(user: @user, action: :renew,
                                            channel_key: "test-channel-billing", client: @failing).call
        end
      end
    end

    assert_match(/재시도 1\/3/, error.message)
    @sub.reload
    assert_predicate @sub, :active?                       # 즉시 강등 아님 — dunning 진입
    assert_predicate @sub, :plus?
    assert_equal 1, @sub.dunning_stage
    assert_equal Time.zone.parse("2026-11-02 06:05"), @sub.next_retry_at   # D+1
    assert_not_nil @sub.last_payment_failed_at
    assert_equal "tok_billing_dunning", @sub.pg_billing_key               # 재차감용 빌링키 유지
    assert_predicate @sub, :dunning_active?
    assert_predicate @user.orders.sole, :failed?
  end

  # ── ② 재차감 성공 → 주기 연장·dunning 리셋 ──

  test "D+1 재차감 성공은 주기를 연장하고 dunning을 초기화한다 (PLAN-5 회복)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"),
                 last_payment_failed_at: Time.zone.parse("2026-11-01 06:05"))

    travel_to(Time.zone.parse("2026-11-02 06:05")) do
      with_portone_client(@ok) do
        Subscriptions::DunningRetryJob.perform_now(@sub.id)
      end
    end

    @sub.reload
    assert_predicate @sub, :active?
    assert_equal 0, @sub.dunning_stage                    # reset_dunning!
    assert_nil @sub.next_retry_at
    assert_not_predicate @sub, :dunning_active?
    assert_equal Time.zone.parse("2026-11-30 23:59:59"), @sub.current_period_end # 1개월 연장
    charge = @ok.calls[:charge_billing_key].sole
    assert_equal "tok_billing_dunning", charge[:billing_key]
    assert_equal 9_900, charge[:amount]                   # 재과금 정상가 — 쿠폰 재적용 없음
    assert_predicate @user.orders.sole.reload, :paid?
  end

  # ── ③ C-1 회귀 — 해지 후 D+1 무차감 ──

  test "dunning 중 해지한 구독은 D+1 재시도 Job 실행 시 차감되지 않는다 (C-1 회귀)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"),
                 last_payment_failed_at: Time.zone.parse("2026-11-01 06:05"))
    @sub.cancel!                                          # 사용자가 /app/billing에서 해지
    fake = @ok                                            # 차감되면 안 되므로 성공 스텁을 꽂는다

    travel_to(Time.zone.parse("2026-11-02 06:05")) do
      with_portone_client(fake) do
        Subscriptions::DunningRetryJob.perform_now(@sub.id)
      end
    end

    assert_empty fake.calls.values.flatten                # 포트원 호출 0건 — 무단 재차감 없음
    @sub.reload
    assert_predicate @sub, :cancelled?
    assert_equal 1, @sub.dunning_stage                    # 상태 불변
    assert_not_predicate @sub, :dunning_active?
  end

  test "해지 구독에 대한 retry_charge 직접 호출도 무차감 no-op이다 (C-1 — 서비스 가드)" do
    @sub.update!(dunning_stage: 1, next_retry_at: 1.hour.ago)
    @sub.cancel!

    Subscriptions::UpgradeService.new(user: @user, action: :retry_charge,
                                      channel_key: "test-channel-billing", client: @ok).call

    assert_empty @ok.calls.values.flatten
    assert_predicate @sub.reload, :cancelled?
    assert_equal 0, @user.orders.count                    # 주문 선기록도 없음
  end

  # ── ④ C-2 회귀 — 3회 소진 cancel! → 갱신 스윕 expire! ──

  test "재시도 3회 소진 실패는 cancelled로 전환하고 다음 일간 갱신 스윕에서 Free 강등된다 (C-2 회귀)" do
    # 3회 재시도까지 모두 실패한 상태(stage 3·D+7 재시도 대기)에서 마지막 재시도가 실패
    @sub.update!(dunning_stage: 3, next_retry_at: Time.zone.parse("2026-11-08 06:05"),
                 last_payment_failed_at: Time.zone.parse("2026-11-05 06:05"))

    travel_to(Time.zone.parse("2026-11-08 06:05")) do
      with_portone_client(@failing) do
        Subscriptions::DunningRetryJob.perform_now(@sub.id)
      end
    end

    @sub.reload
    assert_predicate @sub, :cancelled?                    # 소진 — 해지 전환
    assert_equal 3, @sub.dunning_stage                    # DUNNING_MAX_STAGE 고정
    assert_nil @sub.next_retry_at
    assert_predicate @user.orders.reload.sole, :failed?

    # 다음 일간 갱신 스윕 — due_subscriptions는 cancelled 포함 → expire!에 도달해야 한다(C-2)
    # 스윕은 due 구독 전체를 돌므로 epsilon fixture(active·주기 종료 10-31)의 차감 간섭을
    # 제거한다(아래 ⑤와 같은 방식). 잡 실행은 대역 필수 — 대역 없이는 운영 API 실호출이
    # 나간다(2026-11-24 TEST_GUARD 가드 도입 계기 — 리뷰 R3).
    Subscription.find_by(user_id: users(:epsilon).id)
                &.update_columns(current_period_end: Time.zone.parse("2027-10-31 23:59:59"))

    travel_to(Time.zone.parse("2026-11-09 06:05")) do
      with_portone_client(@ok) do
        SubscriptionRenewalJob.perform_now
      end
    end

    assert_empty @ok.calls.values.flatten                 # 강등 경로에서 차감 API 호출 없음
    @sub.reload
    assert_predicate @sub, :expired?                      # 무료 Plus 영구 잔존 금지(PLAN-5)
    assert_predicate @sub, :free?
    assert_nil @sub.pg_billing_key
    assert_nil @sub.current_period_end
  end

  # ── ⑤ 갱신 Job과의 경합 — dunning 중 스윕은 차감하지 않는다 ──

  test "dunning 진행 중 구독은 일간 갱신 스윕에서 차감·만료되지 않는다 (경합 방지)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"),
                 current_period_end: Time.zone.parse("2026-10-31 23:59:59"))
    # epsilon fixture(active·주기 종료 10-31)가 스윕에서 차감되는 간섭을 제거한다 — 이 테스트의
    # 대상은 @sub의 무변경이다.
    Subscription.find_by(user_id: users(:epsilon).id)
                &.update_columns(current_period_end: Time.zone.parse("2027-10-31 23:59:59"))

    travel_to(Time.zone.parse("2026-11-01 06:05")) do
      with_portone_client(@ok) do
        SubscriptionRenewalJob.perform_now
      end
    end

    assert_empty @ok.calls.values.flatten                 # 스윕이 재차감을 우회하지 않음
    @sub.reload
    assert_predicate @sub, :active?                       # expire!도 아님
    assert_equal 1, @sub.dunning_stage
  end

  # ── Job 멱등 가드 ──

  test "재시도 Job은 dunning 비대상이면 no-op이고 미래 예약이면 재예약한다 (멱등)" do
    # 성공으로 리셋된 구독 — no-op
    @sub.update!(dunning_stage: 0, next_retry_at: nil)
    assert_no_enqueued_jobs only: Subscriptions::DunningRetryJob do
      Subscriptions::DunningRetryJob.perform_now(@sub.id)
    end
    assert_empty @ok.calls.values.flatten

    # next_retry_at 미래 — 그 시각으로 재예약 후 종료(차감 없음)
    @sub.update!(dunning_stage: 1, next_retry_at: 3.hours.from_now)
    assert_enqueued_with job: Subscriptions::DunningRetryJob, args: [ @sub.id ] do
      with_portone_client(@ok) do
        Subscriptions::DunningRetryJob.perform_now(@sub.id)
      end
    end
    assert_empty @ok.calls.values.flatten
  end

  # ── ⑦ 모호 실패(TIMEOUT) — dunning 진입 없음·settle_renewal 회복 ──

  test "모호 차감 실패는 dunning 단계를 진행하지 않고 pending 주문으로 회복을 연다 (PLAN-5)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"),
                 last_payment_failed_at: Time.zone.parse("2026-11-01 06:05"))
    ambiguous = FakePortOneClient.new(raise_on: { charge_billing_key: AMBIGUOUS })

    travel_to(Time.zone.parse("2026-11-02 06:05")) do
      # UpgradeError 상승은 정상 — 잡 계층(DunningRetryJob)이 로그만 남기고 흡수한다
      assert_raises(Subscriptions::UpgradeService::UpgradeError) do
        Subscriptions::UpgradeService.new(user: @user, action: :retry_charge,
                                          channel_key: "test-channel-billing", client: ambiguous).call
      end
    end

    order = @user.orders.sole.reload
    assert_predicate order, :pending?                     # 실패 확정 금지
    assert order.metadata["ambiguous"].present?
    @sub.reload
    assert_equal 1, @sub.dunning_stage                    # 단계 진행 없음
    assert_equal Time.zone.parse("2026-11-02 06:05"), @sub.next_retry_at

    # 웹훅 회복 — 실제로는 성공이었음 → paid 확정·주기 연장·dunning 리셋
    Subscriptions::UpgradeService.new(user: @user, action: :settle_renewal,
                                      order: order, payment: { id: "payment_hook_1" },
                                      client: @ok).call
    order.reload
    assert_predicate order, :paid?
    @sub.reload
    assert_equal 0, @sub.dunning_stage
    assert_nil @sub.next_retry_at
    assert @sub.current_period_end > Time.zone.parse("2026-11-02 06:05")
  end

  # ── PLAN-5 채널 키 미등록(리뷰 W-2) — 카드 거절과 구분: 단계·예약·주문 무변경 ──

  test "채널 키 미등록 재차감은 dunning 단계·재시도 예약·주문 수를 무변경으로 두고 잡은 실패하지 않는다 (PLAN-5)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"),
                 last_payment_failed_at: Time.zone.parse("2026-11-01 06:05"))

    with_portone_channel_keys(billing: nil) do
      travel_to(Time.zone.parse("2026-11-02 06:05")) do
        assert_nothing_raised do
          Subscriptions::DunningRetryJob.perform_now(@sub.id)
        end
      end
    end

    @sub.reload
    assert_predicate @sub, :active?
    assert_equal 1, @sub.dunning_stage                       # 카드 거절이 아니므로 단계 진행 없음
    assert_equal Time.zone.parse("2026-11-02 06:05"), @sub.next_retry_at
    assert_predicate @sub, :dunning_active?
    assert_empty @user.orders, "설정 오류는 실패 주문으로 남지 않는다(롤백)"
  end

  test "전용 예외가 아닌 코드 오류는 재시도 잡도 삼키지 않는다 (범용 rescue 금지 — W-2)" do
    @sub.update!(dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-02 06:05"))
    raising = FakePortOneClient.new(raise_on: { charge_billing_key: ArgumentError.new("코드 오류") })

    with_portone_channel_keys(billing: "test-channel-billing-sentinel") do
      with_portone_client(raising) do
        travel_to(Time.zone.parse("2026-11-02 06:05")) do
          assert_raises(ArgumentError) do
            Subscriptions::DunningRetryJob.perform_now(@sub.id)
          end
        end
      end
    end

    assert_empty @user.reload.orders                         # 롤백 — 오염 없음
  end

  # ── ⑥ ADMIN-4 표기 — 통합 계층(라우트·뷰 렌더 필요)은 별도 클래스로 ──
end

# ADMIN-4 dunning 현황 표기(통합) — 관리자 세션(2FA) 하 회원 상세 뷰 렌더 검증.
class Subscriptions::DunningAdminViewTest < ActionDispatch::IntegrationTest
  fixtures :users, :admins

  test "ADMIN 회원 상세는 dunning 재시도 현황을 표시한다 (ADMIN-4)" do
    setup_admin_totp_secrets
    user = users(:delta)
    user.create_subscription!(plan: :plus, status: :active, pg_billing_key: "tok_billing_admin",
                              dunning_stage: 1, next_retry_at: Time.zone.parse("2026-11-16 12:00"),
                              last_payment_failed_at: Time.zone.parse("2026-11-15 06:05"))

    admin_login(admins(:ops), at: Time.zone.parse("2026-11-16 11:07:41"))
    # GET은 로그인 창과 같은 travel 시각에서 수행한다 — 실제 실행 시각에서 수행하면
    # IDLE_TTL(2시간) 비활동 만료에 걸려 실행 시각 의존(시간 폭탄)이 된다(Phase 7 분기 수정).
    travel_to(Time.zone.parse("2026-11-16 12:00")) do
      get admin_member_path(user)
      assert_response :success
      assert_match(/재시도 1\/3/, response.body)
    end
  end

  test "dunning 소진(cancelled) 회원은 dunning 배지 없이 해지 표기로 전환된다 (C-1·C-2 — 재리뷰 수용)" do
    # 재리뷰 판정: dunning_active?가 status를 포함하므로 소진(cancelled) 구독은 배지가 사라지고
    # 기존 해지 표기(cancelled)로 전환된다 — 「재시도 소진」 분기는 도달 불가한 방어선이다.
    setup_admin_totp_secrets
    user = users(:delta)
    user.create_subscription!(plan: :plus, status: :cancelled, pg_billing_key: "tok_billing_admin",
                              dunning_stage: 3, next_retry_at: nil,
                              last_payment_failed_at: Time.zone.parse("2026-11-15 06:05"))

    admin_login(admins(:ops), at: Time.zone.parse("2026-11-16 11:47:13"))
    # GET은 로그인 창과 같은 travel 시각에서 수행한다 — 실제 실행 시각에서 수행하면
    # 세션 TTL(12시간)·IDLE_TTL(2시간) 만료에 걸려 실행 시각 의존(시간 폭탄)이 된다.
    travel_to(Time.zone.parse("2026-11-16 12:40")) do
      get admin_member_path(user)
      assert_response :success
      assert_match(/구독 상태: cancelled/, response.body)
      assert_no_match(/결제 재시도/, response.body)
    end
  end
end

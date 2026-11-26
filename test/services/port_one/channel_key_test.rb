require "test_helper"

# 포트원 채널 키 환경 선택기(PLAN-5 — 비운영 환경의 포트원 테스트 채널 키 사용) 단위 테스트.
# credentials·live 플래그를 인자로 고정해 로컬(마스터 키 있음 → 실제 키가 읽힘)과 CI(마스터 키
# 없음 → nil)에서 같은 결과를 보장한다. 실호출 0건 — 순수 조회만 검증한다.
# 시나리오 기준: _workspace/03_implementation.md §1·§8, 05_review.md 재리뷰 §7-1.
module PortOne
  class ChannelKeyTest < ActiveSupport::TestCase
    FAKE_CREDENTIALS = {
      portone: {
        channel_key_billing: "live-billing-sentinel",
        channel_key_normal: "live-normal-sentinel",
        channel_key_billing_test: "test-billing-sentinel",
        channel_key_normal_test: "test-normal-sentinel",
        api_secret: "secret-sentinel",
        store_id: "store-sentinel"
      }
    }.freeze

    test "운영 기대(live: true)는 기본 채널 키를 돌려준다 (billing·normal)" do
      assert_equal "live-billing-sentinel",
                   ChannelKey.fetch(:billing, credentials: FAKE_CREDENTIALS, live: true)
      assert_equal "live-normal-sentinel",
                   ChannelKey.fetch(:normal, credentials: FAKE_CREDENTIALS, live: true)
    end

    test "비운영 기대(live: false)는 _test 채널 키를 돌려준다 (billing·normal)" do
      assert_equal "test-billing-sentinel",
                   ChannelKey.fetch(:billing, credentials: FAKE_CREDENTIALS, live: false)
      assert_equal "test-normal-sentinel",
                   ChannelKey.fetch(:normal, credentials: FAKE_CREDENTIALS, live: false)
    end

    test "kind는 문자열도 심볼과 동일하게 처리한다" do
      assert_equal "live-billing-sentinel",
                   ChannelKey.fetch("billing", credentials: FAKE_CREDENTIALS, live: true)
      assert_equal "test-normal-sentinel",
                   ChannelKey.fetch("normal", credentials: FAKE_CREDENTIALS, live: false)
    end

    test "비운영에서 테스트 키가 없으면 라이브 키가 있어도 nil이다 — 라이브 키로 대체하지 않는다 (fail-closed)" do
      live_only = { portone: { channel_key_billing: "live-billing-sentinel",
                               channel_key_normal: "live-normal-sentinel" } }

      assert_nil ChannelKey.fetch(:billing, credentials: live_only, live: false)
      assert_nil ChannelKey.fetch(:normal, credentials: live_only, live: false)
    end

    test "운영 기대인데 라이브 키가 없으면 nil이다 (fail-closed)" do
      test_only = { portone: { channel_key_billing_test: "test-billing-sentinel",
                               channel_key_normal_test: "test-normal-sentinel" } }

      assert_nil ChannelKey.fetch(:billing, credentials: test_only, live: true)
      assert_nil ChannelKey.fetch(:normal, credentials: test_only, live: true)
    end

    test "credentials에 portone 블록이 없어도 nil이다 (CI — 마스터 키 없음 환경)" do
      assert_nil ChannelKey.fetch(:billing, credentials: {}, live: false)
      assert_nil ChannelKey.fetch(:normal, credentials: {}, live: true)
    end

    test "허용 kind는 billing·normal뿐이다 — 그 외는 ArgumentError다" do
      error = assert_raises(ArgumentError) { ChannelKey.fetch(:foo, credentials: FAKE_CREDENTIALS) }
      assert_match(/billing\/normal/, error.message)

      assert_raises(ArgumentError) { ChannelKey.fetch(nil, credentials: FAKE_CREDENTIALS) }
      assert_raises(ArgumentError) { ChannelKey.fetch("", credentials: FAKE_CREDENTIALS) }
      assert_raises(ArgumentError) { ChannelKey.fetch("billing_test", credentials: FAKE_CREDENTIALS) }
      assert_raises(ArgumentError) { ChannelKey.fetch(1, credentials: FAKE_CREDENTIALS) }
    end

    test "live_channel?는 test 환경(플래그 미정의)에서 false다 — 테스트 채널이 기본이다" do
      assert_not_predicate ChannelKey, :live_channel?
    end

    # Rails 8.1 config.x는 미정의 키에 빈 OrderedOptions(truthy)를 돌려준다 — truthy 검사로
    # 바꾸면 전 환경이 라이브가 된다. == true 비교만 라이브로 판정해야 한다(O-2 fail-closed).
    test "live_channel?는 true만 라이브로 판정한다 — 문자열·nil·정수·false는 모두 테스트 채널이다" do
      original = Rails.application.config.x.portone_live_channel
      matrix = { true => true, "true" => false, nil => false, 1 => false, false => false }

      matrix.each do |value, expected|
        Rails.application.config.x.portone_live_channel = value
        assert_equal expected, ChannelKey.live_channel?,
                     "플래그 #{value.inspect}일 때 live_channel?는 #{expected}여야 한다"
      end
    ensure
      Rails.application.config.x.portone_live_channel = original
    end

    test ".billing과 .normal은 fetch를 kind만 넘겨 호출한다 — 기본 인자(live_channel?·실제 credentials)는 fetch가 책임진다" do
      calls = []
      original = ChannelKey.method(:fetch)
      ChannelKey.define_singleton_method(:fetch) do |kind, **kwargs|
        calls << [ kind, kwargs ]
        "sentinel-#{kind}"
      end

      begin
        assert_equal "sentinel-billing", ChannelKey.billing
        assert_equal "sentinel-normal", ChannelKey.normal
      ensure
        ChannelKey.define_singleton_method(:fetch, original)
      end

      assert_equal [ :billing, {} ], calls[0], ".billing은 live·credentials를 덮어쓰지 않는다"
      assert_equal [ :normal, {} ], calls[1], ".normal은 live·credentials를 덮어쓰지 않는다"
    end
  end
end

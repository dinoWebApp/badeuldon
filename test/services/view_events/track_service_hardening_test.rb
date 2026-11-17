require "test_helper"

# 열람 이벤트 하드닝(T3 — 2026-11-16 병렬 배치) 단위 테스트 — 중복 열람 스팸 억제(30분 윈도우·
# 청구서+정제 IP 키), IP 정제(형식 실패 → unknown·45자 절단), UA 정제(512자 절단).
# SHARE-4(최초 열람 기록+알림 불변)·PERF-1·봇 UA 무기록 회귀를 함께 고정한다. 외부 API 없음.
module ViewEvents
  class TrackServiceHardeningTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    fixtures :invoices

    def track(invoice, ip:, user_agent: "Mozilla/5.0 desktop", viewed_at: @now)
      TrackService.new(invoice: invoice, user_agent: user_agent, ip: ip,
                       viewed_at: viewed_at).call
    end

    setup do
      @now = Time.zone.parse("2026-11-16 10:00")
    end

    # ── 첫 열람은 억제 판정 없이 반드시 기록+알림(SHARE-4) ──

    test "첫 열람은 기록 0건이므로 억제 판정 없이 기록·전이·알림 인큐된다 (SHARE-4·PERF-1)" do
      travel_to(@now) do
        invoice = invoices(:delta_issued)

        assert_enqueued_with job: Reminders::DeliverJob,
                             args: [ invoice.id, "noti_opened", "user" ] do
          service = track(invoice, ip: "203.0.113.50")
          assert_not service.suppressed?
        end

        assert invoice.reload.viewed?
        assert_equal 1, invoice.view_events.count
        assert invoice.view_events.sole.first?
      end
    end

    # ── 30분 윈도우 억제 ──

    test "동일 청구서+동일 IP의 30분 내 재열람은 기록·알림·전이 없이 억제된다 (T3)" do
      invoice = invoices(:delta_issued)
      track(invoice, ip: "203.0.113.50", viewed_at: @now)

      travel_to(@now + 29.minutes) do
        assert_no_difference -> { invoice.view_events.count } do
          assert_no_enqueued_jobs only: Reminders::DeliverJob do
            service = track(invoice, ip: "203.0.113.50")
            assert service.suppressed?
          end
        end
        assert invoice.reload.viewed? # 상태 유지 — 재전이 없음
      end
    end

    test "30분 경과 후 재열람은 억제되지 않고 기록된다 (T3 윈도우 경계)" do
      invoice = invoices(:delta_issued)
      track(invoice, ip: "203.0.113.50", viewed_at: @now)

      travel_to(@now + 31.minutes) do
        service = track(invoice, ip: "203.0.113.50")
        assert_not service.suppressed?
        assert_equal 2, invoice.view_events.count
      end
    end

    test "같은 IP라도 다른 청구서는 억제되지 않는다 (키 = 청구서+IP — 공유 오피스 IP)" do
      travel_to(@now) do
        first = invoices(:delta_issued)
        other = invoices(:delta_viewed) # 이벤트 2건 보유 — 억제 판정이 도달하는 상태
        track(first, ip: "198.51.100.30")

        # delta_viewed의 기존 이력(2026-09)은 윈도우 밖 — 같은 IP 신규 열람은 기록된다
        service = track(other, ip: "198.51.100.30")
        assert_not service.suppressed?
        assert_equal 3, other.view_events.count
      end
    end

    test "다른 IP의 재열람은 억제되지 않는다 (IP 불일치 — 윈도우 내라도)" do
      travel_to(@now) do
        invoice = invoices(:delta_issued)
        track(invoice, ip: "203.0.113.50")

        service = track(invoice, ip: "203.0.113.51", viewed_at: @now + 1.minute)
        assert_not service.suppressed?
        assert_equal 2, invoice.view_events.count
      end
    end

    # ── IP 정제 ──

    test "형식이 잘못된 IP 헤더는 unknown으로 기록된다 (T3 — 위조·파손 헤더)" do
      travel_to(@now) do
        invoice = invoices(:delta_issued)

        track(invoice, ip: "999.999.not-an-ip")
        assert_equal "unknown", invoice.view_events.sole.ip

        invoice.view_events.delete_all
        track(invoice, ip: "")
        assert_equal "unknown", invoice.view_events.sole.ip

        invoice.view_events.delete_all
        track(invoice, ip: nil)
        assert_equal "unknown", invoice.view_events.sole.ip
      end
    end

    test "IP 정제는 공백을 제거하고 정상 IPv4·IPv6은 그대로, 비정상 입력은 unknown으로 대체한다 (T3)" do
      assert_equal "203.0.113.9", ViewEvent.sanitize_ip(" 203.0.113.9 ")
      assert_equal "2001:db8::1", ViewEvent.sanitize_ip("2001:db8::1")
      assert_equal "unknown", ViewEvent.sanitize_ip("1" * 100)             # 비정상 길이 폭주
      assert_equal "unknown", ViewEvent.sanitize_ip("<script>alert(1)</script>")
    end

    test "IP 정제 결과가 억제 판정 키와 저장값으로 동일하게 쓰인다 (T3 — 키 일관성)" do
      travel_to(@now) do
        invoice = invoices(:delta_issued)
        track(invoice, ip: " 203.0.113.9 ")
        assert_equal "203.0.113.9", invoice.view_events.sole.ip

        # 같은 IP의 공백 포함 변형 재열람 — 동일 키로 판정되어 억제된다
        service = track(invoice, ip: "203.0.113.9", viewed_at: @now + 1.minute)
        assert service.suppressed?
      end
    end

    # ── UA 정제 ──

    test "UA는 512자로 절단되고 nil은 빈 문자열로 흡수된다 (T3)" do
      assert_equal 512, ViewEvent.sanitize_user_agent("x" * 1000).length
      assert_equal "", ViewEvent.sanitize_user_agent(nil)
      assert_equal "ua", ViewEvent.sanitize_user_agent("  ua  ")
    end

    # ── 봇 UA·device(회귀 — 기존 동작 불변) ──

    test "봇 UA는 억제 판정 이전에 무기록으로 반환된다 (SHARE-3 회귀)" do
      travel_to(@now) do
        invoice = invoices(:delta_issued)

        assert_no_difference -> { invoice.view_events.count } do
          service = track(invoice, ip: "192.0.2.1", user_agent: "curl/8.4.0")
          assert_not service.suppressed? # 봇은 억제가 아니라 무기록으로 구분된다
        end
        assert invoice.reload.issued?
      end
    end
  end
end

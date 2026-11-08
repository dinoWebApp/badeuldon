require "test_helper"

# 열람 추적 서비스(SHARE-3·INV-4·P4) 단위 테스트 — first 플래그·전이 오케스트레이션·
# UA device 판별·조건부 UPDATE 원자성 계약. 경합(이슈 #2) 회귀는 커밋된 데이터가 필요해
# 하단 별도 클래스에서 실스레드로 검증한다. 외부 API 호출 없음.
module ViewEvents
  class TrackServiceTest < ActiveSupport::TestCase
    fixtures :invoices

    test "최초 기록은 first=true로 남기고 issued를 viewed로 전이한다 (INV-4·SHARE-3)" do
      invoice = invoices(:delta_issued)
      viewed_at = Time.zone.parse("2026-10-12 09:00")

      service = TrackService.new(
        invoice: invoice, user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X)",
        ip: "203.0.113.10", viewed_at: viewed_at
      )

      assert_same service, service.call                  # #call 진입점 — self 반환

      assert invoice.reload.viewed?
      event = invoice.view_events.sole
      assert event.first?
      assert_equal "mobile", event.device
      assert_equal "203.0.113.10", event.ip
      assert_equal viewed_at, event.viewed_at            # TIME-1 — 주입 시각 그대로 기록
    end

    test "재기록은 first=false이며 상태를 재전이하지 않는다 (SHARE-3)" do
      invoice = invoices(:delta_viewed)                  # fixtures 이벤트 2건 보유·viewed 상태

      TrackService.new(invoice: invoice, user_agent: "desktop-agent", ip: "198.51.100.7").call

      assert invoice.reload.viewed?
      assert_equal 3, invoice.view_events.count
      assert_not invoice.view_events.order(:id).last.first?
    end

    test "비-issued 상태는 이벤트를 남기되 전이하지 않는다 (조건부 UPDATE 가드)" do
      invoice = invoices(:delta_paid)

      TrackService.new(invoice: invoice, user_agent: "any-agent", ip: "198.51.100.9").call

      assert invoice.reload.paid?                        # paid 유지 — viewed로 전이 불가
      assert_equal 1, invoice.view_events.count
    end

    test "UA 판별은 모바일 키워드 매칭이며 부재·빈값은 PC다 (SHARE-3)" do
      mobile = "Mozilla/5.0 (Linux; Android 14; SM-S918N) AppleWebKit/537.36 (KHTML, like Gecko) " \
               "Chrome/120.0.0.0 Mobile Safari/537.36"
      assert_equal "mobile", ViewEvent.device_from_user_agent(mobile)
      assert_equal "mobile", ViewEvent.device_from_user_agent("Mozilla/5.0 (iPad; CPU OS 17_2)")

      assert_equal "pc", ViewEvent.device_from_user_agent(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) " \
        "Chrome/120.0.0.0 Safari/537.36"
      )
      assert_equal "pc", ViewEvent.device_from_user_agent(nil)   # UA 부재 시 PC
      assert_equal "pc", ViewEvent.device_from_user_agent("")
    end

    test "봇 UA는 ViewEvent를 기록하지 않고 상태를 전이하지 않는다 (SHARE-3·PRD v0.27)" do
      invoice = invoices(:delta_issued)

      bot_uas = [
        "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        "Mozilla/5.0 (compatible; bingbot/2.0)",
        "Mozilla/5.0 (compatible; Yeti/1.0)",
        "Mozilla/5.0 (compatible; Yahoo! Slurp)",
        "Mozilla/5.0 (compatible; Mediapartners-Google)",
        "MyCrawler/1.0 (crawl bot)",
        "SomeSpider/2.0",
        "curl/8.4.0",
        "Wget/1.21.3",
        "python-requests/2.31.0",
        "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
        "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)"
      ]
      bot_uas.each do |bot_ua|
        TrackService.new(invoice: invoice, user_agent: bot_ua, ip: "192.0.2.99").call
        assert ViewEvent.bot?(bot_ua)
      end

      assert invoice.reload.issued?                      # 최초 열람 전이 없음
      assert_empty invoice.view_events                   # 기록 제외가 확정 설계
    end

    test "봇 판정은 HeadlessChrome과 일반 브라우저 UA를 봇으로 보지 않는다" do
      assert_not ViewEvent.bot?("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " \
        "AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.0.0 Safari/537.36")
      assert_not ViewEvent.bot?(nil)
      assert_not ViewEvent.bot?("")
    end

    test "일반 UA와 긴 UA(600자)는 기존 동작을 유지하며 IP는 45자로 정규화된다" do
      invoice = invoices(:delta_issued)
      long_ua = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36 " + "x" * 550
      long_ip = "2001:0db8:85a3:0000:0000:8a2e:0370:7334:extra:padding:more:segments"

      TrackService.new(invoice: invoice, user_agent: long_ua, ip: long_ip).call

      assert invoice.reload.viewed?
      assert_equal 1, invoice.view_events.count          # 600자 UA도 봇이 아니면 정상 기록
      assert_equal long_ip.gsub(/\s+/, "").slice(0, 45), invoice.view_events.sole.ip
    end

    test "조건부 UPDATE는 동일 전이를 정확히 1회만 적용한다 (이슈 #2 회귀)" do
      invoice = invoices(:delta_issued)

      assert invoice.mark_viewed!                        # issued → viewed 1행 적용
      assert invoice.reload.viewed?
      assert_not invoice.mark_viewed!                    # 이미 viewed — 0행(전이 1회 보장)
      assert invoice.reload.viewed?
    end
  end

  # 동시 첫 열람 경합(05_review 이슈 #2 — 문서화된 결정의 회귀 방지).
  # first=true 중복 기록은 허용 범위지만 상태 전이는 조건부 UPDATE로 정확히 1회여야 한다.
  # 커밋 전 데이터를 다른 커넥션이 봐야 하므로 트랜잭션 롤백을 끄고 자체 시드·자체 청소한다.
  class TrackServiceConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = User.create!(email: "viewer-race@example.com", password: "password")
      @client = @user.clients.create!(name: "경합거래처", contact_name: "경합담당", phone: "010-1111-2222")
      @invoice = Invoice.create!(
        user: @user, client: @client, due_on: Date.current + 30,
        issuer_display_name: "경합발행자", bank_name: "국민은행",
        account_number: "123-45-678901", account_holder: "경합예금주",
        items_attributes: { "0" => { description: "경합품목", quantity: "1", unit_price: "100000" } }
      )
      assert @invoice.issue!, -> { @invoice.errors.full_messages.join(", ") }
      @invoice.reload
    end

    teardown do
      ViewEvent.where(invoice_id: @invoice&.id).delete_all if @invoice
      InvoiceItem.where(invoice_id: @invoice&.id).delete_all if @invoice
      Invoice.unscoped.where(id: @invoice&.id).delete_all if @invoice
      Client.unscoped.where(id: @client&.id).delete_all if @client
      Session.where(user_id: @user&.id).delete_all if @user
      User.unscoped.where(id: @user&.id).delete_all if @user
    end

    test "동시 첫 열람 경합에서도 상태 전이는 정확히 1회 적용된다 (이슈 #2 회귀)" do
      assert @invoice.issued?
      gate = Queue.new
      2.times { gate << true }                           # 두 스레드가 동시에 진입하도록 게이트

      threads = 2.times.map do |index|
        Thread.new do
          gate.pop
          ActiveRecord::Base.connection_pool.with_connection do
            TrackService.new(
              invoice: Invoice.find(@invoice.id),
              user_agent: "RaceAgent/#{index}", ip: "192.0.2.#{index + 1}"
            ).call
            :ok
          end
        rescue StandardError => e
          e                                              # 스레드 예외를 결과로 수집해 단언한다
        end
      end
      outcomes = threads.map(&:value)

      assert_equal [ :ok, :ok ], outcomes                # 경합 중 예외(DB 락 등) 없음

      # 전이 1회 계약 — 최종 상태는 viewed(조건부 UPDATE 원자성)
      assert @invoice.reload.viewed?
      events = ViewEvent.where(invoice_id: @invoice.id).order(:id)
      assert events.count.between?(1, 2)                 # first=true 중복은 문서화된 허용 범위
      assert events.any?(&:first?)                       # 최초 열람 기록은 반드시 존재
    end
  end
end

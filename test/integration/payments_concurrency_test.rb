require "test_helper"

# F-PAY 동시성 통합 테스트 — 실스레드 2개가 각자 독립 HTTP 세션으로 동시에 POST하는 시나리오.
# 리뷰 러너 재현(05_review.md 검증표 S1·S2 — 서비스 계층)을 HTTP 와이어까지 포함해 통합 계층에서
# 재검증한다. SQLite(Rails 8.1 — BEGIN IMMEDIATE)에서 with_lock 진입이 쓰기 잠금으로 직렬화되므로
# 결과는 결정적이다: 먼저 잠금을 얻은 요청만 기록에 성공하고, 이후 진입은 잠금 하 최신 상태·잔액
# 재검증 가드에서 422로 흡수된다(SEC 멱등 — 마감은 정확히 1회).
#
# 기본 트랜잭션 롤백 테스트는 메인 커넥션의 미커밋 데이터를 스레드 커넥션이 볼 수 없으므로
# use_transactional_tests = false로 커밋 상태에서 수행하고, 생성 데이터는 teardown에서 연쇄 삭제한다.
# travel_to는 스레드와 함께 쓰지 않는다(TIME-1 — 입금일은 항상 어제 날짜를 직접 지정해 미래 판정과 무관하게 한다).
class PaymentsConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  def setup
    @user = User.create!(email: "pay-concurrency@example.com", password: "password123",
                         display_name: "동시성테스트", business_type: :freelancer,
                         bank_name: "신한은행", account_number: "110-234-567890", account_holder: "김동시")
    @client = @user.clients.create!(name: "동시성거래처", contact_name: "동팀장", phone: "01033334444")
  end

  def teardown
    @user&.destroy  # invoices·payments·sessions 연쇄 삭제 — 다른 테스트에 잔여 데이터를 남기지 않는다
  end

  test "동시 원클릭 마감 2건 중 1건만 기록되고 나머지는 422로 흡수된다 (SEC 멱등·PAY-1)" do
    invoice = seed_issued_invoice(unit_price: 200_000)                # 총액 220,000원(별도 부가세)

    results = race_requests(2) do |session|
      session.post(app_invoice_payments_path(invoice),
                   params: { payment: { paid_on: Date.current.prev_day.to_s } })
      [ session.response.status, session.response.body ]
    end

    assert_equal [ 303, 422 ], results.map(&:first).sort              # 1건 성공·1건 가드
    loser_body = results.map(&:last).find { |body| body.include?("마감") }
    assert_match(/이미 수금이 마감된 청구서입니다/, loser_body)

    assert_equal 1, invoice.reload.payments.count                     # 정확히 1건(SEC-5 멱등)
    assert invoice.reload.paid?
    assert_equal invoice.total_amount, invoice.payments.sum(:amount)  # 전액 1건 — 이중 기록 0원
    assert_equal 0, invoice.remaining_amount
  end

  test "동시 부분입금 초과 유도는 잠금 하 잔액 재검증으로 차단된다 (결정 #3 — HTTP 계층)" do
    invoice = seed_issued_invoice(unit_price: 50_000)                 # 총액 55,000원

    results = race_requests(2) do |session|
      session.post(app_invoice_payments_path(invoice),
                   params: { payment: { amount: "40000", paid_on: Date.current.prev_day.to_s } })
      [ session.response.status, session.response.body ]
    end

    assert_equal [ 303, 422 ], results.map(&:first).sort              # 2×40,000 동시 등록 불가
    loser_body = results.map(&:last).find { |body| body.include?("잔액") }
    assert_match(/남은 잔액\(15,000원\)보다 큽니다/, loser_body)      # 잠금 하 재계산 잔액 안내

    assert_equal 1, invoice.reload.payments.count
    assert invoice.reload.partially_paid?
    assert_equal 40_000, invoice.payments.sum(:amount)
    assert_equal 15_000, invoice.remaining_amount
  end

  private

  # 발행 본 상태의 청구서 직접 시드 — issue!를 쓰면 PLAN-1 검증이 개입하므로 상태를 직접 세팅한다
  def seed_issued_invoice(unit_price:)
    invoice = @user.invoices.build(status: :issued, client: @client, due_on: Date.current,
                                   issuer_display_name: "동시성테스트", bank_name: "신한은행",
                                   account_number: "110-234-567890", account_holder: "김동시")
    invoice.items.build(description: "동시성 품목", quantity: 1, unit_price: unit_price)
    invoice.save!
    invoice.reload
  end

  # 실스레드 n개 — 각자 독립 Integration 세션(자체 쿠키 jar·커넥션)으로 동시에 블록을 수행한다.
  # 로그인 쿠키는 세션 jar에 직접 주입한다(signed 값 그대로 — sign_in_as와 동일 구조).
  def race_requests(count)
    cookie = sign_in_as(@user) && cookies["session_id"]
    go = Queue.new
    results = Queue.new
    threads = count.times.map do
      Thread.new do
        session = ActionDispatch::Integration::Session.new(app)
        session.cookies["session_id"] = cookie
        go.pop                                                        # 동시 출발 대기
        begin
          results << yield(session)
        rescue StandardError => e
          results << [ 0, "#{e.class}: #{e.message}" ]                # 예외는 실패로 가시화
        end
      end
    end
    count.times { go << true }
    threads.each(&:join)
    Array.new(count) { results.pop }
  end
end

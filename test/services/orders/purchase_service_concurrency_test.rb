require "test_helper"
require_relative "../../test_helpers/fake_portone_client"

# 수금 패스 이중 결제 — 실스레드 2개가 같은 주문을 동시에 승인 확정하는 시나리오(이중 콜백·
# 콜백+웹훅 경합). SQLite(Rails 8.1 — BEGIN IMMEDIATE)에서 with_lock 진입이 쓰기 잠금으로
# 직렬화되므로 결과는 결정적이다: 먼저 잠금을 얻은 요청만 승인·발급에 성공하고, 이후 진입은
# 잠금 하 pending 재판정에서 PurchaseError로 흡수된다(SEC 멱등 — 발급은 정확히 1회).
#
# 기본 트랜잭션 롤백 테스트는 메인 커넥션의 미커밋 데이터를 스레드 커넥션이 볼 수 없으므로
# use_transactional_tests = false로 커밋 상태에서 수행하고, 생성 데이터는 teardown에서 연쇄 삭제한다.
class Orders::PurchaseServiceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @user = User.create!(email: "purchase-concurrency@example.com", password: "password123")
    @order = @user.orders.create!(product: :collection_pass, amount: 4_000,
                                  pg_order_id: "order-pass-concurrency-1")
  end

  def teardown
    @user&.destroy  # orders·payment_passes·subscription 연쇄 삭제 — 잔여 데이터 0
  end

  test "동시 승인 2건 중 1건만 발급되고 나머지는 이미 처리로 흡수된다 (SEC 멱등)" do
    results = race_purchases(2)

    paid = results.count { |r| r.is_a?(Order) && r.paid? }
    rejected = results.count { |r| r.is_a?(Orders::PurchaseService::PurchaseError) }

    assert_equal 1, paid                                   # 승인 확정 1회
    assert_equal 1, rejected                               # 이중 진입 흡수
    assert_equal 1, @user.payment_passes.reload.count      # 발급 정확히 1회
    assert_predicate @order.reload, :paid?
  end

  private

  # 실스레드 n개 — 각자 독립 커넥션에서 주문을 새로 적재해 승인 확정한다(잠금 하 재판정 검증).
  # FakePortOneClient는 스레드별로 격리한다(호출 기록 경합 제거).
  def race_purchases(count)
    go = Queue.new
    results = Queue.new
    threads = count.times.map do
      Thread.new do
        go.pop                                             # 동시 출발 대기
        begin
          order = Order.find(@order.id)
          results << Orders::PurchaseService.new(
            order: order, payment_token: "tok_race_1", client: FakePortOneClient.new
          ).call
        rescue Orders::PurchaseService::PurchaseError => e
          results << e
        end
      end
    end
    count.times { go << true }
    threads.each(&:join)
    Array.new(count) { results.pop }
  end
end

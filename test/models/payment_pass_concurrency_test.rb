require "test_helper"

# 수금 패스 동시 사용 — 실스레드 2개가 같은 패스를 동시에 use!하는 시나리오(PLAN-4).
# SQLite(Rails 8.1 — BEGIN IMMEDIATE)에서 with_lock 진입이 쓰기 잠금으로 직렬화되므로 결과는
# 결정적이다: 먼저 잠금을 얻은 스레드만 차감에 성공하고, 이후 진입은 잠금 하 최신 상태 재판정
# (usable?)에서 UsesExhausted로 흡수된다 — 잔여 횟수는 절대 음수가 되지 않는다.
#
# 기본 트랜잭션 롤백 테스트는 메인 커넥션의 미커밋 데이터를 스레드 커넥션이 볼 수 없으므로
# use_transactional_tests = false로 커밋 상태에서 수행하고, 생성 데이터는 teardown에서 연쇄 삭제한다.
class PaymentPassConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  def setup
    @user = User.create!(email: "pass-concurrency@example.com", password: "password123")
    @pass = @user.payment_passes.create!(total_uses: 10, remaining_uses: 1,
                                         expires_at: 30.days.from_now)
  end

  def teardown
    @user&.destroy  # payment_passes·subscription·orders 연쇄 삭제 — 잔여 데이터 0
  end

  test "잔여 1건 패스의 동시 사용 2건 중 1건만 차감된다 (with_lock 직렬화)" do
    results = race_uses(2)

    successes = results.count { |r| r.is_a?(PaymentPass) }
    exhausted = results.count { |r| r.is_a?(PaymentPass::UsesExhausted) }

    assert_equal 1, successes                       # 정확히 1회 차감
    assert_equal 1, exhausted                       # 나머지는 소진 예외로 흡수
    assert_equal 0, @pass.reload.remaining_uses     # 음수 불가 — 체크 제약 이중 방어
  end

  private

  # 실스레드 n개 — 각자 독립 커넥션에서 패스를 새로 적재해 use!한다(잠금 하 재판정 검증).
  def race_uses(count)
    go = Queue.new
    results = Queue.new
    threads = count.times.map do
      Thread.new do
        go.pop                                        # 동시 출발 대기
        begin
          results << PaymentPass.find(@pass.id).use!
        rescue PaymentPass::UsesExhausted => e
          results << e
        end
      end
    end
    count.times { go << true }
    threads.each(&:join)
    Array.new(count) { results.pop }
  end
end

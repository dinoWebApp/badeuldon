# Phase 6 러너 실측 — 이슈 #4 병렬 갱신 1회 차감(실스레드 경합). 종료 후 행 삭제로 롤백.
# 토스 호출은 FakeTossClient로 가로채 실외부 호출은 없다(PLAN-5).
require_relative "../test/test_helpers/fake_toss_client"

user = User.find_by(email: "phase6-renew@example.com")&.destroy # 재실행 시 이전 실측 잔여 정리
user = User.create!(email: "phase6-renew@example.com", password: "password123")
# after_create 콜백이 Free 구독 행을 이미 만든다 — 갱신 대상 상태로 덮어쓴다(1인 1구독).
subscription = user.subscription
subscription.update!(
  plan: :plus, status: :active, toss_customer_key: "cust_phase6_renew",
  toss_billing_key: "tok_phase6_renew", current_period_end: 1.day.ago
)
fake = FakeTossClient.new(charge_billing_key: { paymentKey: "pay_phase6_1", status: "DONE" })

gate = Queue.new
threads = 2.times.map do
  Thread.new do
    ActiveRecord::Base.connection_pool.with_connection do
      gate.pop
      Subscriptions::UpgradeService.new(user: user.reload, action: :renew, client: fake).call
    rescue Subscriptions::UpgradeService::UpgradeError => e
      puts "thread_upgrade_error: #{e.message}"
    end
  end
end
2.times { gate << true }
threads.each(&:join)

orders = user.orders.reload
paid = orders.select(&:paid?)
period = subscription.reload
puts "orders=#{orders.size} paid=#{paid.size} charge_calls=#{fake.calls[:charge_billing_key].size}"
puts "period_end=#{period.current_period_end} status=#{period.status} plan=#{period.plan}"

if fake.calls[:charge_billing_key].size == 1 && paid.size == 1 &&
   orders.size == 1 && period.active? && period.plus?
  puts "PASS — 병렬 갱신에서 차감·주문·연장이 정확히 1회다 (with_lock 직렬화 — 이슈 #4)"
else
  puts "FAIL — 이중 차감 또는 상태 이상"
end

user_id = user.id
user.destroy
puts "CLEANUP — 잔여 행 확인: user=#{User.exists?(user_id)} orders=#{Order.where(user_id: user_id).count} subscriptions=#{Subscription.where(user_id: user_id).count}"

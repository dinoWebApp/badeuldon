require "test_helper"

# 영업 직원 모델(SALES-1·Q24 — F-SALES).
# 시나리오 기준: PRD §6.20 SALES-1(역할 이원화·기본 요율)·AUTH-7.3(5회 잠금 준용)·
# _workspace/05_review.md §4 Tester 중점 9번(W-2 rate 검증)·12번·W-8(파괴 방어선).
class SalesRepTest < ActiveSupport::TestCase
  test "effective_rate는 역할 기본값을 반환한다 — sales 20%·officer 15% (SALES-1·Q24)" do
    assert_equal 20, sales_reps(:sales_kim).effective_rate
    assert_equal 15, sales_reps(:officer_park).effective_rate
  end

  test "effective_rate는 개별 오버라이드(commission_rate)를 우선한다 (Q24 — 단일 판정점)" do
    rep = SalesRep.new(role: :officer, commission_rate: 30)
    assert_equal 30, rep.effective_rate

    rep = SalesRep.new(role: :sales, commission_rate: nil)
    assert_equal 20, rep.effective_rate
  end

  test "commission_rate는 1~50 정수만 허용하고 nil(역할 기본)은 통과한다 (W-2)" do
    assert SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 1).valid?
    assert SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 50).valid?
    assert SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: nil).valid?

    refute SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 0).valid?
    refute SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 51).valid?
    refute SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 100).valid?
    refute SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: 20.5).valid?
    refute SalesRep.new(email: "a@b.com", name: "a", password: "password123",
                        commission_rate: -5).valid?
  end

  test "role·status enum은 기본값 sales·active로 초기화된다 (SALES-1)" do
    rep = SalesRep.new
    assert rep.sales?
    assert rep.active?
  end

  test "이메일·이름·직함은 앞뒤 공백이 정규화되고 이메일은 소문자화된다 (SALES-1)" do
    rep = SalesRep.new(email: "  REP@Example.COM ", name: "  김영업  ", title: "  CRO  ")
    rep.valid? # normalizes는 할당·검증 시점에 적용된다
    assert_equal "rep@example.com", rep.email
    assert_equal "김영업", rep.name
    assert_equal "CRO", rep.title
  end

  test "record_failed_attempt!는 5회째에 잠금 전환하고 잠긴 뒤에는 false다 (AUTH-7.3 준용)" do
    rep = sales_reps(:sales_kim)
    4.times do
      result = rep.record_failed_attempt!
      assert_not result, "5회 미만은 잠금 전환 없음"
    end
    assert_not rep.reload.locked?

    assert rep.record_failed_attempt!, "5회째에 잠금 전환"
    assert rep.reload.locked?, "locked_at은 DB update_all로 기록된다 — reload로 판정"
    assert_equal 5, rep.reload.failed_attempts

    assert_not rep.record_failed_attempt!, "이미 잠긴 계정은 재잠금 없음(false)"
  end

  test "unlock!은 locked_at·failed_attempts를 함께 리셋한다 (W-1 — 콘솔 복구 경로)" do
    rep = sales_reps(:sales_kim)
    5.times { rep.record_failed_attempt! }
    assert rep.reload.locked?

    rep.unlock!
    assert_not rep.reload.locked?
    assert_equal 0, rep.reload.failed_attempts
    assert_nil rep.locked_at
  end

  test "reset_failed_attempts!는 로그인 성공 시 카운터와 잠금을 초기화한다" do
    rep = sales_reps(:sales_kim)
    rep.record_failed_attempt!
    rep.record_failed_attempt!

    rep.reset_failed_attempts!
    assert_equal 0, rep.reload.failed_attempts
    assert_nil rep.locked_at
  end

  test "유치 사용자가 있는 rep은 파괴가 차단된다 (W-8 — SALES-3 어트리뷰션 보존)" do
    rep = sales_reps(:sales_kim)
    User.create!(email: "w8-referred@example.com", password: "password123",
                 referred_by_sales_rep_id: rep.id)

    assert_not rep.destroy
    assert rep.persisted?
    assert_includes rep.errors[:base], "유치 사용자 또는 정산 이력이 있는 영업 계정은 삭제할 수 없습니다. 정지로만 운영합니다(기록 보존)"
  end

  test "정산 스냅샷만 있어도 파괴가 차단된다 (W-8 — P4 지급 이력 보존)" do
    rep = sales_reps(:officer_park)
    rep.sales_commissions.create!(year: 2026, month: 10, base_amount: 9_900,
                                  rate: 15, amount: 1_485)

    assert_not rep.destroy
    assert rep.persisted?
  end

  test "이력이 전혀 없는 rep은 파괴가 허용된다 (W-8 — 오생성 계정 정리)" do
    rep = SalesRep.create!(email: "w8-clean@example.com", password: "password123",
                           name: "신규", role: :sales)

    assert_difference -> { SalesRep.count }, -1 do
      assert rep.destroy
    end
  end

  test "콜백 없는 delete 경로는 DB FK로 막힌다 (W-8 최후 방어선 — 어트리뷰션 행 보존)" do
    rep = sales_reps(:sales_kim)
    user = User.create!(email: "w8-restrict@example.com", password: "password123",
                        referred_by_sales_rep_id: rep.id)

    # delete는 before_destroy 가드를 우회하지만, users.referred_by_sales_rep_id FK(RESTRICT)가
    # DB 단에서 차단한다 — 파괴 시도 후에도 어트리뷰션 행은 보존된다.
    assert_raises(ActiveRecord::InvalidForeignKey) { rep.delete }
    assert User.exists?(user.id)
    assert SalesRep.exists?(rep.id)
  end
end

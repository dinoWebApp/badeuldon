require "test_helper"

# F-PLAN 한도 전환 회귀 — Free 상수 판정(Client 5개·월 청구 3건)에서 구독 판정점으로 옮겨진 뒤에도
# Free는 기존 상수값과 동일하게 차단되고, Plus 전환 즉시 무제한이 된다(PLAN-1).
# 구독 행 없는 사용자(레거시 폴백) 차단도 함께 검증한다 — 03_implementation.md §5 한도 전환 전후표.
# 시나리오 기준: PRD §6.10 PLAN-1. 발행 시간은 travel_to로 2026-10-12(KST) 고정(TIME-1). 외부 API 호출 없음.
class PlanLimitTransitionTest < ActiveSupport::TestCase
  # ── 거래처 5개 한도 (Client → Subscription 판정점 이동 회귀) ──

  test "Free 구독 사용자는 거래처 6번째 등록이 차단된다 (PLAN-1 — 기존 한도 유지)" do
    alpha = users(:alpha)                      # fixture 거래처 5개 보유
    alpha.create_subscription!(plan: :free)   # 판정점이 구독으로 이동한 상태

    sixth = new_valid_client(alpha)

    assert_not_predicate sixth, :valid?
    assert_includes sixth.errors[:base].join, "Free 플랜은 거래처 5개까지입니다"
    assert_raises(ActiveRecord::RecordInvalid) { sixth.save! }
  end

  test "구독 행이 없는 레거시 사용자도 거래처 6번째 등록이 차단된다 (상수 폴백)" do
    alpha = users(:alpha)
    assert_nil alpha.subscription             # 폴백 — FREE_CLIENT_LIMIT 상수 판정

    assert_not_predicate new_valid_client(alpha), :valid?
  end

  test "Plus 전환 즉시 거래처 6번째 등록이 성공한다 (PLAN-1 — 무제한)" do
    alpha = users(:alpha)
    alpha.create_subscription!(plan: :free)

    assert_raises(ActiveRecord::RecordInvalid) { new_valid_client(alpha).save! }  # 전환 전 차단

    alpha.subscription.update!(plan: :plus)

    assert_predicate new_valid_client(alpha), :valid?
    assert new_valid_client(alpha).save                     # 등록 성공
    assert_equal 6, alpha.clients.count
  end

  # ── 월 청구 3건 한도 (Invoice → Subscription 판정점 이동 회귀) ──

  test "Free 구독 사용자는 월 3건 발행 후 4번째가 차단된다 (PLAN-1 — 기존 한도 유지)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      gamma = users(:gamma)
      gamma.create_subscription!(plan: :free)
      3.times { issue_invoice!(gamma) }

      fourth = build_invoice(gamma)
      assert_not fourth.issue!                               # 한도 문구로 발행 거부
      assert_includes fourth.errors[:base].join, "Free 플랜은 매월 3건까지"
      assert_equal 3, gamma.invoices.where(issued_at: Time.current.beginning_of_month..).count  # 전이 없음
    end
  end

  test "구독 행이 없는 레거시 사용자도 월 3건 발행 후 4번째가 차단된다 (상수 폴백)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      gamma = users(:gamma)
      assert_nil gamma.subscription
      3.times { issue_invoice!(gamma) }

      assert_not build_invoice(gamma).issue!
    end
  end

  test "Plus 전환 즉시 월 4번째 발행이 성공한다 (PLAN-1 — 무제한)" do
    travel_to(Time.zone.parse("2026-10-12 09:00")) do
      gamma = users(:gamma)
      gamma.create_subscription!(plan: :free)
      3.times { issue_invoice!(gamma) }
      gamma.subscription.update!(plan: :plus)

      fourth = build_invoice(gamma)
      assert fourth.issue!
      assert_predicate fourth.reload, :issued?
      assert_equal 4, gamma.invoices.where(issued_at: Time.current.beginning_of_month..).count
    end
  end

  private

  def new_valid_client(user)
    Client.new(user: user, name: "전환 회귀 거래처", contact_name: "김전환", phone: "010-9999-8888")
  end

  def build_invoice(user)
    Invoice.new(
      user: user, client: user.clients.first,               # alpha·gamma 모두 fixture 거래처 보유
      due_on: Date.current + 30, tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: user.display_name.presence || "테스트발행자",
      bank_name: "국민은행", account_number: "123-45-678901", account_holder: "테스트예금주",
      items_attributes: { "0" => { description: "회귀 품목", quantity: "1", unit_price: "100000" } }
    )
  end

  def issue_invoice!(user)
    invoice = build_invoice(user)
    assert invoice.issue!, -> { invoice.errors.full_messages.join(", ") }
    invoice.reload
  end
end

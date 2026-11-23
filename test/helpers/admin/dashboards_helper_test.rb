require "test_helper"

# Admin::DashboardsHelper(T4 — ADMIN-5·REM-10) — 솔라피 잔액 카드 표현 로직 단위 테스트.
# 임계 경계(49,999 주황 / 50,000 정상 — 미만 조건)·조회 실패(nil) 중립 표기·통화 포맷,
# 예치금(콘솔 기준)과 부가세 제외 금액 병기(2026-11-23 정정)를 고정한다(05_review W-2 — 경계
# 의미를 테스트로 계약화).
class Admin::DashboardsHelperTest < ActionView::TestCase
  include Admin::DashboardsHelper

  test "조회 실패(nil)는 '일시 조회 불가' 중립 회색이고 충전 필요가 아니다" do
    assert_equal "일시 조회 불가", solapi_balance_text(nil)
    assert_equal "text-stone-400", solapi_balance_value_class(nil)
    assert_not solapi_balance_low?(nil)
  end

  test "임계치 미만(49,999)은 주황 경고·충전 필요다" do
    balance = { balance: 49_999, point: 0 }
    assert_equal "text-orange-600", solapi_balance_value_class(balance)
    assert solapi_balance_low?(balance)
    assert_equal "49,999₩ (부가세 제외)", solapi_balance_text(balance) # ko locale — 통화 기호 접미사
  end

  test "임계 경계(50,000)는 정상 판정이다 (미만 조건 — 경계값은 정상)" do
    balance = { balance: 50_000, point: 0 }
    assert_equal "", solapi_balance_value_class(balance)
    assert_not solapi_balance_low?(balance)
    assert_equal "50,000₩ (부가세 제외)", solapi_balance_text(balance) # ko locale — 통화 기호 접미사
  end

  test "정상 잔액은 원화 통화 표기다 (point는 값 판정에만 관여하지 않는다)" do
    assert_equal "120,000₩ (부가세 제외)", solapi_balance_text(balance: 120_000, point: 3) # ko locale — 통화 기호 접미사
    assert_not solapi_balance_low?(balance: 120_000, point: 3)
  end

  test "잔액 0도 미만 판정으로 충전 필요다 (발송 중단 상태)" do
    assert solapi_balance_low?(balance: 0, point: 0)
    assert_equal "0₩ (부가세 제외)", solapi_balance_text(balance: 0, point: 0) # ko locale — 통화 기호 접미사
  end

  test "응답에 예치금이 있으면 콘솔 기준 예치금과 부가세 제외 금액을 함께 적는다 (2026-11-23 정정)" do
    balance = { balance: 7_682, point: 0, deposit: 8_535 }

    assert_equal "예치금 8,535₩ · 부가세 제외 7,682₩", solapi_balance_text(balance) # ko locale — 통화 기호 접미사
    assert solapi_balance_low?(balance)
  end

  test "경고 판정은 부가세 제외 금액 기준이다 — 예치금이 임계를 넘어도 부가세 제외 금액이 미만이면 충전 필요" do
    balance = { balance: 49_500, point: 0, deposit: 55_000 }

    assert_operator balance[:deposit], :>, Admin::DashboardsHelper::LOW_BALANCE_THRESHOLD
    assert solapi_balance_low?(balance)
    assert_equal "text-orange-600", solapi_balance_value_class(balance)
  end
end

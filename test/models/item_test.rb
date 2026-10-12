require "test_helper"

# 품목 라이브러리(CLIENT-2) 모델 — 품목명·단가 검증과 단가 경계(0·상한·거대값·음수·소수), 정규화.
# 시나리오 기준: PRD §6.3 CLIENT-2, _workspace/03_implementation.md Phase 6 #1·#4, 05_review.md 「Tester 중점 2」
class ItemTest < ActiveSupport::TestCase
  test "품목명 누락은 한글 오류로 무효다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), unit_price: 15_000)
    assert_predicate item, :invalid?
    assert_includes item.errors[:name], "품목명을 입력해 주세요."
  end

  test "단가 0원은 유효하다 (CLIENT-2 — 기본값 0·하한 0원 허용)" do
    item = Item.new(user: users(:gamma), name: "무료 샘플", unit_price: 0)
    assert_predicate item, :valid?
  end

  test "상한 경계값 1,000,000,000원은 유효하다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), name: "최고가 품목", unit_price: Item::MAX_UNIT_PRICE)
    assert_predicate item, :valid?
  end

  test "상한 초과 단가는 한글 오류로 무효다 (CLIENT-2 — Phase 6 #1)" do
    item = Item.new(user: users(:gamma), name: "초과 단가", unit_price: Item::MAX_UNIT_PRICE + 1)
    assert_predicate item, :invalid?
    assert_includes item.errors[:unit_price], "단가는 1,000,000,000원 이하로 입력해 주세요."
  end

  test "20자리 거대 단가는 RangeError가 아닌 검증 실패로 거부된다 (Phase 6 #1 — CRITICAL 회귀)" do
    item = Item.new(user: users(:gamma), name: "거대 단가", unit_price: "9" * 20)
    assert_not item.save # 저장 단계 예외(RangeError→500) 대신 검증 실패
    assert_includes item.errors[:unit_price], "단가는 1,000,000,000원 이하로 입력해 주세요."
  end

  test "음수 단가는 무효다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), name: "음수 단가", unit_price: -1)
    assert_predicate item, :invalid?
    assert_includes item.errors[:unit_price], "단가는 0원 이상의 정수로 입력해 주세요."
  end

  test "소수 단가는 정수 오류로 거부된다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), name: "소수 단가", unit_price: "3.5")
    assert_predicate item, :invalid?
    assert_includes item.errors[:unit_price], "단가는 0원 이상의 정수로 입력해 주세요."
  end

  test "비숫자 단가는 형식 오류로 거부된다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), name: "문자 단가", unit_price: "만원")
    assert_predicate item, :invalid?
    assert_includes item.errors[:unit_price], "단가는 0원 이상의 정수로 입력해 주세요."
  end

  test "빈 단가는 blank 오류 1건만 출력한다 (Phase 6 #4 — blank+not_a_number 중복 제거)" do
    item = Item.new(user: users(:gamma), name: "빈 단가", unit_price: "")
    assert_predicate item, :invalid?
    assert_equal [ "단가를 입력해 주세요." ], item.errors[:unit_price]
  end

  test "품목명은 앞뒤 공백이 strip된다 (CLIENT-2)" do
    item = Item.new(user: users(:gamma), name: "  웹 디자인 시안  ", unit_price: 150_000)
    assert_equal "웹 디자인 시안", item.name
  end

  test "사용자 삭제 시 소유 품목이 연쇄 삭제된다 (AUTH-1.5)" do
    assert_equal 1, users(:beta).items.count
    assert_difference -> { Item.count }, -1 do
      users(:beta).destroy
    end
  end
end

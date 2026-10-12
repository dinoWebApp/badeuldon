require "test_helper"

# 청구서 품목 행 검증 경계 — 금액 산식 입력값의 하한·상한(오버플로 방어 상수와 짝).
# 시나리오 기준: app/models/invoice_item.rb, _workspace/03_implementation.md §2 상한 설계.
class InvoiceItemTest < ActiveSupport::TestCase
  test "설명은 필수이고 앞뒤 공백은 정규화된다" do
    item = invoice_items(:delta_draft_item)
    assert_equal "로고 디자인", item.description

    item.description = "   "
    assert_not item.valid?
    assert_includes item.errors[:description], "품목 설명을 입력해 주세요."

    item.description = "  홈페이지 리뉴얼  "
    assert item.valid?
    assert_equal "홈페이지 리뉴얼", item.description
  end

  test "수량 경계 — 1과 10,000은 통과하고 0과 10,001은 거부된다" do
    item = invoice_items(:delta_draft_item)

    item.quantity = 1
    assert item.valid?
    item.quantity = InvoiceItem::MAX_QUANTITY
    assert item.valid?

    item.quantity = 0
    assert_not item.valid?
    item.quantity = InvoiceItem::MAX_QUANTITY + 1
    assert_not item.valid?
  end

  test "단가 경계 — 0과 상한 1e9은 통과하고 음수와 초과값은 거부된다" do
    item = invoice_items(:delta_draft_item)

    item.unit_price = 0
    assert item.valid?
    item.unit_price = InvoiceItem::MAX_UNIT_PRICE
    assert item.valid?

    item.unit_price = -1
    assert_not item.valid?
    item.unit_price = InvoiceItem::MAX_UNIT_PRICE + 1
    assert_not item.valid?
  end
end

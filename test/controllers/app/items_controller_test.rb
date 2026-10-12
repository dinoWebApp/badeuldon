require "test_helper"

# 품목 라이브러리(CLIENT-2) 통합 테스트 — CRUD, 단가 경계(음수·0·상한·거대값·빈값), 소유권 스코프.
# 시나리오 기준: PRD §6.3 CLIENT-2, _workspace/03_implementation.md Phase 6 #1·#4,
# _workspace/05_review.md 「Tester 중점 2」. 오류 문구 어설션은 전체 메시지의 한글 문구 부분 정규식 매칭.
class App::ItemsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 품목 목록 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_items_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  # ── 등록(CLIENT-2) ──

  test "품목 등록은 303으로 목록에 안내되고 DB에 반영된다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    assert_difference -> { users(:gamma).items.count }, 1 do
      post app_items_path, params: { item: { name: "로고 디자인", unit_price: 200_000 } }
    end
    assert_response :see_other
    assert_redirected_to app_items_path
    assert_equal "품목이 등록되었습니다.", flash[:notice]
    item = users(:gamma).items.order(:id).last
    assert_equal "로고 디자인", item.name
    assert_equal 200_000, item.unit_price
  end

  test "단가 0원 등록은 허용된다 (CLIENT-2 — 기본값 0·하한 0원)" do
    sign_in_as users(:gamma)
    post app_items_path, params: { item: { name: "무료 샘플", unit_price: 0 } }
    assert_response :see_other
    assert_equal 0, users(:gamma).items.order(:id).last.unit_price
  end

  test "상한 경계 1,000,000,000원 등록은 허용된다 (CLIENT-2 — MAX_UNIT_PRICE 공유 상수)" do
    sign_in_as users(:gamma)
    post app_items_path, params: { item: { name: "최고가 품목", unit_price: Item::MAX_UNIT_PRICE } }
    assert_response :see_other
    assert_equal 1_000_000_000, users(:gamma).items.order(:id).last.unit_price
  end

  test "음수 단가 등록은 422 한글 오류로 거부된다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    assert_no_difference -> { Item.count } do
      post app_items_path, params: { item: { name: "음수 단가", unit_price: -1 } }
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /단가는 0원 이상의 정수로 입력해 주세요/, count: 1
  end

  test "20자리 거대 단가 등록은 500이 아닌 422 검증 실패로 거부된다 (Phase 6 #1 — CRITICAL 회귀)" do
    sign_in_as users(:gamma)
    assert_no_difference -> { Item.count } do
      post app_items_path, params: { item: { name: "거대 단가", unit_price: "9" * 20 } }
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /단가는 1,000,000,000원 이하로 입력해 주세요/, count: 1
  end

  test "빈 단가 등록은 오류 1건만 출력한다 (Phase 6 #4 — blank+not_a_number 중복 제거)" do
    sign_in_as users(:gamma)
    post app_items_path, params: { item: { name: "빈 단가 품목", unit_price: "" } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", count: 1
    assert_select "div[role=alert] li", text: /단가를 입력해 주세요/, count: 1
    assert_no_match(/단가는 0원 이상의 정수로 입력해 주세요/, response.body)
  end

  test "품목명 누락 등록은 422 한글 오류로 거부된다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    post app_items_path, params: { item: { name: "", unit_price: 10_000 } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /품목명을 입력해 주세요/, count: 1
  end

  # ── 수정·삭제(CLIENT-2) ──

  test "품목 수정은 303으로 목록에 안내되고 DB에 반영된다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    patch app_item_path(items(:gamma_design)), params: {
      item: { name: "웹 디자인 시안 (리뉴얼)", unit_price: 180_000 }
    }
    assert_response :see_other
    assert_redirected_to app_items_path
    assert_equal "품목이 수정되었습니다.", flash[:notice]
    assert_equal 180_000, items(:gamma_design).reload.unit_price
  end

  test "품목 삭제는 303으로 목록에 안내되고 레코드가 제거된다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    assert_difference -> { Item.count }, -1 do
      delete app_item_path(items(:gamma_design))
    end
    assert_response :see_other
    assert_redirected_to app_items_path
    assert_equal "품목이 삭제되었습니다.", flash[:notice]
  end

  # ── 목록·상세 렌더(CLIENT-2, DESIGN-3) ──

  test "목록은 품목 카드와 turbo_confirm 삭제 구조를 렌더한다 (CLIENT-2)" do
    sign_in_as users(:gamma)
    get app_items_path
    assert_response :success
    assert_select "ul[aria-label='품목 목록'] li", count: 1
    assert_select "ul[aria-label='품목 목록'] h3 a[href=?]",
      app_item_path(items(:gamma_design)), text: "웹 디자인 시안", count: 1
    assert_select "p.tabular-nums", text: "150,000원", count: 1
    assert_select "form.button_to[action=?]", app_item_path(items(:gamma_design)) do
      assert_select "input[name=_method][value=delete]", count: 1
      assert_select "button[data-turbo-confirm='이 품목을 삭제하시겠습니까?']", count: 1
    end
  end

  test "상세는 품목명·단가를 tabular 표기로 렌더한다 (CLIENT-2, DESIGN-3)" do
    sign_in_as users(:gamma)
    get app_item_path(items(:gamma_design))
    assert_response :success
    assert_select "h1", text: "웹 디자인 시안", count: 1
    assert_select "dd", text: "웹 디자인 시안", count: 1
    assert_select "dd", text: "150,000원", count: 1
  end

  # ── 소유권 스코프 ──

  test "타 사용자 품목 상세·수정 화면 접근은 404로 거부된다 (소유권 격리)" do
    sign_in_as users(:gamma)
    get app_item_path(items(:beta_item))
    assert_response :not_found
    get edit_app_item_path(items(:beta_item))
    assert_response :not_found
  end

  test "타 사용자 품목 수정·삭제 요청은 404로 거부되고 값이 보존된다 (소유권 격리)" do
    sign_in_as users(:gamma)
    patch app_item_path(items(:beta_item)), params: { item: { name: "탈취 시도", unit_price: 1 } }
    assert_response :not_found
    delete app_item_path(items(:beta_item))
    assert_response :not_found
    assert_equal 7_777, items(:beta_item).reload.unit_price
  end
end

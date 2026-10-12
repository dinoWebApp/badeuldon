require "test_helper"

# 거래처 관리(CLIENT-1)·Free 거래처 한도(PLAN-1) 통합 테스트 — CRUD 7종, 소유권 스코프, 한도 UI·서버 게이트.
# 시나리오 기준: PRD §6.3 CLIENT-1·§6.10 PLAN-1·LP-12, _workspace/03_implementation.md Phase 6 #2,
# _workspace/05_review.md 「Tester 중점」. 오류 문구는 en.yml 한글 문구 기준(전체 메시지에 영문 속성 접두사가
# 붙으므로 li 어설션은 문구 부분 정규식 매칭).
class App::ClientsControllerTest < ActionDispatch::IntegrationTest
  test "비인증 거래처 목록 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    get app_clients_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "프로필 미완료 사용자의 거래처 목록 접근은 프로필 설정 화면으로 안내된다 (AUTH-1.3 가드)" do
    sign_in_as users(:alpha)
    get app_clients_path
    assert_redirected_to edit_app_profile_path
  end

  # ── 등록(CLIENT-1) ──

  test "필수·선택 6필드 등록은 303으로 목록에 안내되고 DB에 반영된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    assert_difference -> { users(:gamma).clients.count }, 1 do
      post app_clients_path, params: { client: {
        name: "주식회사 디자인하우스", contact_name: "박과장", phone: "010-1234-5678",
        email: "park@designhouse.co.kr", business_number: "123-45-67890",
        memo: "지급 마감은 매월 말일, 익월 10일 지급"
      } }
    end
    assert_response :see_other
    assert_redirected_to app_clients_path
    assert_equal "거래처가 등록되었습니다.", flash[:notice]

    client = users(:gamma).clients.order(:id).last
    assert_equal "주식회사 디자인하우스", client.name
    assert_equal "박과장", client.contact_name
    assert_equal "010-1234-5678", client.phone
    assert_equal "park@designhouse.co.kr", client.email
    assert_equal "123-45-67890", client.business_number
    assert_equal "지급 마감은 매월 말일, 익월 10일 지급", client.memo
  end

  test "선택 3종 공백 등록은 303으로 성공한다 (CLIENT-1 — 선택 입력 허용)" do
    sign_in_as users(:gamma)
    post app_clients_path, params: { client: {
      name: "미닝컴퍼니", contact_name: "김담당", phone: "01012345678",
      email: "", business_number: "", memo: ""
    } }
    assert_response :see_other
    client = users(:gamma).clients.order(:id).last
    assert_equal "01012345678", client.phone
    assert_empty client.email
    assert_empty client.business_number
    assert_empty client.memo
  end

  test "필수 누락 등록은 422와 필드별 한글 오류로 거부된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    assert_no_difference -> { Client.count } do
      post app_clients_path, params: { client: { name: "", contact_name: "", phone: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /거래처명을 입력해 주세요/, count: 1
    assert_select "div[role=alert] li", text: /담당자명을 입력해 주세요/, count: 1
    assert_select "div[role=alert] li", text: /휴대폰 번호를 입력해 주세요/, count: 1
  end

  test "연락처는 숫자만 입력도 허용하고 잘못된 형식은 422 한글 오류로 거부된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    post app_clients_path, params: { client: {
      name: "숫자폰거래처", contact_name: "김담당", phone: "01012345678"
    } }
    assert_response :see_other
    assert_equal "01012345678", users(:gamma).clients.order(:id).last.phone

    post app_clients_path, params: { client: {
      name: "국제번호거래처", contact_name: "김담당", phone: "+82-10-1234-5678"
    } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /휴대폰 번호 형식이 올바르지 않습니다/, count: 1
  end

  test "잘못된 이메일 형식은 422 한글 오류로 거부된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    post app_clients_path, params: { client: {
      name: "이메일오류거래처", contact_name: "김담당", phone: "010-1234-5678", email: "not-an-email"
    } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /이메일 형식이 올바르지 않습니다/, count: 1
  end

  test "한도 미도달 등록 화면은 저장 버튼이 활성으로 렌더된다 (PLAN-1 — UI 분기)" do
    sign_in_as users(:gamma)
    get new_app_client_path
    assert_response :success
    assert_no_match(/Free 플랜은 거래처/, response.body)
    assert_select "input[type=submit][value='저장']:not([disabled])", count: 1
  end

  # ── 수정·삭제(CLIENT-1) ──

  test "수정은 303으로 목록에 안내되고 DB에 반영된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    patch app_client_path(clients(:gamma_main)), params: { client: {
      name: "감마파트너스 리뉴얼", contact_name: "감차장", phone: "010-7777-8888"
    } }
    assert_response :see_other
    assert_redirected_to app_clients_path
    assert_equal "거래처 정보가 수정되었습니다.", flash[:notice]
    assert_equal "감마파트너스 리뉴얼", clients(:gamma_main).reload.name
    assert_equal "감차장", clients(:gamma_main).reload.contact_name
  end

  test "수정 실패(필수 누락)는 422로 재렌더되고 기존값이 보존된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    patch app_client_path(clients(:gamma_main)), params: { client: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "감마파트너스", clients(:gamma_main).reload.name
  end

  test "삭제는 303으로 목록에 안내되고 레코드가 제거된다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    assert_difference -> { Client.count }, -1 do
      delete app_client_path(clients(:gamma_main))
    end
    assert_response :see_other
    assert_redirected_to app_clients_path
    assert_equal "거래처가 삭제되었습니다.", flash[:notice]
  end

  test "목록·상세의 삭제 버튼은 button_to turbo_confirm 구조로 렌더된다 (CLIENT-1 — 파괴적 동작 확인)" do
    sign_in_as users(:gamma)
    get app_clients_path
    assert_response :success
    assert_select "form.button_to[action=?]", app_client_path(clients(:gamma_main)) do
      assert_select "input[name=_method][value=delete]", count: 1
      assert_select "button[data-turbo-confirm]", text: "삭제", count: 1
      assert_select "button[data-turbo-confirm='이 거래처를 삭제하시겠습니까?']", count: 1
    end

    get app_client_path(clients(:gamma_main))
    assert_select "form.button_to[action=?]", app_client_path(clients(:gamma_main)) do
      assert_select "button[data-turbo-confirm='이 거래처를 삭제하시겠습니까?']", count: 1
    end
  end

  # ── 목록·상세 렌더(CLIENT-1) ──

  test "목록은 거래처 카드에 등록 정보를 렌더한다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    get app_clients_path
    assert_response :success
    assert_select "ul[aria-label='거래처 목록'] li", count: 1
    assert_select "ul[aria-label='거래처 목록'] h3 a[href=?]",
      app_client_path(clients(:gamma_main)), text: "감마파트너스", count: 1
    assert_select "p", text: "감과장 담당", count: 1
    assert_select "dd", text: "010-7777-8888", count: 1
    assert_select "dd", text: "partner@gammapartners.co.kr", count: 1
    assert_select "dd", text: "777-77-77777", count: 1
  end

  test "상세는 필수·선택 전 필드를 렌더한다 (CLIENT-1)" do
    sign_in_as users(:gamma)
    get app_client_path(clients(:gamma_main))
    assert_response :success
    assert_select "h1", text: "감마파트너스", count: 1
    assert_select "dd", text: "감과장", count: 1
    assert_select "dd", text: "010-7777-8888", count: 1
    assert_select "dd", text: "partner@gammapartners.co.kr", count: 1
    assert_select "dd", text: "777-77-77777", count: 1
  end

  # ── 소유권 스코프 ──

  test "타 사용자 거래처 상세·수정 화면 접근은 404로 거부된다 (소유권 격리)" do
    sign_in_as users(:gamma)
    get app_client_path(clients(:beta_secret))
    assert_response :not_found
    get edit_app_client_path(clients(:beta_secret))
    assert_response :not_found
  end

  test "타 사용자 거래처 수정·삭제 요청은 404로 거부되고 값이 보존된다 (소유권 격리)" do
    sign_in_as users(:gamma)
    patch app_client_path(clients(:beta_secret)), params: { client: { name: "탈취 시도" } }
    assert_response :not_found
    delete app_client_path(clients(:beta_secret))
    assert_response :not_found
    assert_equal "베타비밀거래처", clients(:beta_secret).reload.name
  end

  # ── PLAN-1 Free 거래처 한도(alpha — fixtures 5개 보유) ──

  test "한도 도달 목록은 배너와 비활성 CTA로 렌더된다 (PLAN-1)" do
    sign_in_as users(:alpha)
    complete_profile_of
    get app_clients_path
    assert_response :success
    assert_select "ul[aria-label='거래처 목록'] li", count: 5
    assert_includes response.body, "Free 플랜은 거래처 5개까지입니다."
    assert_select "a", text: "새 거래처 등록", count: 0
    assert_select "span[aria-disabled='true']", text: "새 거래처 등록", count: 1
  end

  test "한도 도달 등록 화면은 배너와 저장 비활성으로 렌더된다 (PLAN-1 — 직접 접근)" do
    sign_in_as users(:alpha)
    complete_profile_of
    get new_app_client_path
    assert_response :success
    assert_includes response.body, "Free 플랜은 거래처 5개까지입니다."
    assert_select "input[type=submit][value='저장'][disabled]", count: 1
    assert_select "input[type=submit][value='저장'][aria-disabled='true']", count: 1
  end

  test "한도 도달 사용자의 6번째 등록 POST는 422 한도 문구로 차단된다 (PLAN-1 — 서버 최종 게이트)" do
    sign_in_as users(:alpha)
    complete_profile_of
    assert_no_difference -> { users(:alpha).clients.count } do
      post app_clients_path, params: { client: {
        name: "여섯번째 거래처", contact_name: "김여섯", phone: "010-6666-7777"
      } }
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert] li", text: /Free 플랜은 거래처 5개까지입니다/, count: 1
  end

  test "한도 도달 상태의 등록 실패 재렌더에도 배너·저장 비활성이 유지된다 (Phase 6 #2)" do
    sign_in_as users(:alpha)
    complete_profile_of
    post app_clients_path, params: { client: { name: "", contact_name: "", phone: "" } }
    assert_response :unprocessable_entity
    assert_includes response.body, "Free 플랜은 거래처 5개까지입니다."
    assert_select "input[type=submit][value='저장'][disabled]", count: 1
    # 필수 3종 blank 오류 + 한도 base 오류가 함께 노출된다(서버 게이트는 계속 차단)
    assert_select "div[role=alert] li", count: 4
    assert_select "div[role=alert] li", text: /Free 플랜은 거래처 5개까지입니다/, count: 1
  end

  test "한도 도달 상태에서도 수정은 허용된다 (PLAN-1 — on: :create)" do
    sign_in_as users(:alpha)
    complete_profile_of
    patch app_client_path(clients(:alpha_client_1)), params: { client: {
      name: "알파컴퍼니 본사", contact_name: "김철수", phone: "010-1111-2222"
    } }
    assert_response :see_other
    assert_redirected_to app_clients_path
    assert_equal "알파컴퍼니 본사", clients(:alpha_client_1).reload.name
    assert_equal 5, users(:alpha).clients.count
  end

  test "삭제 후 재등록하면 슬롯이 회수되어 5개를 유지한다 (PLAN-1)" do
    sign_in_as users(:alpha)
    complete_profile_of
    delete app_client_path(clients(:alpha_client_5))
    assert_response :see_other
    assert_equal 4, users(:alpha).clients.count

    post app_clients_path, params: { client: {
      name: "재등록 거래처", contact_name: "김재등록", phone: "010-1212-3434"
    } }
    assert_response :see_other
    assert_equal 5, users(:alpha).clients.count
  end

  test "5번째까지는 등록되고 6번째부터 차단된다 (PLAN-1 — 경계 통과)" do
    sign_in_as users(:gamma) # 1개 보유 시작 — 5개까지 성공, 6번째 차단
    4.times do |i|
      post app_clients_path, params: { client: {
        name: "경계거래처#{i + 2}", contact_name: "담당자", phone: "010-0000-#{format('%04d', i + 2)}"
      } }
      assert_response :see_other, "#{i + 2}번째 등록은 성공해야 한다"
    end
    assert_equal 5, users(:gamma).clients.count

    post app_clients_path, params: { client: {
      name: "여섯번째 거래처", contact_name: "담당자", phone: "010-0000-0007"
    } }
    assert_response :unprocessable_entity
    assert_includes response.body, "Free 플랜은 거래처 5개까지입니다."
  end

  private

  # AUTH-1.3 가드 — alpha는 프로필 미완료라 /app 진입이 차단된다. PLAN-1 한도 fixtures 검증을 위해
  # 테스트 내에서 프로필을 완료한다(완료 판정 = display_name 설정, 03 §4.1).
  def complete_profile_of
    patch app_profile_path, params: { user: {
      display_name: "알파디자인", business_type: "freelancer",
      bank_name: "국민은행", account_number: "123-45-678901",
      account_holder: "김알파", phone: "010-9000-0001"
    } }
    assert_redirected_to app_root_path
  end
end

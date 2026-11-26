require "test_helper"
require "stringio"

# 프로필 설정(AUTH-1.3) — 표면 ② 첫 화면 통합 테스트
# 시나리오 기준: _workspace/05_review.md §5 Tester 중점 2·4번, 03_implementation.md §4.1
class App::ProfilesControllerTest < ActionDispatch::IntegrationTest
  test "비인증 프로필 화면 접근은 302로 로그인 화면에 리다이렉트된다 (require_authentication)" do
    get edit_app_profile_path
    assert_response :redirect
    assert_redirected_to new_session_path
  end

  test "비인증 프로필 저장 시도도 로그인 화면에 리다이렉트되고 저장되지 않는다 (기본 가드)" do
    assert_no_changes -> { users(:alpha).reload.display_name } do
      patch app_profile_path, params: { user: { display_name: "무단변경", business_type: "business" } }
    end
    assert_redirected_to new_session_path
  end

  test "프로필 화면은 필수 2필드와 선택 4필드 폼을 렌더한다 (AUTH-1.3)" do
    sign_in_as users(:alpha)
    get edit_app_profile_path
    assert_response :success
    assert_select "h1", text: "프로필 설정"
    assert_select "input[name='user[display_name]']"
    # 탈퇴 안내의 결제 기록 보존 고지(Q33 — 방침 §3과 화면의 투명성 정합)
    assert_includes response.body, "결제 기록은 관계 법령에 따라 회원과 연결되지 않는 형태로 5년간 보관됩니다 (개인정보처리방침 §3)."
    assert_select "input[type=radio][name='user[business_type]']", count: 2
    assert_select "input[name='user[phone]']"
    assert_select "select[name='user[bank_name]']"
    assert_select "input[name='user[account_number]'][data-controller='account-number']"
    assert_select "input[name='user[account_holder]']"
    # 자동 하이픈 보조 UX(리뷰 이슈 #8 placeholder 포맷 회귀)
    assert_select "input[name='user[account_number]'][placeholder='예) 1234-5678-9012']"
  end

  test "빈값 제출은 422와 필수 필드 한글 오류로 거부된다 (AUTH-1.3)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "", business_type: "" } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert]" do |alerts|
      text = alerts.first.text
      assert_includes text, "표시명(또는 상호)을 입력해 주세요."
      assert_includes text, "사업자 유형을 선택해 주세요."
    end
    assert_nil users(:alpha).reload.display_name
  end

  test "잘못된 형식의 연락처·계좌번호는 422와 한글 오류로 거부된다 (AUTH-1.3·AUTH-9)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "business",
      phone: "010123456789", account_number: "12"
    } }
    assert_response :unprocessable_entity
    assert_select "div[role=alert]" do |alerts|
      text = alerts.first.text
      # AUTH-9(2026-11-19) — "abc"는 정규화로 공백화되므로 위반 표본은 12자리 숫자다.
      # 노출 문언은 ko.yml(user.phone.invalid) — 기존 문언 유지.
      assert_includes text, "연락처 형식이 올바르지 않습니다. 예) 010-1234-5678"
      # 리뷰 이슈 #7 — 길이 안내 포함 문구 회귀
      assert_includes text, "계좌번호 형식을 확인해 주세요. 숫자와 하이픈(-)으로 5자 이상 입력해 주세요."
    end
  end

  test "필수 2필드만으로 저장하며 선택 4필드는 공백으로 남는다 (AUTH-1.3 — 선택 입력 허용)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "  알파랩  ", business_type: "business" } }
    assert_response :see_other
    # 저장 완료 목적지 — welcome 임시 화면 소멸, /app 대시보드(03 §4.1)
    assert_redirected_to app_root_url

    user = users(:alpha).reload
    assert_equal "알파랩", user.display_name # normalizes — 앞뒤 공백 제거
    assert_equal "business", user.business_type
    assert_nil user.bank_name
    assert_nil user.account_number
    assert_nil user.account_holder
    assert_nil user.phone
  end

  test "6필드 저장은 303으로 /app에 안내하고 6컬럼 전부 DB에 반영된다 (AUTH-1.3, 03 §4.1)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "freelancer", bank_name: "우리은행",
      account_number: "1002-345-678901", account_holder: "김알파", phone: "010-1234-5678"
    } }
    assert_response :see_other
    assert_redirected_to app_root_url
    follow_redirect!
    assert_select "h1", text: "대시보드"
    assert_select "p#notice", text: "프로필 설정이 완료되었습니다."

    user = users(:alpha).reload
    assert_equal "알파스튜디오", user.display_name
    assert_equal "freelancer", user.business_type
    assert_equal "우리은행", user.bank_name
    assert_equal "1002-345-678901", user.account_number
    assert_equal "김알파", user.account_holder
    # AUTH-9(2026-11-19) — phone은 하이픈 제거 숫자만 저장(normalizes)
    assert_equal "01012345678", user.phone
  end

  test "프로필 완료 후 재로그인하면 /app으로 진입한다 (AUTH-1.3 분기, 03 §4.1)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: { display_name: "알파스튜디오", business_type: "business" } }
    assert_redirected_to app_root_url

    sign_out
    post session_path, params: { email: users(:alpha).email, password: "password" }
    assert_response :see_other
    assert_redirected_to app_root_url
  end

  test "프로필 화면 헤더는 미완료 표시명에 플레이스홀더를 노출한다 (Phase 6 #2)" do
    sign_in_as users(:alpha)
    get edit_app_profile_path
    assert_response :success
    # 표시명 공백 사용자 — 빈 span 대신 플레이스홀더(app 레이아웃 헤더)
    assert_select "header span", text: "프로필 완성 중", count: 1
  end

  test "프로필 화면 헤더는 완료 사용자의 표시명을 노출한다 (Phase 6 #2 — 완료 분기)" do
    sign_in_as users(:gamma)
    get edit_app_profile_path
    assert_response :success
    assert_select "header span", text: "감마스튜디오", count: 1
  end

  test "프로필 업데이트는 로그인 사용자에게만 적용되고 타 사용자·인증 정보는 불변이다 (소유자 스코프)" do
    sign_in_as users(:alpha)
    patch app_profile_path, params: { user: {
      display_name: "알파스튜디오", business_type: "business",
      email: "hijack@example.com", password: "escalated-secret"
    } }
    assert_redirected_to app_root_url

    alpha = users(:alpha).reload
    assert_equal "알파스튜디오", alpha.display_name
    # 파라미터 화이트리스트 밖 — 권한 상향·계정 탈취 불가
    assert_equal "alpha@example.com", alpha.email
    assert alpha.authenticate("password")
    refute alpha.authenticate("escalated-secret")
    # 단일 자원(Current.user) 스코프 — 타 사용자 레코드 무영향
    assert_nil users(:beta).reload.display_name
    assert_equal "감마스튜디오", users(:gamma).reload.display_name
  end

  test "프로필 저장 로그에서 계좌번호·예금주·연락처는 [FILTERED]로 기록된다 (리뷰 이슈 #1 — CRITICAL 회귀)" do
    sign_in_as users(:alpha)
    io = StringIO.new
    captured = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(captured)
    begin
      patch app_profile_path, params: { user: {
        display_name: "알파스튜디오", business_type: "business", bank_name: "국민은행",
        account_number: "123-45-678901", account_holder: "김알파", phone: "010-1234-5678"
      } }
    ensure
      Rails.logger.stop_broadcasting_to(captured)
    end

    log = io.string
    assert_includes log, %q("account_number" => "[FILTERED]")
    assert_includes log, %q("account_holder" => "[FILTERED]")
    assert_includes log, %q("phone" => "[FILTERED]")
    assert_not_includes log, "123-45-678901"
    assert_not_includes log, "김알파"
    assert_not_includes log, "010-1234-5678"
    # 은행명·표시명은 민감정보가 아니므로 평문 유지(과잉 필터링 방지 회귀)
    assert_includes log, "국민은행"
    assert_includes log, "알파스튜디오"
  end

  # ── AUTH-1.5 회원 탈퇴 ────────────────────────────────────────────────────────

  test "탈퇴 영역은 안내·삭제 대상 8종·확인용 이메일 입력과 상태 요약을 렌더한다 (AUTH-1.5·C-2)" do
    # C-1 — 공용 픽스처 패스(delta_active_pass, 만료 2026-12-30)의 usable 의존 제거:
    # 테스트가 직접 만든 90일 패스로 교체해 날짜와 무관하게 "남은 수금 패스 10건"을 고정한다.
    users(:delta).payment_passes.destroy_all
    travel_to(Time.zone.parse("2026-10-15 09:00")) do
      users(:delta).payment_passes.create!(total_uses: 10, remaining_uses: 10, expires_at: 90.days.from_now)
      sign_in_as users(:delta)
      get edit_app_profile_path
      assert_response :success
      assert_select "h2", text: "회원 탈퇴"
      # W-3 — 실패 시 이 섹션(#withdrawal 앵커)으로 되돌아온다
      assert_select "section#withdrawal"
      assert_match "탈퇴하면 계정과 데이터가 즉시 삭제되어", response.body
      # C-2 — 삭제되는 항목 8종(연쇄 삭제 범위 전체)·미리 저장 안내
      assert_select "#withdrawal li", text: "청구서와 청구 링크(발행 중인 링크는 모두 폐기)"
      assert_select "#withdrawal li", text: "청구서 부속 기록(입금 내역·약속·문의 응답·열람 기록)"
      assert_select "#withdrawal li", text: "거래처·품목"
      assert_select "#withdrawal li", text: "발송 이력·문의 내역"
      assert_select "#withdrawal li", text: "반복 청구 일정"
      assert_select "#withdrawal li", text: "결제·환불 내역(구독료·수금 패스·내용증명·세금계산서 결제)"
      assert_select "#withdrawal li", text: "세금계산서 발행 내역"
      assert_select "#withdrawal li", text: "계정 정보(이메일·휴대폰·프로필)"
      assert_match "필요한 내역은 탈퇴 전에 미리 저장해 주세요", response.body
      assert_select "label", text: "확인용 이메일"
      assert_select "input[name='confirm_email'][autocomplete='email']"
      # W-3 — 브라우저 pattern으로 공백만 입력 차단
      assert_select "input[name='confirm_email']" do |input|
        assert_equal ".*\\S.*", input.first["pattern"]
        assert_equal "공백 없이 가입한 이메일을 입력해 주세요", input.first["title"]
      end
      assert_select "input[type=submit][value='탈퇴합니다']"
      # 상태 요약 — delta fixtures: 미수 청구 6건(issued·overdue·due_soon·viewed·promised·
      # partially_paid · 합계 946,000원 — 입금 기록 없음)·위에서 생성한 유효 패스 잔여 10건.
      # W-4 핵심 구절 <strong> 마크업이 섞이므로 문단 텍스트 기준으로 단언한다.
      # W-5 — "받을 권리는 그대로 남습니다"로 채권 소멸 오독 방지.
      # N-3 — 주어·목적어를 명시해 "돈을 받을 수 없다" 오독을 방지한 문구
      assert_select "#withdrawal p",
                    text: /미수 청구 6건\(잔액 946,000원\)의 청구 링크가 열리지 않아, 채무자에게 받을돈 명의의 안내를 보내거나 입금 예정일 약속을 받을 수 없습니다/
      assert_match "받을 권리는 그대로 남습니다", response.body
      assert_select "#withdrawal p", text: /남은 수금 패스 10건은 소멸되며 환불되지 않습니다/
      # REM-3 안내 문구 — "주일(주말)" 오타 정정 회귀 고정
      assert_match "야간·주말 발송은 정책상 불가합니다", response.body
      assert_no_match /주일/, response.body
      # delta는 구독 행이 없어 Plus 관련 문구는 없다
      assert_no_match /Plus\(/, response.body
      assert_no_match /체험 중인 Plus/, response.body
    end
  end

  test "유료 Plus 이용 중 계정에는 즉시 종료·환불 없음·이후 결제 없음을 고지한다 (AUTH-1.5·Q29)" do
    sign_in_as users(:epsilon) # epsilon_plus_active — 주기 종료 2026-10-31·active(자동 결제 중)
    get edit_app_profile_path
    assert_response :success
    # W-4 — 핵심 구절 굵게(<strong>) markup이 섞이므로 문단 텍스트 기준으로 단언한다
    assert_select "#withdrawal p", text: /이용 중인 Plus\(10월 31일 종료 예정\)는 즉시 종료됩니다/
    assert_select "#withdrawal p", text: /남은 기간은 환불되지 않고, 이후 결제는 청구되지 않습니다/
    # epsilon은 미수 청구·수금 패스가 없어 해당 문구는 없다
    assert_no_match /미수 청구/, response.body
    assert_no_match /남은 수금 패스/, response.body
  end

  test "해지 예약(자동 결제 종료) 상태의 Plus는 남은 기간 환불 없음만 고지한다 (AUTH-1.5·W-5)" do
    users(:epsilon).subscription.update!(status: :cancelled) # PLAN-5 해지 예약 — 이후 결제 없음
    sign_in_as users(:epsilon)
    get edit_app_profile_path
    assert_response :success
    assert_select "#withdrawal p", text: /이용 중인 Plus\(10월 31일 종료 예정\)는 즉시 종료됩니다/
    assert_select "#withdrawal p", text: /남은 기간은 환불되지 않습니다/
    # 자동 결제가 이미 끝난 상태라 "이후 결제는 청구되지 않습니다" 문구는 나오지 않는다
    assert_no_match /이후 결제는 청구되지 않습니다/, response.body
  end

  test "체험 중인 Plus 계정에는 체험 즉시 종료 안내를 표시한다 (AUTH-1.5)" do
    user = users(:gamma)
    Subscription.create!(user:, plan: :plus, status: :trialing, trial_ends_at: 7.days.from_now)
    sign_in_as user
    get edit_app_profile_path
    assert_response :success
    assert_match "체험 중인 Plus는 즉시 종료됩니다", response.body
    assert_no_match /종료 예정/, response.body
  end

  test "탈퇴 확인 이메일이 불일치하면 설정 화면 탈퇴 영역으로 되돌아가고 계정·감사 로그가 변하지 않는다 (AUTH-1.5·W-3)" do
    sign_in_as users(:alpha)
    delete app_profile_path, params: { confirm_email: "wrong@example.com" }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    follow_redirect!
    assert_select "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    # N-1 — 탈퇴 영역 안에서도 같은 안내가 보인다(앵커 복귀 시 상단 alert은 화면 밖)
    assert_select "#withdrawal [role=alert]",
                  text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
  end

  test "확인용 이메일이 공백만이면 거부되고 탈퇴 영역으로 되돌아간다 (AUTH-1.5·W-3)" do
    sign_in_as users(:alpha)
    delete app_profile_path, params: { confirm_email: "   " }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    follow_redirect!
    assert_select "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    assert_select "section#withdrawal"
  end

  test "확인용 이메일이 빈 문자열이면 거부되고 탈퇴 영역으로 되돌아간다 (AUTH-1.5·W-3)" do
    sign_in_as users(:alpha)
    delete app_profile_path, params: { confirm_email: "" }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    follow_redirect!
    assert_select "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
    assert_select "section#withdrawal"
  end

  test "탈퇴 확인 이메일이 일치하면 회원·세션이 삭제되고 감사 로그와 함께 랜딩으로 안내된다 (AUTH-1.5·ADMIN-2)" do
    user = users(:alpha)
    sign_in_as user
    delete app_profile_path, params: { confirm_email: user.email.upcase } # AUTH-1.4 정규화 허용
    assert_response :see_other
    assert_redirected_to root_path
    assert_not User.exists?(user.id)
    # 세션 종료 — 연쇄 삭제로 세션 행도 소멸한다
    assert_equal 0, Session.where(user_id: user.id).count
    # 감사 로그 — admin nil·이메일 스냅샷(P4 — 삭제 후에도 대상 식별 가능)·탈퇴 시점 요약(W-8)
    log = AuditLog.find_by!(action: "member_withdrawal", target_type: "User", target_id: user.id)
    assert_nil log.admin_id
    assert_match "회원 탈퇴 — 이메일 스냅샷: alpha@example.com", log.detail
    assert_match "미수 0건(잔액 0원) · Plus: 없음 · 수금 패스 0건", log.detail
    follow_redirect!
    assert_select "p#notice", text: "탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다."
    # 세션 종료 확인 — /app 재접근은 로그인 화면으로 되돌려진다
    get app_root_path
    assert_redirected_to new_session_path
  end

  test "비로그인 탈퇴 요청은 로그인 화면으로 되돌려지고 계정이 유지된다 (require_authentication)" do
    delete app_profile_path, params: { confirm_email: users(:alpha).email }
    assert_redirected_to new_session_path
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
  end

  # ── AUTH-1.5 보강(05_review §T1·2차 Tester 중점 제안) ─────────────────────────

  test "confirm_email을 배열로 변조한 요청은 303 불일치로 끝나고 계정·데이터가 유지된다 (AUTH-1.5·W-3)" do
    sign_in_as users(:alpha)
    # 배열 제출은 confirm_email[]= 형태로 도착한다 — 서비스의 직접 비교(to_s)로는
    # 회원 이메일과 절대 같아질 수 없어 삭제가 실행되지 않는다(2차 리뷰 ②-b 실측과 동일).
    delete app_profile_path, params: { confirm_email: [ users(:alpha).email ] }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    follow_redirect!
    assert_select "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
  end

  test "confirm_email을 해시로 변조한 요청도 303 불일치로 끝나고 계정이 유지된다 (AUTH-1.5·W-3)" do
    sign_in_as users(:alpha)
    delete app_profile_path, params: { confirm_email: { email: users(:alpha).email } }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
  end

  test "confirm_email 키가 아예 없는 요청은 400으로 거부되고 계정이 유지된다 (AUTH-1.5·W-3 — 정상 경로 아님)" do
    sign_in_as users(:alpha)
    delete app_profile_path
    assert_response :bad_request
    assert_predicate users(:alpha).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
  end

  test "다른 회원의 이메일을 입력하면 거부되고 누구의 계정도 삭제되지 않는다 (AUTH-1.5)" do
    sign_in_as users(:alpha)
    delete app_profile_path, params: { confirm_email: users(:beta).email }
    assert_response :see_other
    assert_redirected_to edit_app_profile_path(anchor: "withdrawal")
    assert_predicate users(:alpha).reload, :present?
    assert_predicate users(:beta).reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    follow_redirect!
    assert_select "p#alert", text: "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
  end

  test "부분입금이 있는 미수 청구의 잔액 고지는 입금액을 차감해 표시된다 (AUTH-1.5·DASH-1 계산식)" do
    user = users(:gamma)
    invoice = Invoice.new(user: user, client: clients(:gamma_main), status: :draft,
                          due_on: 30.days.from_now.to_date, tax_mode: :separate,
                          withholding_enabled: false, issuer_display_name: "부분입금발행자",
                          bank_name: "신한은행", account_number: "110-234-567890", account_holder: "김감마",
                          items_attributes: [ { description: "유지보수", quantity: 1, unit_price: 300_000 } ])
    invoice.save!
    invoice.issue!
    Payment.create!(invoice: invoice, amount: 100_000, paid_on: Time.current.to_date)
    expected_balance = ActiveSupport::NumberHelper.number_to_delimited(
      invoice.reload.total_amount - 100_000
    )

    sign_in_as user
    get edit_app_profile_path
    assert_response :success
    assert_select "#withdrawal p", text: /미수 청구 1건\(잔액 #{Regexp.escape(expected_balance)}원\)/
  end

  test "탈퇴 성공 뒤 같은 요청을 다시 보내면 로그인 화면으로 되돌려지고 감사가 중복 기록되지 않는다 (멱등)" do
    user = users(:alpha)
    sign_in_as user
    delete app_profile_path, params: { confirm_email: user.email }
    assert_redirected_to root_path

    # 남은 세션이 없어 재요청은 인증 가드가 먼저 받는다 — 404·오류가 아닌 로그인 안내
    delete app_profile_path, params: { confirm_email: user.email }
    assert_redirected_to new_session_path
    assert_equal 1, AuditLog.where(action: "member_withdrawal").count, "재요청은 감사를 추가로 남기지 않는다"
  end

  test "탈퇴 요청은 CSRF 토큰 없이는 거부된다 (기본 보호 유지 — AUTH-1.5)" do
    original_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      sign_in_as users(:alpha)
      delete app_profile_path, params: { confirm_email: users(:alpha).email }
      assert_response 422
      assert_predicate users(:alpha).reload, :present?
      assert_equal 0, AuditLog.where(action: "member_withdrawal").count
    ensure
      ActionController::Base.allow_forgery_protection = original_protection
    end
  end
end

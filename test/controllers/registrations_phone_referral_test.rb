require "test_helper"
require_relative "../test_helpers/fake_solapi_client"
require_relative "../test_helpers/solapi_stubbing"

# 가입 플로우 — AUTH-9 세션 결합(C-1)·SALES-3 추천 어트리뷰션·SALES-4 쿠폰 예약·W-6 감사.
# 시나리오 기준: PRD §6.20 SALES-3/4·AUTH-9(검증 통과 시에만 가입·1회용)·
# _workspace/05_review.md §4 Tester 중점 1·4·5·6번 / §1 C-1.
class RegistrationsPhoneReferralTest < ActionDispatch::IntegrationTest
  include SolapiStubbing

  setup do
    @rep = sales_reps(:sales_kim)
    @code = sales_referral_codes(:sales_kim_current)
  end

  # ── C-1 회귀(최우선) — 검증 주체와 가입 주체를 같은 브라우저로 결합 ──

  test "C-1 — 인증 없이 create를 제출하면 422로 거부되고 계정이 만들어지지 않는다 (AUTH-9)" do
    assert_no_difference -> { User.count } do
      submit_signup(email: "no-verify@example.com", phone: "01012345678")
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /휴대폰 인증이 필요합니다/
  end

  test "C-1 — 브라우저 A가 검증한 번호로 브라우저 B(별도 세션)의 가입은 422로 차단된다 (리뷰 §4-1)" do
    phone = "01011112222"
    browser_a = open_session
    issue_and_verify_in(browser_a, phone:)

    browser_b = open_session
    assert_no_difference -> { User.count } do
      submit_signup_in_session(browser_b, email: "attacker@example.com", phone: phone)
    end
    browser_b.assert_response 422
    browser_b.assert_select "div[role=alert]", text: /휴대폰 인증이 필요합니다/

    # 정상 경로 — 검증한 브라우저 A 본인의 가입은 성공한다
    assert_difference -> { User.count }, +1 do
      submit_signup_in_session(browser_a, email: "owner@example.com", phone: phone)
    end
    browser_a.assert_response :see_other
    browser_a.assert_redirected_to edit_app_profile_path
  end

  test "C-1 — 다른 번호를 검증한 세션이 consumed 번호로 제출하면 422다 (세션≠제출)" do
    phone_a = "01011112222"
    phone_b = "01033334444"
    browser_a = open_session
    issue_and_verify_in(browser_a, phone: phone_a)

    browser_b = open_session
    issue_and_verify_in(browser_b, phone: phone_b) # B는 자기 번호만 검증

    assert_no_difference -> { User.count } do
      submit_signup_in_session(browser_b, email: "swapper@example.com", phone: phone_a)
    end
    browser_b.assert_response 422
    browser_b.assert_select "div[role=alert]", text: /휴대폰 인증이 필요합니다/
  end

  test "C-1 — 가입 성공 후 세션값은 소멸해 재사용할 수 없다 (30분 창이라도)" do
    phone = "01011112222"
    browser_a = open_session
    issue_and_verify_in(browser_a, phone: phone)
    submit_signup_in_session(browser_a, email: "first@example.com", phone: phone)
    browser_a.assert_response :see_other

    # 로그아웃으로 U1 세션만 종료한 뒤 같은 번호로 재가입 시도 — consumed 행은 30분 창 안에
    # 있지만 세션값이 소멸했으므로 차단돼야 한다(번호만으로 재가입 불가).
    browser_a.delete session_path
    assert_no_difference -> { User.count } do
      submit_signup_in_session(browser_a, email: "second@example.com", phone: phone)
    end
    browser_a.assert_response 422
  end

  # ── SALES-3 추천 어트리뷰션 ──

  test "유효 추천 코드로 가입하면 어트리뷰션·코드 스냅샷·쿠폰 예약이 기록된다 (SALES-3·4)" do
    assert_difference -> { User.count }, +1 do
      sign_up(email: "referred@example.com", phone: "01012345601", referred_code: @code.code)
    end
    assert_response :see_other

    user = User.find_by(email: "referred@example.com")
    assert_equal @rep.id, user.referred_by_sales_rep_id
    assert_equal @code.code, user.referral_code_snapshot, "P4 — 가입 시점 코드 스냅샷"

    coupon = user.subscription.reload.coupon
    assert_not_nil coupon, "SALES-4 — 첫결제 할인 쿠폰 예약"
    assert_equal "percent", coupon.discount_type
    assert_equal 20, coupon.discount_value
    assert_equal 1, coupon.max_redemptions
  end

  test "추천 코드는 대소문자·공백 변형도 수용하고 스냅샷은 정규화 코드다 (SALES-3)" do
    sign_up(email: "referred-case@example.com", phone: "01012345602",
            referred_code: "  #{@code.code.downcase}  ")
    assert_response :see_other

    user = User.find_by(email: "referred-case@example.com")
    assert_equal @rep.id, user.referred_by_sales_rep_id
    assert_equal @code.code, user.referral_code_snapshot
  end

  test "만료 추천 코드 입력은 422 안내로 가입이 중단된다 (SALES-2·3 — 조용한 무시 금지)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "expired-code@example.com", phone: "01012345603",
              referred_code: sales_referral_codes(:sales_kim_expired).code)
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /추천 코드가 유효하지 않거나 만료되었습니다/
  end

  test "존재하지 않는 추천 코드도 422 안내로 가입이 중단된다 (SALES-3)" do
    assert_no_difference -> { User.count } do
      sign_up(email: "unknown-code@example.com", phone: "01012345604", referred_code: "ZZZZ9999")
    end
    assert_response :unprocessable_entity
    assert_select "div[role=alert]", text: /추천 코드가 유효하지 않거나 만료되었습니다/
  end

  test "추천 코드 공백은 무시되고 추천 없는 정상 가입이 된다 (SALES-3 — 선택 입력)" do
    assert_difference -> { User.count }, +1 do
      sign_up(email: "no-referral@example.com", phone: "01012345605", referred_code: "")
    end
    assert_response :see_other

    user = User.find_by(email: "no-referral@example.com")
    assert_nil user.referred_by_sales_rep_id
    assert_nil user.referral_code_snapshot
    assert_nil user.subscription.reload.coupon_id, "쿠폰 예약 없음"
    assert_empty Coupon.where(name: "추천 가입 첫 결제 할인")
  end

  test "정지 rep의 유효 창 코드도 현재 유효 코드면 수용된다 (SALES-2 — 가입은 current_valid만 판정)" do
    suspended = sales_reps(:suspended_choi)
    code = suspended.sales_referral_codes.create!(code: "SUSPEND2", valid_from: Date.current - 1,
                                                  valid_until: Date.current + 4)
    sign_up(email: "suspended-rep@example.com", phone: "01012345606", referred_code: code.code)
    assert_response :see_other
    assert_equal suspended.id, User.find_by(email: "suspended-rep@example.com").referred_by_sales_rep_id
  end

  # ── AUTH-9 가입 파라미터 ──

  test "가입된 번호로의 재가입은 422로 거부된다 (AUTH-9 — 번호 유일)" do
    sign_up(email: "first-phone@example.com", phone: "01012345678")
    assert_response :see_other
    delete session_path # U1 로그아웃 — 같은 브라우저에서의 재가입 시도를 재현한다

    # 번호당 1분 1회 rate limit을 우회하기 위해 2분 경과 후 재시도 — verify까지 통과한
    # 제출에서 유일성 검증이 발화하는 것을 보장한다.
    travel_to(2.minutes.from_now) do
      assert_no_difference -> { User.count } do
        sign_up(email: "dup-phone@example.com", phone: "01012345678")
      end
    end
    assert_response :unprocessable_entity
    # rails-i18n ko 기본 taken 문언 — 번호 유일은 모델 검증+부분 유니크 인덱스 이중 방어
    assert_match(/이미/, response.body)
  end

  test "휴대폰 번호는 하이픈 없는 숫자로 정규화 저장된다 (AUTH-9)" do
    sign_up(email: "normalized@example.com", phone: "010-9876-0001")
    assert_response :see_other
    assert_equal "01098760001", User.find_by(email: "normalized@example.com").phone
  end

  test "인증번호 응답에는 코드가 포함되지 않고 마스킹 번호만 돌아온다 (AUTH-9)" do
    with_solapi_client(FakeSolapiClient.new) do
      post send_phone_code_registration_path, params: { phone: "01012345678" }
    end
    assert_response :ok
    json = JSON.parse(response.body)
    assert json["ok"]
    assert_equal "010****5678", json["phone"]
    assert_not_includes response.body, PhoneVerification.last.code, "코드 네트워크 응답 비노출"
  end

  test "번호당 1분 1회 — 즉시 재요청은 422 안내로 거부된다 (AUTH-9 rate limit)" do
    with_solapi_client(FakeSolapiClient.new) do
      post send_phone_code_registration_path, params: { phone: "01012345678" }
      assert_response :ok

      post send_phone_code_registration_path, params: { phone: "01012345678" }
    end
    assert_response :unprocessable_entity
    assert_match(/인증 요청이 너무 잦습니다/, response.body)
    assert_equal 1, PhoneVerification.where(phone: "01012345678").count
  end

  test "인증번호 발송은 IP당 1시간 20회로 제한된다 — 초과 시 429 JSON (AUTH-9·W-5 CGNAT 완화)" do
    with_memory_rate_limit_store do
      20.times do |i|
        with_solapi_client(FakeSolapiClient.new) do
          post send_phone_code_registration_path, params: { phone: format("010%08d", 50_000_001 + i) }
        end
        assert_response :ok, "#{i + 1}회째는 허용된다"
      end

      with_solapi_client(FakeSolapiClient.new) do
        post send_phone_code_registration_path, params: { phone: "01051000021" }
      end
      assert_response :too_many_requests
      assert_match(/인증 요청이 너무 많습니다/, response.body)
    end
  end

  # ── W-6 — 부착 실패는 가입을 막지 않고 감사 로그를 남긴다 ──

  test "쿠폰 부착 실패 시 가입은 완료되고 coupon_attach_failed 감사가 기록된다 (W-6)" do
    stub_failing_coupon_service do
      assert_difference -> { User.count }, +1 do
        sign_up(email: "attach-fail@example.com", phone: "01012345607", referred_code: @code.code)
      end
    end
    assert_response :see_other, "쿠폰 실패는 가입을 막지 않는다(정가 첫 결제 폴백)"

    user = User.find_by(email: "attach-fail@example.com")
    assert_equal @rep.id, user.referred_by_sales_rep_id, "어트리뷰션은 기록됨"
    assert_nil user.subscription.reload.coupon_id, "쿠폰은 부착되지 않았다"

    audit = AuditLog.find_by(action: "coupon_attach_failed")
    assert_not_nil audit
    assert_nil audit.admin, "U1 행위 — admin 부재(coupon_redeemed 선례)"
    assert_equal "User", audit.target_type
    assert_equal user.id, audit.target_id
  end

  private

  # W-6 주입 — AttachFirstChargeCouponService 생성 경로를 실패 객체로 교체(SolapiStubbing 패턴).
  def stub_failing_coupon_service
    original = Sales::AttachFirstChargeCouponService.method(:new)
    Sales::AttachFirstChargeCouponService.define_singleton_method(:new) do |*|
      raise StandardError, "쿠폰 부착 실패 주입(테스트)"
    end
    yield
  ensure
    Sales::AttachFirstChargeCouponService.define_singleton_method(:new, original)
  end

  # 1단계(SMS 발송 stub) + 2단계(코드 확인)를 해당 브라우저 세션에서 수행한다.
  def issue_and_verify_in(browser, phone:)
    with_solapi_client(FakeSolapiClient.new) do
      browser.post send_phone_code_registration_path, params: { phone: }
    end
    code = PhoneVerification.where(phone: phone.gsub(/\D/, "")).order(:created_at).last.code
    browser.post verify_phone_code_registration_path, params: { phone:, code: }
  end

  # 가입 create — 해당 세션에서 제출한다(파라미터만으로 verify는 수행하지 않는다).
  def submit_signup_in_session(browser, email:, phone:)
    browser.post registration_path, params: {
      user: { email:, password: "secret-123", password_confirmation: "secret-123", phone: }
    }
  end

  def submit_signup(email:, phone:)
    submit_signup_in_session(self, email:, phone:)
  end

  # 전체 플로우 — 발송 → 확인 → 가입 제출. referred_code는 선택.
  def sign_up(email:, phone:, referred_code: nil)
    issue_and_verify_in(self, phone:)
    post registration_path, params: {
      user: { email:, password: "secret-123", password_confirmation: "secret-123", phone: },
      referred_code:
    }
  end
end

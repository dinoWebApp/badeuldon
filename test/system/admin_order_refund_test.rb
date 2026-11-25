require "application_system_test_case"
require_relative "../test_helpers/portone_stubbing"
require_relative "../test_helpers/fake_portone_client"

# ADMIN-11·PLAN-9 — 관리자 주문 상세 환불 실행 브라우저 E2E(05_review §6 — 브라우저 확인창
# 실렌더 검증의 갈음). 관리자 2FA 실로그인 → 주문 상세의 실행 폼(사유 필수) → turbo_confirm
# 확인 대화창(window.confirm stub 승인 — 2026-11-06 CI 안정화 선례) → 303 동일 주소 복귀 +
# flash 요약 → 환불 완료 섹션·index "환불됨" 표기까지 실렌더로 검증한다.
#
# 포트원은 with_portone_client(클래스 생성자 교체 — 프로세스 전역)로 가로챈다. 시스템 테스트
# 서버(Puma 스레드)도 같은 프로세스라 교체가 전달되며, Turbo가 confirm 승인 후 비동기로
# 요청을 보내므로(클릭 반환 시점에 요청 진행 중일 수 있다) flash·상태 확정까지 블록을
# 유지한다 — 조기 해제 시 원본 래퍼로 실제 API가 호출된다(2026-11-24 TEST_GUARD 가드가
# 있으나 테스트 자체를 정상 경로로 고정한다 — REM 수동 발송 시스템 테스트와 같은 방침).
class AdminOrderRefundTest < ApplicationSystemTestCase
  include PortOneStubbing

  fixtures :admins, :users, :orders, :payment_passes

  test "관리자가 주문 상세에서 사유를 넣고 환불을 실행하면 완료 표시가 된다 (ADMIN-11·PLAN-9)" do
    setup_admin_totp_secrets
    order = orders(:delta_pass_order)

    login_admin(admins(:ops))
    visit admin_order_path(order)
    wait_for_turbo                                                    # 부트 대기 — confirm stub 주입 시점 보장

    assert_text "결제 취소(환불) 실행"                                  # 실행 폼 도달(로그인 세션 유효)
    assert_text "만료가 임박한 것부터 10건 차감"                         # 실행 효과 고지(W-5 — 폼 안내·확인창 공용)
    confirm_message = find(:button, "결제 취소(환불) 실행")["data-turbo-confirm"]
    assert_match(/환불을 실행할까요\? .*4,000₩/, confirm_message,
                 "확인 대화창에 금액·실행 효과가 담긴다(ADMIN-11 — data-turbo-confirm)")
    fill_in "order_refund_reason", with: REASON

    fake = FakePortOneClient.new(get_payment: { id: order.pg_order_id, status: "CANCELLED",
                                                amount: { paid: order.amount,
                                                          cancelled: order.amount } })
    with_portone_client(fake) do
      click_submit_and_await(order)                                     # confirm stub 승인 → Turbo 제출
      assert_text "환불을 실행했습니다"                                 # 성공 flash(303 → 동일 주소 재도착)
    end

    assert_text "환불이 완료된 주문입니다"                              # 환불 완료 섹션(실행 폼 감춤)
    assert_text "ops@example.com"                                    # 실행자 표기
    # 요청 처리 확정 뒤 DB·목록을 읽는다(제출 직후 읽기 금지 — admin_blog_publish_test 사연).
    assert_predicate order.reload, :refunded?
    assert_equal "cancelled", order.status
    assert_equal 0, users(:delta).payment_passes.sum(:remaining_uses), "패스 10건 차감(PLAN-9②)"
    assert_equal 1, AuditLog.where(action: "order_refund", target_type: "Order",
                                   target_id: order.id).count                         # ADMIN-2

    visit admin_orders_path
    assert_text "환불됨"                                               # 목록 표기(ADMIN-4·11)
  end

  private

  # 확인창 승인 stub + turbo:submit-start 감시를 심고 제출 버튼을 DOM 클릭한다.
  # chromedriver 클릭 간헐 드롭 이력(ApplicationSystemTestCase §7 — 본 테스트 실측 포함)으로
  # 제출 시작(turbo:submit-start·주문 상태)을 폴링하고, 시작되지 않았으면 네이티브 제출로
  # 폴백한다. 폴백은 사유를 DOM에 재주입한 뒤 같은 스크립트에서 제출한다(실측 변주 — 클릭
  # 드롭과 함께 fill_in 값이 소실된 채 빈 사유로 제출된 케이스를 원자 스크립트로 차단).
  # 확인창 문구 존재는 위 data-turbo-confirm 단정으로 검증한다. 이중 제출은 서비스의
  # with_lock·잠금 후 재검사(PLAN-9 ⑤)가 흡수한다. 테스트 스레드의 order.reload는 공유
  # 커넥션(시스템 테스트 트랜잭션 공유)으로 유효하다.
  REASON = "이중 결제 정정(시스템 테스트)"

  def click_submit_and_await(order)
    install_confirm_stub
    dom_click_button "결제 취소(환불) 실행"
    20.times do
      break if submit_started? || order.reload.refunded?
      sleep 0.1
    end
    return if submit_started? || order.reload.refunded?

    page.execute_script(<<~JS)
      var form = document.querySelector('form[action="#{refund_admin_order_path(order)}"]');
      form.querySelector('#order_refund_reason').value = #{REASON.to_json};
      form.submit();
    JS
    20.times do
      break if order.reload.refunded?
      sleep 0.1
    end
  end

  def install_confirm_stub
    page.execute_script(<<~JS)
      window.__turboSubmitStarted = false;
      window.confirm = function() { return true; };
      document.addEventListener('turbo:submit-start', function() {
        window.__turboSubmitStarted = true;
      });
    JS
  end

  def submit_started?
    page.evaluate_script("window.__turboSubmitStarted === true")
  rescue Selenium::WebDriver::Error::WebDriverError
    false # 내비게이션·평가 경합 — 폴링으로 재시도
  end

  # 관리자 2단계 실로그인(AUTH-7.1 — admin_blog_publish_test 선례). chromedriver 합성
  # 클릭 유실 이력이 있어 폼은 action 일치 네이티브 제출로 고정한다(§ submit_and_await_navigation).
  def login_admin(admin)
    visit new_admin_session_path
    fill_in "이메일", with: admin.email
    fill_in "비밀번호", with: "password"
    submit_and_await_navigation(admin_session_path)
    fill_in "인증 코드", with: totp_code(admin.otp_secret)
    submit_and_await_navigation(totp_verify_admin_session_path)
    assert_text "관리자로 로그인되었습니다."
  end

  # action이 url과 일치하는 form을 네이티브 제출한다(풀 내비게이션 — Turbo 경합 제거).
  # 근원 실측은 ApplicationSystemTestCase·admin_blog_publish_test 헤더 주석 참조.
  def submit_form_of(url)
    page.execute_script(
      "document.querySelector('form[action=\"' + arguments[0] + '\"]').submit()", url
    )
  end

  # 네이티브 제출 뒤 화면이 바뀔 때까지 기다린다(2026-11-24 실측 — 제출 직후 노드·DB 읽기
  # 실패 방지. admin_blog_publish_test의 검증된 헬퍼를 본 파일용으로 둔다).
  def submit_and_await_navigation(url)
    from_path = page.current_path
    submit_form_of(url)
    deadline = Time.now + Capybara.default_max_wait_time
    until page.current_path != from_path
      flunk "화면 전환 실패 — 현재 화면: #{page.current_url} / 표시: #{visible_text_snippet}" if Time.now >= deadline
      sleep 0.05
    end
  end

  def visible_text_snippet
    page.text.first(200)
  rescue Selenium::WebDriver::Error::WebDriverError
    "(본문 읽기 실패)"
  end
end

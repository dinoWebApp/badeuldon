require "application_system_test_case"
require_relative "../test_helpers/portone_stubbing"

# PLAN-5 — 결제 채널 키 미설정(CI와 같은 credentials 미구성 상태) 환경의 요금제 체크아웃.
# "결제하기" 버튼 대신 안내를 보여주고(fail-closed) 위젯 블록은 유지된다(리뷰 W-1 결정 범위).
# 브라우저에서 포트원 SDK가 실제로 호출될 수 있으므로 "결제하기"를 절대 클릭하지 않는다 —
# 로그인·이동·렌더 검증만 수행한다. 채널 키는 선택기 일시 교체로 고정(실제 credentials 비의존),
# 서버 스레드(동일 프로세스)에도 적용되도록 프로세스 공유 대역(with_portone_channel_keys)을 쓰고
# 블록 종료 시 복원된다.
class AppBillingChannelKeyNoticeTest < ApplicationSystemTestCase
  include PortOneStubbing

  test "수금 패스 체크아웃은 채널 키가 없으면 결제 버튼 대신 안내를 보여준다 (PLAN-5·W-1)" do
    user = users(:delta)

    travel_to(Time.zone.parse("2026-11-25 09:00")) do
      with_portone_channel_keys(normal: nil) do
        log_in_as(user)
        order = user.orders.create!(product: :collection_pass, amount: 4_000,
                                    pg_order_id: "order-system-channel-nil-1")
        visit app_billing_path(checkout: order.pg_order_id)
      end

      assert_text "결제 채널이 설정되지 않았습니다"
      assert_no_button "결제하기"
      assert_selector "[data-controller=portone-payment]", count: 1
    end
  end

  # 로그인은 공용 log_in_as(ApplicationSystemTestCase — W-7 경화, dom_click_button 제출)를 쓴다.
end

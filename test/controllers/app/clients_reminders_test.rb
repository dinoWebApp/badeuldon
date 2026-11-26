require "test_helper"

# 거래처 화면 F-REM 액션 통합 테스트(REM-7·VIEW-7) — 거래처 단위 보류 재개와 수신 거부
# 거래처의 재개 차단. 보류 자체의 발송 차단은 SendService 가드 테스트가, 청구 건 단위
# 보류·재개는 invoices_reminders_test.rb가 담당한다(계층 분리).
# 수신거부(refused_at)는 채무자 의사 표현이라 U1이 되돌리는 경로가 없다(제품 원칙 P1) —
# 보류 마킹이 남아 있어도 거부 거래처의 재개 요청은 상태를 바꾸지 않고 사유로 안내한다.
class App::ClientsRemindersTest < ActionDispatch::IntegrationTest
  fixtures :users, :clients

  test "보류한 거래처의 재개는 303으로 접수되고 마킹을 해소한다 (REM-7)" do
    sign_in_as users(:delta)
    client = clients(:delta_main)
    client.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))

    patch resume_reminders_app_client_path(client)
    assert_response :see_other
    assert_redirected_to app_client_path(client)
    assert_equal "이 거래처의 자동 안내를 재개했습니다.", flash[:notice]
    assert_not client.reload.reminders_suspended?
  end

  test "수신 거부한 거래처의 재개 요청은 상태 변경 없이 사유 안내로 거부된다 (VIEW-7·REM-7)" do
    sign_in_as users(:delta)
    client = clients(:delta_main)
    client.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-10-12 09:00"),
      refused_at: Time.zone.parse("2026-10-12 10:00")
    )

    patch resume_reminders_app_client_path(client)
    assert_response :see_other
    assert_redirected_to app_client_path(client)
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다.",
                 flash[:alert]
    client.reload
    assert client.reminders_suspended?                              # 보류 마킹 유지 — 상태 변경 없음
    assert client.refused?                                          # 거부 마킹도 유지
  end

  # W-1 — 목록 카드는 보류 판정이 먼저라 수신 거부 + 거래처 보류 겹침에 「재개」가
  # 그대로 보이던 결함의 회귀 방지. delta의 거래처는 1개라 카드가 응답에 단독이다.
  test "수신 거부 + 거래처 보류가 겹친 거래처 카드에는 재개·보류 버튼이 모두 없다 (VIEW-7·W-1)" do
    sign_in_as users(:delta)
    client = clients(:delta_main)
    client.update_columns(
      reminders_suspended_at: Time.zone.parse("2026-10-12 09:00"),
      refused_at: Time.zone.parse("2026-10-12 10:00")
    )

    get app_clients_path
    assert_response :ok
    assert_no_match(/재개/, response.body)                          # 보류 우선 판정이어도 재개는 미노출
    assert_no_match(/보류/, response.body)                          # 거부는 액션 없음 — 보류 버튼도 미노출
    assert_match(/수정/, response.body)                             # 수정·삭제 버튼은 그대로
    assert_match(/수신 거부/, response.body)                        # 거부 배지가 사유를 설명
  end

  test "거래처 보류만 단독인 거래처 카드에는 재개 버튼이 있다 (W-1 회귀 — 정상 경로 보존)" do
    sign_in_as users(:delta)
    client = clients(:delta_main)
    client.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))

    get app_clients_path
    assert_response :ok
    assert_match(/재개/, response.body)
  end

  # VIEW-7(Q30) — 상속 거래처도 직접 거부와 같은 재개 차단을 탄다(리뷰 Tester 중점 4).
  # 상속은 Client 콜백이 refused_at을 채우므로 이후 판정은 직접 거부와 동일 경로다.
  test "상속 거래처의 거래처 단위 재개 요청은 상태 변경 없이 사유 안내로 거부된다 (VIEW-7·Q30)" do
    sign_in_as users(:delta)
    users(:delta).clients.create!(name: "델타재개 원본", contact_name: "덜원본", phone: "010-3535-3535")
    mark_refused(users(:delta).clients.last, at: Time.zone.parse("2026-10-12 10:00"))
    client = users(:delta).clients.create!(name: "델타재개 상속", contact_name: "덜상속",
                                           phone: "01035353535")                # 상속
    client.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))
    assert client.reload.refused?

    patch resume_reminders_app_client_path(client)
    assert_response :see_other
    assert_redirected_to app_client_path(client)
    assert_equal "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다.",
                 flash[:alert]
    client.reload
    assert client.reminders_suspended?                              # 보류 마킹 유지 — 상태 변경 없음
    assert client.refused?                                          # 거부 마킹도 유지
  end
end

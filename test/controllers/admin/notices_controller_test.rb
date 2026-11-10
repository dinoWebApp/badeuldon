require "test_helper"

# ADMIN-6 — 공지 관리 컨트롤러(Run C). ① 목록·중요도 필터·초안 표시, ② 생성 303,
# ③ publish(초안→게시·재호출 멱등)·close(만료 기록→노출 제외), ④ 수정·삭제,
# ⑤ 비인증·U1 세션 차단. 모두 컨트롤러 경유 HTTP 수준 검증(Run A/B 교훈).
class Admin::NoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    setup_admin_totp_secrets
    @admin = admins(:ops)
  end

  test "index는 목록을 렌더하고 초안·게시 중·종료를 함께 표시한다 (ADMIN-6)" do
    admin_login(@admin)
    Notice.create!(title: "초안 공지", body: "b") # published_at nil — 초안

    get admin_notices_path
    assert_response :success
    assert_match "정기 점검 안내", response.body
    assert_match "초안 공지", response.body
    assert_match "초안", response.body
    assert_match "게시 중", response.body
  end

  test "index 중요도 필터가 동작한다 (ADMIN-6)" do
    admin_login(@admin)
    get admin_notices_path, params: { importance: "important" }
    assert_response :success
    assert_match "부가세 신고 기한 안내", response.body
    assert_no_match "정기 점검 안내", response.body

    get admin_notices_path, params: { importance: "invalid" } # 무효값은 필터 미적용(200 유지)
    assert_response :success
  end

  test "공지 생성은 303으로 목록에 안내되고 DB에 반영된다 (ADMIN-6)" do
    admin_login(@admin)
    assert_difference -> { Notice.count }, 1 do
      post admin_notices_path, params: { notice: { title: "신규 공지", body: "내용", importance: "general" } }
    end
    assert_response :see_other
    assert_redirected_to admin_notices_path
    assert_equal "신규 공지", Notice.order(:id).last.title
  end

  test "필수값 누락 생성은 422로 재렌더된다 (ADMIN-6)" do
    admin_login(@admin)
    assert_no_difference -> { Notice.count } do
      post admin_notices_path, params: { notice: { title: "", body: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "publish는 초안을 게시하고 published_at을 기록한다 — 재호출 멱등 (ADMIN-6)" do
    admin_login(@admin)
    notice = Notice.create!(title: "발행 대상", body: "b")

    patch publish_admin_notice_path(notice)
    assert_response :see_other
    notice.reload
    assert_not_nil notice.published_at
    assert notice.live?

    travel 1.hour do
      assert_no_difference -> { notice.reload.published_at.to_f } do
        patch publish_admin_notice_path(notice)
      end
    end
  end

  test "만료가 이미 과거인 초안 발행은 실패 안내(alert)로 되돌린다 — 무음 실패 방지 (W-3·ADMIN-6)" do
    admin_login(@admin)
    notice = Notice.create!(title: "지연 발행 초안", body: "b", expires_at: Time.current - 1.day)

    assert_no_difference -> { notice.reload.published_at&.to_f || 0 } do
      patch publish_admin_notice_path(notice)
    end
    assert_response :see_other
    assert_not_nil flash[:alert]
    assert_nil notice.reload.published_at
  end

  test "close는 expires_at을 기록해 노출 대상에서 제외한다 (ADMIN-6)" do
    admin_login(@admin)
    notice = notices(:general_active)

    patch close_admin_notice_path(notice)
    assert_response :see_other
    notice.reload
    assert_not_nil notice.expires_at
    assert notice.ended?
    assert_not_includes Notice.published_now, notice
  end

  test "수정은 303·삭제는 303으로 반영된다 (ADMIN-6)" do
    admin_login(@admin)
    notice = notices(:general_active)

    patch admin_notice_path(notice), params: { notice: { title: "제목 수정" } }
    assert_response :see_other
    assert_equal "제목 수정", notice.reload.title

    assert_difference -> { Notice.count }, -1 do
      delete admin_notice_path(notices(:expired_notice))
    end
    assert_response :see_other
  end

  test "비인증·U1 세션은 관리자 공지 관리에 접근할 수 없다 (AUTH-7)" do
    get admin_notices_path
    assert_redirected_to new_admin_session_path

    sign_in_as users(:gamma)
    get admin_notices_path
    assert_redirected_to new_admin_session_path
  end
end

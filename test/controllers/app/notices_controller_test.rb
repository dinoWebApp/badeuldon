require "test_helper"

# ADMIN-7 — 공지 U1 노출(Run C). ① 대시보드 일반 배너(게시 중·미읽음)·닫기=읽음 후 재노출 없음,
# ② 중요 팝업(/app 전 화면 — 레이아웃)·확인=읽음, ③ /app/notice 목록·상세·읽음 N 표시,
# ④ mark_read 멱등 303, ⑤ 만료·미래·초안 미노출, ⑥ 비인증 차단·소유 유저 본인 기록.
# 컨트롤러 경유 HTTP 수준 재현(Run A/B 교훈).
class App::NoticesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:gamma) # profile 완료 — /app 가드 통과
    sign_in_as @user
  end

  # ── 배너(일반·미읽음) ──

  test "대시보드에 게시 중 일반 공지 미읽음 배너가 노출된다 (ADMIN-7)" do
    # fixture로 gamma는 general_active를 이미 읽음 — 미읽음 일반 공지를 새로 만들어 검증
    Notice.create!(title: "배너 노출 대상", body: "b", importance: :general, published_at: Time.current)
    get app_root_path
    assert_response :success
    assert_match "배너 노출 대상", response.body
    assert_match "공지", response.body
  end

  test "배너 닫기(POST mark_read) 후 재노출되지 않는다 — 읽음 기록 1건 (ADMIN-7·SEC-5)" do
    # fixture로 gamma는 general_active를 이미 읽음 — 미읽음 일반 공지를 새로 만들어 검증
    unread = Notice.create!(title: "배너 닫기 대상", body: "b", importance: :general, published_at: Time.current)
    assert_difference -> { NoticeRead.count }, 1 do
      post mark_read_app_notice_path(unread)
    end
    assert_response :see_other

    get app_root_path
    assert_response :success
    assert_no_match "배너 닫기 대상", response.body
  end

  test "fixture로 미리 읽은 공지는 배너에 노출되지 않는다 (ADMIN-7)" do
    get app_root_path
    # gamma는 notice_reads fixture로 general_active를 읽은 상태 — important_active는 팝업 대상
    assert_no_match "정기 점검 안내", response.body
  end

  test "만료·미래 발행 공지는 대시보드에 노출되지 않는다 (ADMIN-7)" do
    get app_root_path
    assert_no_match "지난 점검 안내", response.body
    assert_no_match "아직 발행 전 안내", response.body
  end

  # ── 팝업(중요·미읽음) ──

  test "게시 중 중요 공지 팝업이 /app 전 화면에 노출된다 — 레이아웃 레벨 (ADMIN-7)" do
    get app_root_path
    assert_response :success
    assert_match "중요 공지", response.body
    assert_match "부가세 신고 기한 안내", response.body

    # 대시보드가 아닌 /app 화면(공지 목록)에서도 렌더 — 레이아웃 배치 확인
    get app_notices_path
    assert_match "부가세 신고 기한 안내", response.body
  end

  test "팝업 확인(POST mark_read) 후 다시 노출되지 않는다 (ADMIN-7)" do
    post mark_read_app_notice_path(notices(:important_active))
    assert_response :see_other

    get app_root_path
    assert_no_match "부가세 신고 기한 안내", response.body
  end

  # ── 목록·상세 ──

  test "공지 목록은 게시 중 것만 보여주고 미읽음 N 배지를 표시한다 (ADMIN-7)" do
    get app_notices_path
    assert_response :success
    assert_match "정기 점검 안내", response.body           # fixture 읽음 — N 배지 없음
    assert_match "부가세 신고 기한 안내", response.body
    assert_no_match "지난 점검 안내", response.body

    assert_match "일반", response.body                     # 중요도 배지 렌더 확인
  end

  test "공지 상세는 제목·중요도·게시 기간·본문을 보여준다 (ADMIN-7)" do
    get app_notice_path(notices(:important_active))
    assert_response :success
    assert_match "부가세 신고 기한 안내", response.body
    assert_match "제2기 중간예정신고", response.body
    assert_match "중요", response.body
  end

  test "미게시(초안·만료) 공지 상세는 404로 감춰진다 (ADMIN-7)" do
    expired = notices(:expired_notice)
    expired.update_columns(published_at: nil) # 초안도 상세 불가
    get app_notice_path(expired)
    assert_response :not_found
  end

  # ── mark_read 멱등·소유 ──

  test "mark_read 재호출은 멱등 — 레코드 증가 없이 303 (SEC-5)" do
    post mark_read_app_notice_path(notices(:general_active))
    assert_no_difference -> { NoticeRead.count } do
      post mark_read_app_notice_path(notices(:general_active))
    end
    assert_response :see_other
  end

  test "읽음 기록은 세션 유저 본인 소유다 (ADMIN-7)" do
    post mark_read_app_notice_path(notices(:important_active))
    read = NoticeRead.last
    assert_equal @user.id, read.user_id
    assert_equal notices(:important_active).id, read.notice_id
  end

  # ── C-1(05_review) — 미게시 공지 mark_read 차단 ──

  test "초안(발행 전) 공지 mark_read는 404로 차단된다 — 선읽음 우회 방지 (C-1·ADMIN-7)" do
    draft = Notice.create!(title: "초안 차단 대상", body: "b") # published_at nil
    assert_no_difference -> { NoticeRead.count } do
      post mark_read_app_notice_path(draft)
    end
    assert_response :not_found
  end

  test "미래 발행 공지 mark_read는 404로 차단된다 (C-1·ADMIN-7)" do
    assert_no_difference -> { NoticeRead.count } do
      post mark_read_app_notice_path(notices(:future_notice))
    end
    assert_response :not_found
  end

  test "이미 종료된 공지 mark_read는 허용된다 — 만료 직후 클릭 UX 유지 (C-1 권고안)" do
    post mark_read_app_notice_path(notices(:expired_notice))
    assert_response :see_other
    assert NoticeRead.exists?(user: @user, notice: notices(:expired_notice))
  end

  test "초안 차단 후 발행하면 mark_read가 정상 동작한다 — 우회 원천 봉쇄 회귀 (C-1)" do
    draft = Notice.create!(title: "발행 후 정상", body: "b")
    post mark_read_app_notice_path(draft)
    assert_response :not_found

    draft.update!(published_at: Time.current)
    post mark_read_app_notice_path(draft)
    assert_response :see_other
    assert NoticeRead.exists?(user: @user, notice: draft)
  end

  test "비인증 접근은 로그인 화면으로 리다이렉트된다 (AUTH-1)" do
    sign_out
    get app_notices_path
    assert_redirected_to new_session_path

    post mark_read_app_notice_path(notices(:general_active))
    assert_redirected_to new_session_path
  end
end

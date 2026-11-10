# ADMIN-7 공지 U1 노출(Run C) — /app/notice 목록·상세 + 읽음 기록(member POST, SEC-5 멱등).
# 노출 대상 쿼리는 컨트롤러에서 산출하고 뷰는 @변수만 소비한다(뷰 쿼리 금지).
class App::NoticesController < App::BaseController
  def index
    @notices = Notice.published_now.ordered
    @read_notice_ids = Current.user.notice_reads.where(notice_id: @notices.select(:id)).pluck(:notice_id)
  end

  def show
    @notice = Notice.published_now.find(params[:id])
    @read = Current.user.notice_reads.exists?(notice_id: @notice.id)
  end

  # 읽음 기록 — 배너 닫기·팝업 확인·상세 확인이 공용으로 POST한다. 본인 유저에만 기록되며
  # NoticeReads::MarkService로 멱등(재POST 안전). 303 PRG — Turbo 폼도 리다이렉트를 따른다.
  # C-1(05_review) — 발행된 공지만 대상(`published_at <= 현재`). 초안·미래 발행을 선읽음하면
  # 이후 발행 시 배너·팝업이 영구 미노출되는 ADMIN-7 우회라 404로 차단한다. show의
  # published_now(만료도 제외)와 달리 종료된 공지는 허용 — 세션 도중 만료된 건 클릭 UX 유지.
  def mark_read
    notice = Notice.where(published_at: ..Time.current).find(params[:id])
    NoticeReads::MarkService.call(user: Current.user, notice: notice)
    redirect_back fallback_location: app_notices_path, status: :see_other, notice: "공지를 확인했습니다."
  end
end

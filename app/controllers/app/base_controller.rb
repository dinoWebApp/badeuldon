module App
  # 표면 ②(/app) 공통 베이스 — 인증은 ApplicationController 가드(require_authentication)를 상속하고,
  # 프로필 미완료(AUTH-1.3 표시명 미설정) 사용자는 최초 프로필 설정 화면으로 안내한다.
  # 표면 ② 전용 레이아웃(app — 사이드바·헤더)을 공통 적용한다.
  class BaseController < ApplicationController
    layout "app"

    before_action :require_complete_profile
    before_action :load_active_notices

    private

    # ADMIN-7 — 게시 중 공지 중 미읽음 것을 레이아웃 팝업(중요)·대시보드 배너(일반) 소비용으로
    # 적재한다(/app 전 화면 대상이므로 베이스에서 1회). 미읽음 판정은 notice_reads 부정 조건.
    def load_active_notices
      active = Notice.published_now
      read_scope = Current.user.notice_reads.select(:notice_id)
      @unread_important_notices = active.important.where.not(id: read_scope).ordered
      @unread_general_notices = active.general.where.not(id: read_scope).ordered
    end

    # AUTH-1.3 — 청구서 발행에 표시명·계좌가 필요하므로 미설정 사용자는 프로필 설정을 먼저 완료한다.
    # 조용한 리다이렉트는 '클릭해도 반응 없음'으로 오해되므로 플래시로 이유를 전달한다.
    def require_complete_profile
      redirect_to edit_app_profile_path,
                  alert: "안전한 청구 발행을 위해 프로필을 먼저 완성해 주세요." if Current.user.display_name.blank?
    end
  end
end

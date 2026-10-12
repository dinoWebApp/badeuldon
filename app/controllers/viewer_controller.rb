# 표면 ③ 청구서 뷰어(/b/:token) — 비로그인 U2(채무자)가 공유 링크로 청구서를 확인하는 화면.
# 가입·로그인 없이 토큰으로만 조회하며(VIEW-1·P3), 유효한 열람마다 ViewEvent를 기록하고
# 최초 열람 시 상태를 issued→viewed로 전이한다(SHARE-3·INV-4). 만료·폐기·미존재 토큰은
# 전부 동일한 VIEW-6 안내 화면과 404로 응답해 존재 여부를 구분하지 않는다.
class ViewerController < ApplicationController
  layout "viewer"

  allow_unauthenticated_access only: :show  # VIEW-1·P3 — 어떤 로그인 요구도 없는 열람

  def show
    @invoice = Invoice.includes(:client).find_by(token: params[:token])
    return render :expired, status: :not_found unless link_accessible?

    ViewEvents::TrackService.new(
      invoice: @invoice, user_agent: request.user_agent, ip: request.remote_ip
    ).call
  end

  private

  # VIEW-1·P3 — 뷰어는 정적 문서 페이지(모던 JS 불필요, 클립보드 수동 복사 fallback 존재)라
  # 모든 브라우저·인앱 웹뷰를 허용한다. 카카오톡 인앱 실측(iOS 16.x + Safari/604.1)에서
  # ApplicationController 상속 정책(:modern)이 406으로 차단했다. actionpack 8.1은
  # versions: :all을 지원하지 않고(NoMethodError 실증) 상속 before_action은 익명 람다라
  # skip_before_action으로도 해제할 수 없어 같은 이름의 인스턴스 메서드를 no-op으로
  # 대체해 이 표면에서만 게이트를 무효화한다. 랜딩·앱·관리자의 :modern 정책은 불변.
  def allow_browser(**); end

  # SHARE-1/2·INV-6 — 링크 열람 가능 조건: 토큰 일치(find_by)·미폐기(voided 아님)·미만료.
  # 분기 결과는 만료/폐기/미존재 전부 동일 템플릿·동일 상태 코드(VIEW-6 + 404)로 수렴한다.
  def link_accessible?
    @invoice.present? && !@invoice.voided? &&
      @invoice.token_expires_at.present? && @invoice.token_expires_at > Time.current
  end
end

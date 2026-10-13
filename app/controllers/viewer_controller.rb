# 표면 ③ 청구서 뷰어(/b/:token) — 비로그인 U2(채무자)가 공유 링크로 청구서를 확인하고
# 응답(약속)을 보내는 화면. 가입·로그인·개인정보 입력 없이 토큰으로만 조회·응답하며
# (VIEW-1·PROMISE-2·P3), 유효한 열람마다 ViewEvent를 기록하고 최초 열람 시 상태를
# issued→viewed로 전이한다(SHARE-3·INV-4). 응답 접수는 Promises::RegisterService가 담당한다.
# 만료·폐기·미존재 토큰은 열람·응답·완료 화면 전 경로에서 동일한 VIEW-6 안내와 404로
# 응답해 존재 여부를 구분하지 않는다.
class ViewerController < ApplicationController
  layout "viewer"

  # VIEW-1·P3 — 열람·응답·완료 화면 모두 어떤 로그인 요구도 없다(토큰 보유 = 권한).
  allow_unauthenticated_access only: %i[ show create promise_thanks ]
  # F-PROMISE — 비인증 응답 경로의 스팸 방지: 토큰당 10회/10분(Rails cache increment —
  # 요청 건당 기록이므로 응답 폭주·자동화 남용을 제한한다).
  rate_limit to: 10, within: 10.minutes, by: -> { params[:token] }, only: :create

  before_action :set_invoice, only: %i[ show create promise_thanks ]

  def show
    ViewEvents::TrackService.new(
      invoice: @invoice, user_agent: request.user_agent, ip: request.remote_ip
    ).call
    @answered_inquiries = @invoice.promises.inquiry.answered.order(:answered_at, :id)  # PROMISE-6
    @promise = @invoice.promises.build  # 응답 폼 베이스 — 검증 실패 422 재렌더 시 입력 보존
  end

  # POST /b/:token/promises — 채무자 응답 접수(PROMISE-1/2). 약속(this_week·date_selected)은
  # INV-4 issued|viewed→promised 원자 전이, 입금 완료 회신·문의는 상태 불변(PROMISE-7 —
  # 수금 마감은 U1 확인으로만). 성공은 완료 화면 GET으로 PRG 전환해 재제출·이중 접수를 막는다.
  def create
    # Ruby 4.0 — 문자열 키 Parameters의 ** 스플랫은 심볼 키워드로 바인딩되지 않는다
    # (ArgumentError → 500). 키를 명시 추출하며, kind 누락 등 이례 입력도
    # InvalidResponse(422) 계약으로 수렴시킨다.
    @promise = Promises::RegisterService.new(
      invoice: @invoice,
      kind: promise_params[:kind],
      promised_on: promise_params[:promised_on],
      memo: promise_params[:memo]
    ).call
    redirect_to viewer_promise_thanks_path(@invoice.token), status: :see_other
  rescue Promises::RegisterService::InvalidResponse => e
    @promise = e.promise
    @answered_inquiries = @invoice.promises.inquiry.answered.order(:answered_at, :id)
    render :show, status: :unprocessable_entity
  end

  # GET — 응답 접수 완료 화면. 토큰만 있으면 언제든 접근 가능하므로 접수 결과 요약 없이
  # P1 톤 완료 안내만 표시한다(문의 접수 시에도 동일 문구).
  def promise_thanks; end

  private

  # SHARE-1/2·INV-6 — 링크 접근 조건: 토큰 일치(find_by)·미폐기(voided 아님)·미만료.
  # 열람·응답·완료 전 경로에 공통 적용하며, 분기 결과는 만료/폐기/미존재 전부 동일
  # 템플릿·동일 상태 코드(VIEW-6 + 404)로 수렴한다.
  def set_invoice
    @invoice = Invoice.includes(:client).find_by(token: params[:token])
    render :expired, status: :not_found unless link_accessible?
  end

  def link_accessible?
    @invoice.present? && !@invoice.voided? &&
      @invoice.token_expires_at.present? && @invoice.token_expires_at > Time.current
  end

  def promise_params
    params.expect(promise: [ :kind, :promised_on, :memo ])
  end

  # VIEW-1·P3 — 뷰어는 정적 문서 페이지(모던 JS 불필요, 클립보드 수동 복사 fallback 존재)라
  # 모든 브라우저·인앱 웹뷰를 허용한다. 카카오톡 인앱 실측(iOS 16.x + Safari/604.1)에서
  # ApplicationController 상속 정책(:modern)이 406으로 차단했다. actionpack 8.1은
  # versions: :all을 지원하지 않고(NoMethodError 실증) 상속 before_action은 익명 람다라
  # skip_before_action으로도 해제할 수 없어 같은 이름의 인스턴스 메서드를 no-op으로
  # 대체해 이 표면에서만 게이트를 무효화한다. 랜딩·앱·관리자의 :modern 정책은 불변.
  def allow_browser(**); end
end

# 표면 ③ 청구서 뷰어(/b/:token) — 비로그인 U2(채무자)가 공유 링크로 청구서를 확인하고
# 응답(약속)을 보내는 화면. 가입·로그인·개인정보 입력 없이 토큰으로만 조회·응답하며
# (VIEW-1·PROMISE-2·P3), 유효한 열람마다 ViewEvent를 기록하고 최초 열람 시 상태를
# issued→viewed로 전이한다(SHARE-3·INV-4). 응답 접수는 Promises::RegisterService가 담당한다.
# 만료·폐기·미존재 토큰은 열람·응답·완료 화면 전 경로에서 동일한 VIEW-6 안내와 404로
# 응답해 존재 여부를 구분하지 않는다.
class ViewerController < ApplicationController
  # VIEW-1 — 구형·인앱 브라우저 406 게이트 해제는 공용 concern으로 추출했다(카카오톡 인앱
  # 실측·actionpack 8.1 제약 등 메커니즘 상세는 AllowAllBrowsers 주석).
  include AllowAllBrowsers

  layout "viewer"

  # VIEW-1·P3 — 열람·응답·완료 화면 모두 어떤 로그인 요구도 없다(토큰 보유 = 권한).
  allow_unauthenticated_access only: %i[ show create promise_thanks ]
  # F-PROMISE — 비인증 응답 경로의 스팸 방지: 토큰당 10회/10분(Rails cache increment —
  # 요청 건당 기록이므로 응답 폭주·자동화 남용을 제한한다).
  rate_limit to: 10, within: 10.minutes, by: -> { params[:token] }, only: :create

  before_action :set_invoice, only: %i[ show create promise_thanks ]

  def show
    ViewEvents::TrackService.new(
      invoice: @invoice, user_agent: request.user_agent, ip: viewer_client_ip
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

  # CF Tunnel 경유 요청의 실방문자 IP(SHARE-3) — Cloudflare가 설정하는 CF-Connecting-IP를
  # 우선 사용하고, 터널 외 직접 접근(헤더 없음) 시 remote_ip로 fallback한다. ViewEvent 기록 전용
  # (전역 remote_ip 재계산은 후속 과제).
  def viewer_client_ip
    request.headers["CF-Connecting-IP"].presence || request.remote_ip
  end

  def link_accessible?
    @invoice.present? && !@invoice.voided? &&
      @invoice.token_expires_at.present? && @invoice.token_expires_at > Time.current
  end

  def promise_params
    params.expect(promise: [ :kind, :promised_on, :memo ])
  end
end

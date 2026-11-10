# 청구서(INV) — 초안 CRUD + 발행(issue)·무효(void) 상태 전환. 조회·변경은 모두
# Current.user.invoices로 스코프하며, 본문 수정(INV-5)은 draft 스코프로만, 무효(INV-6)는
# 발행 계열 스코프로만 접근한다. 발행 시 채번·토큰 생성(INV-1·SHARE-1)과 월 3건 한도(PLAN-1)
# 검사는 Invoice#issue!가 담당한다. F-REM — 발행 안내 선택(SHARE-6)·자동 안내 보류/재개(REM-7)·
# 수동 발송(REM-8)의 member 전환과 발송 이력 화면(REM-6) 데이터 적재를 담당하며, 실제 발송
# 판정(가드·상한·발송 창)은 Reminders::SendService가 단일 담당한다.
class App::InvoicesController < App::BaseController
  # F-REM — 발송 이력·수동 발송 컨텍스트 적재(RemindersContext). 422 재렌더 대응 상세는
  # Payments·Promises 컨트롤러의 load_invoice_show와 공유한다.
  include RemindersContext

  before_action :set_invoice, only: %i[ show ]
  before_action :set_draft_invoice, only: %i[ edit update destroy issue ]
  before_action :set_voidable_invoice, only: %i[ void ]
  before_action :set_linkable_invoice, only: %i[ regenerate_token ]
  # F-REM — 보류·재개·수동 발송은 미수 계열만 대상으로 한다(초안은 링크·발송이 없고,
  # 수금완료·무효는 발송 모집합에서 제외된다 — Invoice.unsettled와 동일 모집단).
  before_action :set_unsettled_invoice, only: %i[ suspend_reminders resume_reminders remind restart_reminders ]
  # SHARE-3 — 열람 이력 요약(최초·최근·횟수). 422 재렌더(issue·void·재발급 실패)에서도
  # show 템플릿이 동일한 @변수를 갖도록 함께 적재한다 — 대상 조회(set_*_invoice) 뒤에서 실행.
  before_action :set_view_events, only: %i[ show issue void regenerate_token ]
  # F-PROMISE — 응답·약속 이력(최신 우선 — 청구서 약속 표시는 최신 응답 기준). 422 재렌더 대응은
  # set_view_events와 동일 취지다.
  before_action :set_promises, only: %i[ show issue void regenerate_token ]
  # F-PAY — 입금 이력·입금 폼(입금일 기본 오늘). 422 재렌더 대응은 set_view_events와 동일 취지다.
  before_action :set_payments, only: %i[ show issue void regenerate_token ]
  # F-REM(REM-6) — 발송 이력(최신 우선). 422 재렌더 대응은 set_view_events와 동일 취지다.
  before_action :set_message_logs, only: %i[ show issue void regenerate_token ]
  # F-REM(REM-8) — 수동 발송 버튼의 자격·다음 안내 표기용. 뷰의 쿼리·모델 호출 금지 규칙에 따라
  # 컨트롤러가 미리 산출해 @변수로 넘긴다.
  before_action :set_reminder_context, only: %i[ show issue void regenerate_token ]

  def index
    @invoices = Current.user.invoices.includes(:client).sorted_by_due  # DASH-4 정렬과 동일
  end

  def show; end

  def new
    @invoice = Current.user.invoices.build(
      due_on: Date.current + Invoice::DEFAULT_DUE_IN_DAYS,          # INV-3
      withholding_enabled: Current.user.freelancer?,                # INV-2 프리랜서 기본
      bank_name: Current.user.bank_name,                            # 계좌 프로필 프리필
      account_number: Current.user.account_number,
      account_holder: Current.user.account_holder
    )
    @invoice.items.build
    prepare_form_options
  end

  def create
    permitted = invoice_params
    # 품목 행은 소속 검증 통과 후 할당한다 — 위조 id가 nested attributes에 들어가면 500이 되기 때문.
    @invoice = Current.user.invoices.build(permitted.except(:items_attributes))
    @invoice.issuer_display_name = Current.user.display_name  # INV-1 발행자 표시명 스냅샷
    return render_forged_items(:new) unless item_ids_owned?(permitted)

    @invoice.attributes = permitted.slice(:items_attributes) if permitted[:items_attributes].present?
    if @invoice.save
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "청구서 초안이 저장되었습니다."
    else
      prepare_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_form_options
  end

  def update
    permitted = invoice_params
    return render_forged_items(:edit) unless item_ids_owned?(permitted)

    if @invoice.update(permitted)
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "청구서 초안이 수정되었습니다."
    else
      prepare_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @invoice.destroy!
    redirect_to app_invoices_path, status: :see_other,
                notice: "청구서 초안이 삭제되었습니다."
  end

  # 초안 → 발행(INV-4). 성공 303 / 실패 422 — 한도·검증 실패 문구는 모델 errors에서 안내한다.
  # SHARE-6 — send_notice 체크(기본 켬) 시 발행 확정 후 issue_notice를 인큐한다. Invoice#issue!는
  # 모델 메서드라 발행 훅 위치가 컨트롤러에 있다(3-a 인계 사항). REM-3 창 밖이면 SendService가
  # 다음 평일로 예약하므로 컨트롤러는 인큐만 책임진다.
  def issue
    return render_issue_failure unless @invoice.issue!

    enqueue_issue_notice if issue_notice_requested?
    redirect_to app_invoice_path(@invoice), status: :see_other, notice: issue_success_notice
  end

  # 발행 계열 → 무효(INV-6 — 토큰 즉시 폐기)
  def void
    if @invoice.void!
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "청구서가 무효 처리되었습니다."
    else
      flash.now[:alert] = @invoice.errors.full_messages_for(:base).first
      render :show, status: :unprocessable_entity
    end
  end

  # 링크 재발급(SHARE-2 수동 재발급) — 새 토큰 교체로 기존 링크 즉시 무효, 유효기간 유지.
  def regenerate_token
    if @invoice.regenerate_token!
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "링크가 재발급되었습니다. 기존 링크는 즉시 무효화됩니다."
    else
      flash.now[:alert] = @invoice.errors.full_messages_for(:base).first
      render :show, status: :unprocessable_entity
    end
  end

  # REM-7 — 청구 건 단위 발송 보류(REM-11 사전통보의 「보류하기」와 동일 동작). 타임스탬프
  # 마킹만 수행하며 재개 전까지 SendService 가드(SUSPENDED)가 자동·수동 발송을 모두 차단한다.
  # touch는 검증·콜백 없이 시각 기록만 한다 — 본문 불변 가드(INV-5)와 무관한 컬럼이다.
  def suspend_reminders
    @invoice.touch(:reminders_suspended_at)
    redirect_to app_invoice_path(@invoice), status: :see_other,
                notice: "이 청구서의 자동 안내를 보류했습니다. 예정된 발송은 취소됩니다."
  end

  # REM-7 — 청구 건 보류 재개. 거래처 단위 보류·수신거부는 별도 상태다(화면 배지로 안내).
  def resume_reminders
    @invoice.update_column(:reminders_suspended_at, nil)
    redirect_to app_invoice_path(@invoice), status: :see_other,
                notice: "이 청구서의 자동 안내를 재개했습니다. 다음 단계부터 이어집니다."
  end

  # REM-8 — 수동 발송(플랜 무관 버튼). 템플릿은 "현재 상황에 맞는 다음 1통"을 DispatchService의
  # 공개 산정 진입점(manual_step_key — 단일 출처)으로 산정해 넘기고, 가드·상한·발송 창·기록은
  # SendService가 동일 적용한다(P4 — 모든 시도는 발송 이력에 남는다).
  def remind
    # manual_step_key가 nil = 18종 중 참인 템플릿이 없는 창(예: 만기 도과 + 미래 약속의
    # 약속 전날 이전 구간 — Phase 6 C-2). 발송·로그 기록 없이 안내로 수렴한다(P1 톤).
    return redirect_no_template if manual_template_key.nil?

    result = Reminders::SendService.new(
      invoice: @invoice, template_key: manual_template_key,
      recipient_role: :debtor, origin: :manual
    ).call
    redirect_to app_invoice_path(@invoice), status: :see_other, notice: remind_notice(result)
  rescue Solapi::ApiError
    # 모호 실패(TIMEOUT/CONNECTION) — SendService가 failed 기록 후 재상승한 것. 컨트롤러는
    # 사용자 안내만 하고 재시도는 발송 이력의 수동 재발송으로 이어진다.
    redirect_to app_invoice_path(@invoice), status: :see_other,
                alert: "일시적인 오류로 안내 발송에 실패했습니다. 잠시 후 다시 시도해 주세요."
  end

  # Phase 6 C-2 — 참인 안내 문구가 없는 창의 수동 발송 수렴. 발송 시도 자체를 하지 않으므로
  # MessageLog 기록도 없다(스킵도 아님 — "보낼 문구가 없다"는 상태이지 발송 시도가 아니다).
  def redirect_no_template
    redirect_to app_invoice_path(@invoice), status: :see_other,
                notice: "지금 상황에서 보낼 수 있는 안내 문구가 없습니다. 약속일이 지나면 자동으로 안내됩니다."
  end

  # REM-12·13 — 시퀀스 수동 재개("이후 재개는 U1의 수동 재요청으로만 가능" — 자동 재개는
  # 없다). 종결 마킹 해소는 U1의 명시적 재요청이며, 재개 후 다음 평일 스캔이 기존
  # DispatchService 논리로 미발송 스텝부터 이어서 산정한다(소급 창 밖 스텝은 PAST_WINDOW로
  # 차단 — 무한 소급 없음). 보낼 스텝이 남지 않았으면 재개해도 발송이 없으므로 해소하지
  # 않고 안내한다(restartable? — DispatchService 공개 판정).
  def restart_reminders
    if Reminders::DispatchService.new.restartable?(@invoice)
      @invoice.restart_sequence!
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "정기 안내를 다시 진행합니다. 남은 단계부터 이어서 보냅니다."
    else
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  alert: restart_unavailable_notice
    end
  end

  private

  def set_invoice
    @invoice = Current.user.invoices.find(params[:id])
  end

  # SHARE-3 — 열람 이력(시간순). show 템플릿의 최초·최근 열람·횟수 요약에 쓴다.
  def set_view_events
    @view_events = @invoice.view_events.order(:viewed_at, :id)
  end

  # F-PROMISE — 응답·약속 이력(최신 우선). 타임라인 첫 행이 최신 응답이며 약속 표시 기준이다.
  def set_promises
    @promises = @invoice.promises.order(created_at: :desc, id: :desc)
  end

  # F-PAY — 입금 이력(입금일 내림차순)과 폼용 신규 입금(입금일 기본 오늘 — PAY-1·TIME-1).
  # 폼 객체는 컬렉션에 붙이지 않고(invoice_id 직접 지정) 분리해 둔다 — payments 컬렉션에
  # 추가하면 청구서 저장(issue!/void! 등) 시 미완성 Payment가 자동 저장되어
  # "Payments is invalid"로 발행이 막힌다.
  def set_payments
    @payments = @invoice.payments.order(paid_on: :desc, id: :desc)
    @payment = Payment.new(invoice_id: @invoice.id, paid_on: Date.current)
  end

  # INV-5 — 발행 후 본문 수정 불가: 수정·삭제·발행 진입은 초안만 조회한다(이외는 404).
  def set_draft_invoice
    @invoice = Current.user.invoices.draft.find(params[:id])
  end

  # INV-6 — 무효는 발행 계열만 조회한다.
  def set_voidable_invoice
    @invoice = Current.user.invoices.voidable.find(params[:id])
  end

  # F-REM — 보류·재개·수동 발송은 미수 계열만 조회한다(초안·수금완료·무효는 404로 수렴 —
  # 소유권 격리는 set_invoice와 동일하게 Current.user 스코프로 담보한다).
  def set_unsettled_invoice
    @invoice = Current.user.invoices.unsettled.find(params[:id])
  end

  # SHARE-6 — 체크박스(hidden 0 + checked 1) 접수값. 파라미터 부재도 기본 켬으로 해석한다.
  def issue_notice_requested?
    params[:send_notice] != "0"
  end

  # SHARE-6 — 발행 안내 알림톡(채무자 향 1회성 — PLAN-3 상한 집계 밖). 창 밖 예약 여부는
  # SendService가 판정하므로 컨트롤러는 커밋 후 인큐만 한다.
  def enqueue_issue_notice
    Reminders::DeliverJob.perform_later(@invoice.id, "issue_notice", "debtor")
  end

  # SHARE-6 — 결과 안내. 선택 시 서비스 명의 첫 안내를, 해제 시 직접 전달을 안내한다.
  def issue_success_notice
    if issue_notice_requested?
      "청구서가 발행되었습니다. 거래처에게 받을돈 명의의 첫 안내를 보냅니다."
    else
      "청구서가 발행되었습니다. 링크를 복사해 거래처에 직접 전달하세요."
    end
  end

  def render_issue_failure
    flash.now[:alert] = @invoice.errors.full_messages_for(:base).first
    render :show, status: :unprocessable_entity
  end

  # REM-8 — 수동 발송 결과 안내. skipped 사유는 방금 기록된 최신 이력(error_code)에서 읽는다.
  def remind_notice(result)
    case result
    when :sent        then "거래처에게 안내를 발송했습니다."
    when :rescheduled then "지금은 발송 가능 시간(평일 09:00~18:00)이 아니어서 다음 평일 오전 9시에 발송됩니다."
    when :failed      then "안내 발송에 실패했습니다. 발송 이력에서 실패 사유를 확인해 주세요."
    when :duplicate   then "방금 발송이 처리 중이거나 이미 발송되었습니다. 발송 이력을 확인해 주세요."
    else "지금은 발송하지 않았습니다 — #{helpers.message_log_skip_reason(latest_log_error_code)}"
    end
  end

  def latest_log_error_code
    MessageLog.where(invoice_id: @invoice.id).order(:id).last&.error_code
  end

  # REM-12·13 — 재개 불가 안내(남은 미발송 단계 전부 소급 창 경과). 재개 요청은 받아들이지
  # 않고(종결 마킹 유지) 상태를 그대로 안내한다.
  def restart_unavailable_notice
    "다시 보낼 수 있는 남은 단계가 없어 진행하지 않았습니다. 필요하면 개별 안내를 직접 확인해 주세요."
  end

  # SHARE-2 — 재발급은 링크 보유 건만 조회한다(초안·무효 제외 — INV-6).
  def set_linkable_invoice
    @invoice = Current.user.invoices.linkable.find(params[:id])
  end

  def prepare_form_options
    @clients = Current.user.clients.order(:name)
    @items = Current.user.items.order(:name)
  end

  def invoice_params
    # expect 중첩 폼 — 임의 키(행 인덱스) 해시를 허용하는 문서형 [[...]] 배열(8.1 검증 실측).
    params.expect(invoice: [
      :client_id, :due_on, :tax_mode, :withholding_enabled,
      :bank_name, :account_number, :account_holder,
      { items_attributes: [ [ :id, :description, :quantity, :unit_price, :_destroy ] ] }
    ])
  end

  # 무결성 — 위조 품목 id(타인 청구서 항목 지정)는 nested attributes 할당 시
  # RecordNotFound(500)로 이어지므로, 할당 전에 초안 보유 항목 스코프로 소속을 검증한다.
  # 신규 초안은 보유 항목이 없어 id가 지정된 행은 전부 불일치다.
  def item_ids_owned?(permitted)
    rows = permitted[:items_attributes]
    rows = rows.values if rows.is_a?(ActionController::Parameters)
    return true if rows.blank?

    own_ids = @invoice.items.ids.map(&:to_s)
    rows.all? { |row| row[:id].blank? || own_ids.include?(row[:id].to_s) }
  end

  # 소속 불일치 품목이 섞인 요청 — 검증 실패와 동일하게 422를 응답한다(레코드 생성·수정 없음).
  def render_forged_items(template)
    @invoice.errors.add(:base, "유효하지 않은 품목 요청입니다. 품목 행을 확인해 주세요")
    prepare_form_options
    render template, status: :unprocessable_entity
  end
end

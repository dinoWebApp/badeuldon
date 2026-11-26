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

  before_action :set_invoice, only: %i[ show payment_pdf ]
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
  # REF-1 — D+30 도달·미수 청구 상세 상단의 추심 상담 안내 배너 노출 판정.
  before_action :set_referral_banner, only: :show
  # LEGAL-1 — D+30 초과·미수 청구 상세 상단의 내용증명 안내 배너 노출 판정(REF 배너와 동일 조건).
  before_action :set_legal_banner, only: :show
  # TAX-1/2 — paid 청구 상세의 전자세금계산서 발행 버튼·발행 이력 표시 판정(가드 분기는
  # 컨트롤러가 산출해 @변수로 — 뷰의 쿼리·모델 호출 금지 규칙).
  before_action :set_tax_invoice_context, only: :show

  def index
    @invoices = Current.user.invoices.includes(:client).sorted_by_due  # DASH-4 정렬과 동일
  end

  def show; end

  # PAY-6 — 수금완료 증빙 PDF 다운로드(Q17). 소유권은 set_invoice(Current.user 스코프)로 담보하고,
  # 미마감 청구는 404 대신 상세로 되돌려 안내한다 — UX 판정: 상태 안내가 사용자 혼란이 적고,
  # 서비스 가드(Invoices::ReceiptPdfService::PdfNotAvailable)와 이중 방어를 이룬다.
  def payment_pdf
    pdf = Invoices::ReceiptPdfService.call(invoice: @invoice)
    send_data pdf,
              filename: "수금완료증빙_#{@invoice.issue_number}.pdf",
              type: "application/pdf"
  rescue Invoices::ReceiptPdfService::PdfNotAvailable
    redirect_to app_invoice_path(@invoice), status: :see_other,
                alert: "수금이 마감된 청구서만 증빙을 내려받을 수 있습니다."
  end

  # CLIENT-4 — 발행 직전 거래처 지급 성적표 요약(폼 거래처 선택 시 fetch로 갱신). 조회는
  # Current.user.clients 스코프로 격리해 타인 거래처는 404로 수렴한다(소유권 격리).
  # 지표 산출은 Clients::PaymentScorecardQuery(Q14 파생 판정)가 단일 담당한다.
  def scorecard
    client = Current.user.clients.find(params.expect(:client_id))
    render partial: "scorecard_summary",
           locals: { scorecard: Clients::PaymentScorecardQuery.call(client: client) }
  end

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

    enqueue_issue_notice_if_needed
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

  # REM-7 — 청구 건 보류 재개. 거래처 단위 보류는 별도 상태다(화면 배지로 안내).
  # VIEW-7 — 거래처 수신 거부 분은 재개 대상이 아니다(보류를 해소해도 REFUSED 가드로 발송이
  # 영원히 없다 — 상태 변경 없이 사유 안내로 거부한다).
  def resume_reminders
    return redirect_resume_refused if @invoice.client.refused?

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
  # VIEW-7 — 거래처 수신 거부 분은 재개 대상이 아니다(refused_at은 채무자 의사라 U1이
  # 되돌리는 경로가 없고, 지우면 reminders_dispatchable에서 영구 제외된 채 "다시 진행"
  # 안내만 준다 — 상태 변경 없이 사유 안내로 거부한다).
  def restart_reminders
    return redirect_restart_refused if @invoice.client.refused?

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

  # REF-1 — 추심 상담 안내 배너 노출 판정. 미수 계열(unsettled)이고 만기일이 30일 초과
  # 경과(due_on + 30 < 오늘)일 때만 참. 판정은 App::ReferralsController의 목록 모집합과
  # 동일 조건으로 유지한다. 뷰의 쿼리 금지 규칙에 따라 컨트롤러가 산출해 @변수로 넘긴다.
  def set_referral_banner
    @referral_banner = @invoice.unsettled? && @invoice.due_on.present? &&
                       @invoice.due_on + 30 < Date.current
  end

  # LEGAL-1 — 내용증명 배너 노출 판정. 조건은 ContentProofPdfService.legal_target?(단일 출처)과
  # 동일하다(뷰의 쿼리 금지 규칙에 따라 컨트롤러가 산출해 @변수로 넘긴다).
  # TAX-1/2 — paid 청구의 발행 컨텍스트. tax_invoice(기존 발행 기록)와 guard(U1이 지금 발행
  # 가능한지의 분기)를 산출한다: feature_disabled(TAX-4 — 기능 스위치 꺼짐)·tax_type_ineligible
  # (TAX-3 — 간이과세·면세사업자)·settings_missing(발행 설정·인증서 미완료)·client_missing
  # (거래처 사업자번호 없음)·ready(발행 가능)·none(paid 이외 — 버튼 비노출).
  # Phase 6 C-2 — 발행 레코드가 없어도 paid 주문이 있으면(결제 후 SOAP 실패) :paid_pending
  # 분기로 재결제 버튼을 노출하지 않고 기존 주문 상태 확인으로 유도한다.
  # TAX-3/4 판정 우선순위(리뷰 W-1) — 기존 발행 기록(있으면 그대로 표시) > paid_pending
  # (결제 완료·발행 기록 없음) > 꺼짐 > 자격 없음 > settings_missing > client_missing >
  # ready. 돈을 낸 사용자(paid_pending)는 꺼짐·자격 안내에 가려지지 않고 주문 확인 링크를
  # 잃지 않는다(paid_pending 카드에는 발행 버튼이 없어 두 게이트가 약해지지 않는다).
  def set_tax_invoice_context
    @tax_invoice = @invoice.tax_invoice
    @tax_invoice_guard = nil
    @tax_invoice_order = nil
    @tax_invoice_guard_notice = nil
    return unless @invoice.paid?
    return if @tax_invoice

    @tax_invoice_guard = if (@tax_invoice_order = Order.tax_invoice_order_for(@invoice, paid: true))
      :paid_pending
    elsif !TaxInvoice.feature_enabled?
      :feature_disabled
    elsif !Current.user.tax_invoice_eligible?
      @tax_invoice_guard_notice = Current.user.tax_invoice_ineligibility_notice
      :tax_type_ineligible
    elsif !Current.user.tax_invoice_ready?
      :settings_missing
    elsif @invoice.client.corp_num.blank?
      :client_missing
    else
      :ready
    end
  end

  def set_legal_banner
    @legal_banner = LegalDocuments::ContentProofPdfService.legal_target?(@invoice)
  end

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

  # SHARE-6 — 발행 안내 인큐 판정. VIEW-7(Q30·리뷰 W-1) — 수신 거부(상속 포함) 거래처는 첫
  # 안내를 예약하지 않는다. 인큐 단계에서 건너뛰지 않으면 SendService의 창 판정(reschedule!)
  # 이 REFUSED 가드보다 앞서 「발송 예정」 pending 행이 다음 발송 창까지 남는다(가드 순서는
  # 유지 — REFUSED 가드는 여전히 최종 방어선).
  def enqueue_issue_notice_if_needed
    return if @invoice.client.refused?

    enqueue_issue_notice if issue_notice_requested?
  end

  # SHARE-6 — 발행 안내 알림톡(채무자 향 1회성 — PLAN-3 상한 집계 밖). 창 밖 예약 여부는
  # SendService가 판정하므로 컨트롤러는 커밋 후 인큐만 한다.
  def enqueue_issue_notice
    Reminders::DeliverJob.perform_later(@invoice.id, "issue_notice", "debtor")
  end

  # SHARE-6 — 결과 안내. 선택 시 서비스 명의 첫 안내를, 해제 시 직접 전달을 안내한다.
  # VIEW-7(Q30·리뷰 W-1) — 수신 거부(상속 포함) 거래처는 첫 안내가 나가지 않으므로
  # 인큐 여부와 무관하게 직접 전달로 안내한다.
  def issue_success_notice
    if @invoice.client.refused?
      "청구서가 발행되었습니다. 이 거래처는 추가 안내 수신을 거부하여 첫 안내는 보내지 않습니다. " \
        "링크를 복사해 거래처에 직접 전달하세요."
    elsif issue_notice_requested?
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

  # VIEW-7 — 수신 거부 거래처의 청구 보류 재개 요청 수렴. 상태 변경 없이 같은 화면으로
  # 돌려보내고 사유를 안내한다(거부 접수 배너가 뷰에 이미 있어 추가 문구 노출은 없다).
  def redirect_resume_refused
    redirect_to app_invoice_path(@invoice), status: :see_other,
                alert: "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다."
  end

  # VIEW-7 — 수신 거부 거래처의 재개 요청 수렴. 상태 변경 없이 같은 화면으로 돌려보내고
  # 사유를 안내한다(거부 접수 배너가 뷰에 이미 있어 추가 문구 노출은 없다).
  def redirect_restart_refused
    redirect_to app_invoice_path(@invoice), status: :see_other,
                alert: "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다."
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

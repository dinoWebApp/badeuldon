# 청구서(INV) — 초안 CRUD + 발행(issue)·무효(void) 상태 전환. 조회·변경은 모두
# Current.user.invoices로 스코프하며, 본문 수정(INV-5)은 draft 스코프로만, 무효(INV-6)는
# 발행 계열 스코프로만 접근한다. 발행 시 채번·토큰 생성(INV-1·SHARE-1)과 월 3건 한도(PLAN-1)
# 검사는 Invoice#issue!가 담당한다.
class App::InvoicesController < App::BaseController
  before_action :set_invoice, only: %i[ show ]
  before_action :set_draft_invoice, only: %i[ edit update destroy issue ]
  before_action :set_voidable_invoice, only: %i[ void ]

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
  def issue
    if @invoice.issue!
      redirect_to app_invoice_path(@invoice), status: :see_other,
                  notice: "청구서가 발행되었습니다."
    else
      flash.now[:alert] = @invoice.errors.full_messages_for(:base).first
      render :show, status: :unprocessable_entity
    end
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

  private

  def set_invoice
    @invoice = Current.user.invoices.find(params[:id])
  end

  # INV-5 — 발행 후 본문 수정 불가: 수정·삭제·발행 진입은 초안만 조회한다(이외는 404).
  def set_draft_invoice
    @invoice = Current.user.invoices.draft.find(params[:id])
  end

  # INV-6 — 무효는 발행 계열만 조회한다.
  def set_voidable_invoice
    @invoice = Current.user.invoices.voidable.find(params[:id])
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

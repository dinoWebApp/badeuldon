# 거래처 관리(CLIENT-1) — 표면 ② 표준 CRUD. 조회·변경은 모두 Current.user.clients로 스코프해
# 타 사용자 데이터 접근을 차단하며, Free 거래처 한도(PLAN-1)는 Client 모델 검증으로 강제한다.
# F-REM — 거래처 단위 발송 보류/재개(REM-7)의 member 전환을 담당한다. 수신거부(VIEW-7)는
# 채무자 의사 표현이라 U1이 되돌릴 수 없으며(제품 원칙 P1), 재개 경로도 두지 않는다.
class App::ClientsController < App::BaseController
  before_action :set_client, only: %i[ show edit update destroy suspend_reminders resume_reminders ]

  def index
    @clients = Current.user.clients.order(:id)
    @limit_reached = Current.user.client_limit_reached?(Current.user.clients.count)
  end

  def show
    # CLIENT-3/4 — 거래처 카드·지급 성적표·약속 이행 이력(Q14 파생 판정 — Queries::Clients).
    @scorecard = Clients::PaymentScorecardQuery.call(client: @client)
    @compliance = Clients::PromiseComplianceQuery.call(client: @client)
  end

  def new
    @client = Current.user.clients.build
    @limit_reached = Current.user.client_limit_reached?(Current.user.clients.count)
  end

  def create
    @client = Current.user.clients.build(client_params)
    if @client.save
      redirect_to app_clients_path, status: :see_other, notice: "거래처가 등록되었습니다."
    else
      # 실패 재렌더에서도 배너·저장 버튼 상태를 목록/신규 화면과 동일하게 유지한다(PLAN-1).
      @limit_reached = Current.user.client_limit_reached?(Current.user.clients.count)
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @client.update(client_params)
      redirect_to app_clients_path, status: :see_other, notice: "거래처 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # CLIENT-1(P4·REM-6) — 발행 이력 보유 거래처의 삭제는 모델 가드에서 차단되며, 실패 시
  # 오류 안내를 flash alert으로 전달하고 목록으로 되돌린다(303 유지).
  def destroy
    if @client.destroy
      redirect_to app_clients_path, status: :see_other, notice: "거래처가 삭제되었습니다."
    else
      redirect_to app_clients_path, status: :see_other, alert: @client.errors.full_messages.join(" ")
    end
  end

  # REM-7 — 거래처 단위 발송 보류: 이 거래처의 모든 청구서 자동 안내를 멈춘다(가드 SUSPENDED).
  # 타임스탬프 마킹만 수행하며(touch — 검증·콜백 우회 의도), 재개 전까지 스캔 모집합에서
  # 제외된다(Client.reminders_active).
  def suspend_reminders
    @client.touch(:reminders_suspended_at)
    redirect_to app_client_path(@client), status: :see_other,
                notice: "이 거래처의 자동 안내를 보류했습니다. 모든 청구서에 적용됩니다."
  end

  # REM-7 — 거래처 단위 보류 재개. VIEW-7 — 수신거부(refused_at) 거래처는 재개 대상이 아니다
  # (채무자 의사 표현이라 U1이 되돌리는 경로가 없고, 보류를 해소해도 발송이 없다 — 상태 변경
  # 없이 사유 안내로 거부한다).
  def resume_reminders
    return redirect_resume_refused if @client.refused?

    @client.update_column(:reminders_suspended_at, nil)
    redirect_to app_client_path(@client), status: :see_other,
                notice: "이 거래처의 자동 안내를 재개했습니다."
  end

  private

  # VIEW-7 — 수신 거부 거래처의 재개 요청 수렴. 상태 변경 없이 상세로 돌려보내고 사유를
  # 안내한다(거부 접수 안내가 뷰에 이미 있다).
  def redirect_resume_refused
    redirect_to app_client_path(@client), status: :see_other,
                alert: "이 거래처가 추가 안내 수신을 거부하여 자동 안내를 재개할 수 없습니다."
  end

  def set_client
    @client = Current.user.clients.find(params[:id])
  end

  def client_params
    params.expect(client: [ :name, :contact_name, :phone, :email, :business_number, :ceo_name, :corp_addr, :memo ]) # TAX-1 — ceo_name·corp_addr(전자세금계산서 공급받는자 정보)
  end
end

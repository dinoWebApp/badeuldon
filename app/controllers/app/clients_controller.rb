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

  def show; end

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

  # REM-7 — 거래처 단위 보류 재개. 수신거부(refused_at)는 재개 대상이 아니다(VIEW-7 — 채무자 의사).
  def resume_reminders
    @client.update_column(:reminders_suspended_at, nil)
    redirect_to app_client_path(@client), status: :see_other,
                notice: "이 거래처의 자동 안내를 재개했습니다."
  end

  private

  def set_client
    @client = Current.user.clients.find(params[:id])
  end

  def client_params
    params.expect(client: [ :name, :contact_name, :phone, :email, :business_number, :memo ])
  end
end

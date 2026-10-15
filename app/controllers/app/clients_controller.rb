# 거래처 관리(CLIENT-1) — 표면 ② 표준 CRUD. 조회·변경은 모두 Current.user.clients로 스코프해
# 타 사용자 데이터 접근을 차단하며, Free 거래처 한도(PLAN-1)는 Client 모델 검증으로 강제한다.
class App::ClientsController < App::BaseController
  before_action :set_client, only: %i[ show edit update destroy ]

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

  def destroy
    @client.destroy!
    redirect_to app_clients_path, status: :see_other, notice: "거래처가 삭제되었습니다."
  end

  private

  def set_client
    @client = Current.user.clients.find(params[:id])
  end

  def client_params
    params.expect(client: [ :name, :contact_name, :phone, :email, :business_number, :memo ])
  end
end

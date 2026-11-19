# SALES-1 — 영업 직원 관리 콘솔(T-C1 admins 콘솔 패턴). 생성·수정·정지·코드 재생성은
# staff도 허용한다(관리 업무 성격 — AUTH-7.2의 관리자 롤 승강과는 별개 영역)하되 행위 감사는
# 전건으로 기록한다(ADMIN-2). 영업 계정 삭제는 없다(P4 — 어트리뷰션·정산 이력 보존) —
# 정지(suspend)로만 운영한다. 생성 시 초기 추천 코드를 즉시 발급한다(SALES-2).
class Admin::SalesRepsController < Admin::BaseController
  before_action :set_sales_rep, only: %i[ edit update toggle_suspension rotate_code unlock ]

  def index
    @sales_reps = SalesRep.order(created_at: :asc)
    # 현재 유효 코드를 목록 표시용으로 1회 조회(N+1 방지 — rep_id 키 맵).
    @current_codes = SalesReferralCode.current_valid.order(:valid_from)
                          .index_by(&:sales_rep_id)
  end

  def new
    @sales_rep = SalesRep.new
  end

  def create
    @sales_rep = SalesRep.new(sales_rep_params)
    if @sales_rep.save
      code = Sales::RotateReferralCodesService.call(rep: @sales_rep).first
      AuditLogs::RecordService.call(admin: current_admin, action: "sales_rep_created",
                                    target: @sales_rep,
                                    detail: "#{@sales_rep.email}(#{@sales_rep.role}) · 초기 코드 #{code&.code}",
                                    ip: request.remote_ip)
      redirect_to admin_sales_reps_path, status: :see_other,
                  notice: "영업 직원이 생성되었습니다. 초기 추천 코드: #{code&.code}"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @sales_rep.update(updatable_params)
      AuditLogs::RecordService.call(admin: current_admin, action: "sales_rep_updated",
                                    target: @sales_rep,
                                    detail: "#{@sales_rep.email}(#{@sales_rep.role}) 요율 #{@sales_rep.effective_rate}%",
                                    ip: request.remote_ip)
      redirect_to admin_sales_reps_path, status: :see_other, notice: "영업 직원 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 정지·해제(상태 전이라 member PATCH). 정지 시 세션을 전부 파기한다(U1 정지 패턴 준용 —
  # SALES-7 격리 계정도 즉시 차단). 감사: sales_rep_suspended / sales_rep_resumed.
  def toggle_suspension
    target = @sales_rep.active? ? :suspended : :active
    @sales_rep.update!(status: target)
    @sales_rep.sales_rep_sessions.destroy_all if @sales_rep.suspended?
    AuditLogs::RecordService.call(admin: current_admin,
                                  action: @sales_rep.suspended? ? "sales_rep_suspended" : "sales_rep_resumed",
                                  target: @sales_rep, detail: @sales_rep.email, ip: request.remote_ip)
    redirect_to admin_sales_reps_path, status: :see_other,
                notice: (@sales_rep.suspended? ? "정지 처리했습니다(세션 파기)." : "정지를 해제했습니다.")
  end

  # W-1 — 5회 실패 잠금 계정의 콘솔 복구 경로(admins unlock 선례 준용 — SalesRep#unlock!이
  # locked_at·failed_attempts를 함께 리셋). 비밀번호 변경만으로는 잠금이 풀리지 않으므로
  # 운영자가 자력 복구 불가 계정을 해제할 수 있게 한다. 감사: sales_rep_unlocked.
  def unlock
    @sales_rep.unlock!
    AuditLogs::RecordService.call(admin: current_admin, action: "sales_rep_unlocked",
                                  target: @sales_rep, detail: @sales_rep.email,
                                  ip: request.remote_ip)
    redirect_to admin_sales_reps_path, status: :see_other, notice: "잠금을 해제했습니다."
  end

  # 수동 코드 재생성(SALES-2 — 주간 Job과 같은 서비스 재사용). 당일 이미 발급됐으면 멱등
  # 가드로 무변경(nil) — 안내로 흡수한다.
  def rotate_code
    code = Sales::RotateReferralCodesService.call(rep: @sales_rep).first
    AuditLogs::RecordService.call(admin: current_admin, action: "sales_rep_code_rotated",
                                  target: @sales_rep,
                                  detail: "#{@sales_rep.email} · #{code&.code || '당일 발급분 존재(무변경)'}",
                                  ip: request.remote_ip)
    if code
      redirect_to admin_sales_reps_path, status: :see_other, notice: "새 추천 코드: #{code.code}"
    else
      redirect_to admin_sales_reps_path, status: :see_other,
                  alert: "오늘 이미 발급된 코드가 있어 무변경했습니다(멱등)."
    end
  end

  private

  def set_sales_rep
    @sales_rep = SalesRep.find(params[:id])
  end

  # 생성용 — 비밀번호 필수(has_secure_password). role은 유효 enum 키만 할당한다(조작 입력
  # ArgumentError 방지 — admins 콘솔 C-1 패턴).
  def sales_rep_params
    attrs = params.expect(sales_rep: [ :email, :password, :name, :title, :role, :commission_rate ])
    attrs[:role] = "sales" unless SalesRep.roles.key?(attrs[:role].to_s)
    attrs
  end

  # 수정용 — 비밀번호 공백이면 변경하지 않는다(재설정은 별도 절차 없음 — 값 입력 시에만).
  def updatable_params
    attrs = sales_rep_params
    attrs.delete(:password) if attrs[:password].blank?
    attrs
  end
end

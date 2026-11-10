# ADMIN-6 운영 공지 관리(Run C) — CRUD + 발행(publish)/종료(close).
# 상태 전이는 예외적 동사라 member PATCH로 정당화(라우트 컨벤션). 발행 전 초안도 목록에
# 상태 배지(초안·게시 중·종료)로 표시한다.
class Admin::NoticesController < Admin::BaseController
  before_action :set_notice, only: %i[ edit update publish close destroy ]

  # 목록 배지 표현 로직(뷰 표현 3줄+ 이관). 모듈 헬퍼(app/helpers/admin/)는 Admin 모델 클래스와
  # 최상위 `Admin` 네임스페이스가 충돌(zeitwerk 실측)하므로 컨트롤러 helper_method로 제공한다.
  helper_method :notice_status_badge, :notice_importance_badge

  def notice_status_badge(notice)
    if notice.draft?
      [ "초안", "bg-stone-100 text-stone-500" ]
    elsif notice.live?
      [ "게시 중", "bg-green-50 text-green-700" ]
    else
      [ "종료", "bg-orange-50 text-orange-600" ]
    end
  end

  def notice_importance_badge(notice)
    notice.important? ? [ "중요", "bg-red-50 text-red-600" ] : [ "일반", "bg-emerald-50 text-emerald-700" ]
  end

  def index
    scope = Notice.order(created_at: :desc)
    scope = scope.where(importance: params[:importance]) if params[:importance].in?(%w[general important])
    @notices = scope.limit(100)
  end

  def new
    @notice = Notice.new
  end

  def create
    @notice = Notice.new(notice_params)
    if @notice.save
      redirect_to admin_notices_path, status: :see_other, notice: "공지가 저장되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @notice.update(notice_params)
      redirect_to admin_notices_path, status: :see_other, notice: "공지가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 발행 — published_at을 현재 시각(KST, TIME-1)으로 기록. 이미 발행된 공지는 무시(멱등).
  # W-3(05_review) — update 실패(ex: 만료가 이미 과거인 초안) 시 성공 플래시 대신 실패 안내.
  def publish
    if @notice.live? || @notice.update(published_at: Time.current)
      redirect_to admin_notices_path, status: :see_other, notice: "공지가 발행되었습니다."
    else
      redirect_to admin_notices_path, status: :see_other,
                  alert: "발행에 실패했습니다. #{@notice.errors.full_messages.to_sentence}"
    end
  end

  # 종료 — expires_at을 현재 시각으로 기록해 즉시 게시 중단(null=무기한을 닫는다).
  def close
    @notice.update(expires_at: Time.current) if @notice.live?
    redirect_to admin_notices_path, status: :see_other, notice: "공지가 종료되었습니다."
  end

  def destroy
    @notice.destroy
    redirect_to admin_notices_path, status: :see_other, notice: "공지가 삭제되었습니다."
  end

  private

  def set_notice
    @notice = Notice.find(params[:id])
  end

  # xxx_params — 컨벤션(params.expect + private #xxx_params)
  def notice_params
    params.expect(notice: [ :title, :body, :importance, :published_at, :expires_at ])
  end
end

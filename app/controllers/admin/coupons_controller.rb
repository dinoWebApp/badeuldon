# ADMIN-4(T-C2) — 쿠폰·프로모션 관리(Q12). 표준 CRUD + 사용 통계(used_count/max·잔여).
# 쿠폰의 소비(used_count 증가)는 결제 성공 시점의 UpgradeService가 담당하며, 이 컨트롤러는
# 쿠폰 발급·수정·중지라 관리 행위만 수행한다(Admin 행위는 아니지만 일관성 위해 감사 기록은 생략).
class Admin::CouponsController < Admin::BaseController
  # 목록 표현 로직(뷰 표현 3줄+ 이관 — notices와 동일 패턴의 helper_method).
  helper_method :coupon_discount_label

  # 할인 표시 라벨 — percent는 "20% 할인", amount는 "2,000원 할인".
  def coupon_discount_label(coupon)
    if coupon.percent?
      "#{coupon.discount_value}% 할인"
    else
      "#{ActiveSupport::NumberHelper.number_to_delimited(coupon.discount_value)}원 할인"
    end
  end

  before_action :set_coupon, only: %i[show edit update destroy]

  def index
    @coupons = Coupon.order(created_at: :desc).limit(100)
  end

  def show
  end

  def new
    @coupon = Coupon.new
  end

  def create
    @coupon = Coupon.new(coupon_params)
    if @coupon.save
      redirect_to admin_coupon_path(@coupon), status: :see_other, notice: "쿠폰이 생성되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @coupon.update(coupon_params)
      redirect_to admin_coupon_path(@coupon), status: :see_other, notice: "쿠폰이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 쿠폰 삭제 — 이미 사용된 쿠폰(used_count > 0)은 결제 이력(P4)과의 정합을 위해 삭제를 차단하고
  # 비활성화(active: false)로 대체한다. 미사용 쿠폰만 삭제를 허용한다.
  def destroy
    if @coupon.used_count.positive?
      redirect_to admin_coupons_path, status: :see_other,
                  alert: "사용 이력이 있는 쿠폰은 삭제할 수 없습니다. 비활성화로 중지해 주세요."
    elsif @coupon.destroy # W-2 — 예약 보유(subscriptions.coupon_id 참조)는 restrict_with_error로 차단
      redirect_to admin_coupons_path, status: :see_other, notice: "쿠폰이 삭제되었습니다."
    else
      redirect_back fallback_location: admin_coupons_path, status: :see_other,
                    alert: @coupon.errors.full_messages.first.presence ||
                           "사용 예정인 쿠폰은 삭제할 수 없습니다."
    end
  end

  private

  def set_coupon
    @coupon = Coupon.find(params[:id])
  end

  # xxx_params — 컨벤션(params.expect + private #xxx_params). used_count는 결제 성공 시점에만
  # 서비스가 증가하므로 관리자 편집 대상에서 제외한다(SEC-5).
  def coupon_params
    params.expect(coupon: [ :code, :name, :discount_type, :discount_value,
                            :max_redemptions, :expires_at, :active ])
  end
end

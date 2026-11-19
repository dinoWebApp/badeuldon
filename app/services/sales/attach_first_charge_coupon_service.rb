# 추천 가입 첫 결제 할인 쿠폰 자동 부착(SALES-4 — F-SALES·Q12 재사용). 신규 결제 로직은
# 1줄도 쓰지 않는다: Q12 쿠폰 인프라(percent·1회 전용·예약 → 구독 coupon_id)에 "추천 할인"
# 쿠폰을 생성해 예약만 걸어두면, 첫 Plus 차감은 기존 UpgradeService의
# resolve_first_charge_coupon! → consume_first_charge_coupon! 경로가 그대로 처리한다
# (멱등·재과금 정상가·웹훅 settle 포함). SALES-4 설정값 — percent 20·max_redemptions 1.
# 가입 트랜잭션 실패해도 가입은 완료돼야 하므로 호출부(RegistrationsController)가 rescue해
# 로그만 남긴다(쿠폰 부재는 정가 첫 결제로 안전하게 폴백).
module Sales
  class AttachFirstChargeCouponService
    DISCOUNT_PERCENT = 20
    COUPON_NAME = "추천 가입 첫 결제 할인"

    def initialize(user:)
      @user = user
    end

    def call
      return nil unless @user.subscription

      Coupon.create!(code: generate_unique_code, name: COUPON_NAME,
                     discount_type: :percent, discount_value: DISCOUNT_PERCENT,
                     max_redemptions: 1, active: true).tap do |coupon|
        @user.subscription.update!(coupon_id: coupon.id) # Q12 예약 — 첫 차감 시 1회 소비
      end
    end

    private

    # Coupon 형식(대문자 영숫자 8~16자·유니크)에 맞는 무작위 코드 — "REF"+hex 8자 = 11자.
    def generate_unique_code
      loop do
        code = "REF#{SecureRandom.hex(4).upcase}"
        return code unless Coupon.exists?(code: code)
      end
    end
  end
end

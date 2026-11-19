# 추천 코드 로테이션(SALES-2 — F-SALES). 활동 중(active) 영업 직원 전체(또는 rep 단독 —
# 관리자 콘솔 생성·수동 재생성)의 현재 코드를 종료하고 새 8자 코드를 발급한다. 주간
# recurring Job(월요일 00:00 KST)과 콘솔 수동 경로가 같은 서비스를 재사용한다.
#
# 멱등(SEC-5 준칙) — "오늘 발급된 코드가 이미 있으면 무변경" 가드로 잡 재실행·동시 실행에도
# 하루 1회만 회전한다. 기존 코드는 valid_until을 어제로 조기 종료(주간 창 종료와 동일 효과)해
# 이력 행은 보존된다(P4 — 과거 어트리뷰션 감사 근거).
module Sales
  class RotateReferralCodesService
    # 새 코드의 유효 창 — 발급일부터 6일(다음 주간 로테이션 전날까지). 표시 "만료 예정"의 근거.
    VALIDITY_DAYS = 6

    def self.call(rep: nil)
      new(rep:).call
    end

    def initialize(rep: nil)
      @rep = rep
    end

    def call
      targets = @rep ? [ @rep ] : SalesRep.active.order(:id)
      targets.filter_map { |rep| rotate(rep) }
    end

    private

    def rotate(rep)
      # 멱등 가드 — 오늘 발급분이 이미 있으면 무변경(재실행 흡수).
      return nil if rep.sales_referral_codes.exists?(valid_from: Date.current)

      ActiveRecord::Base.transaction do
        # 기존 유효 코드 조기 종료 — 어제까지 유효(=오늘 00시부터 가입 수용 불가).
        rep.sales_referral_codes.current_valid
           .where.not(valid_until: Date.current - 1.day)
           .update_all(valid_until: Date.current - 1.day) # rubocop:disable Rails/SkipsModelValidations
        rep.sales_referral_codes.create!(code: generate_unique_code,
                                         valid_from: Date.current,
                                         valid_until: Date.current + VALIDITY_DAYS)
      end
    end

    # SalesReferralCode 형식(8자·전역 유니크) 충족까지 재시도 — 유니크 인덱스 충돌 흡수.
    def generate_unique_code
      loop do
        code = SalesReferralCode.generate_code
        return code unless SalesReferralCode.exists?(code: code)
      end
    end
  end
end

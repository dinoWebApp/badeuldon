# 휴대폰 인증번호 확인(AUTH-9 — 가입 폼 2단계 비동기의 2단계). 해당 번호의 최근 발행 코드 행을
# 찾아 ① 없음 ② 만료 ③ 시도 5회 초과 ④ 불일치를 분기하고, 일치 시 consumed 마킹으로
# 1회용 소비를 보장한다. 결과는 Result(verified?·status·error) — 컨트롤러가 JSON으로 변환.
# 최종 권위 판정은 가입 create의 이중 검증(consumed_recently 행 + 번호 일치)이 다시 수행한다
# — 이 엔드포인트는 UX 피드백용이며 우회해도 가입은 차단된다.
module PhoneVerifications
  class VerifyService
    Result = Struct.new(:verified?, :status, :error, keyword_init: true)

    def initialize(phone:, code:)
      @phone = phone.to_s.gsub(/\D/, "")
      @code = code.to_s.strip
    end

    def call
      verification = PhoneVerification.where(phone: @phone).order(:created_at).last
      return Result.new(verified?: false, status: :no_request,
                        error: "인증번호 요청부터 다시 진행해 주세요") if verification.nil?
      return Result.new(verified?: false, status: :expired,
                        error: "인증번호가 만료되었습니다. 새로 요청해 주세요") if verification.expired?
      return Result.new(verified?: false, status: :attempts_exceeded,
                        error: "시도 횟수를 초과했습니다. 새로 요청해 주세요") if verification.attempts_exceeded?

      if verification.code == @code && verification.consume!
        Result.new(verified?: true, status: :verified, error: nil)
      else
        verification.record_attempt!
        Result.new(verified?: false, status: :mismatch,
                   error: "인증번호가 올바르지 않습니다")
      end
    end
  end
end

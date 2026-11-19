# 휴대폰 인증번호 발송(AUTH-9 — 가입 폼 2단계 비동기의 1단계). 정규화(하이픈 제거)·
# 형식 검증(휴대폰 국번)·rate limit(번호당 최근 1분 1회·1시간 3회 — AUTH-9 명시)를 통과한
# 요청만 6자리 코드를 발급해 PhoneVerification으로 기록(P4)하고 발송한다. 2026-11-19 전환 —
# 알림톡 우선(템플릿 phone_verification)이며, credentials solapi.template_ids에 키 부재 시
# (템플릿 등록 전 임시) 기존 SMS 경로로 발송한다(NOTI-3 선례 — 등록 공백기 가입 무중단).
# 알림톡 템플릿 등록 문구: 「[받을돈] 가입 인증번호는 [#{인증번호}]입니다. 5분간 유효합니다.」
# — 변수명 "인증번호" 고정(아래 deliver!의 variables 키와 일치 필수).
# client 주입 지점(테스트 stub 방어선 — 실호출 금지 제약)은 Reminders·Noti 서비스와 같은
# 패턴이다. 결과는 Result 구조체(성공·안내 문구·마스킹 번호)로 돌려 컨트롤러가 JSON 응답으로
# 변환한다.
module PhoneVerifications
  class SendService
    # AUTH-9 — 발송 rate limit(번호당). 판정 근거는 phone_verifications 발송 이력 행.
    RATE_LIMIT_PER_MINUTE = 1
    RATE_LIMIT_PER_HOUR = 3
    # 알림톡 템플릿 키 — credentials solapi.template_ids의 키와 동일 문자열.
    TEMPLATE_KEY = "phone_verification"

    Result = Struct.new(:success?, :error, :masked_phone, keyword_init: true)

    def initialize(phone:, client: Solapi::ClientService.new)
      @phone = phone.to_s.gsub(/\D/, "")
      @client = client
    end

    def call
      return failure("올바른 휴대폰 번호를 입력해 주세요") unless valid_format?
      return failure("인증 요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요") if rate_limited?

      code = SecureRandom.random_number(1_000_000).to_s.rjust(PhoneVerification::CODE_DIGITS, "0")
      verification = PhoneVerification.create!(phone: @phone, code:,
                                               expires_at: PhoneVerification::CODE_TTL.from_now)
      deliver!(code)
      Result.new(success?: true, error: nil, masked_phone: masked_phone)
    rescue Solapi::ApiError => e
      Rails.logger.error("[PhoneVerifications::SendService] phone=#{masked_phone} #{e.class}: #{e.message}")
      # 발송 실패한 요청은 rate limit 판정에서 제외하기 위해 방금 기록한 행을 제거한다 —
      # 실패 재시도가 "3회/시간" 소진으로 이어지지 않게 한다(사용자 원인 아님).
      verification&.destroy
      failure("인증번호 발송에 실패했습니다. 잠시 후 다시 시도해 주세요")
    end

    private

    # 휴대폰 형식(국번 01x·가입자번호 7~8자리) — 정규화 후 숫자만 기준.
    def valid_format?
      @phone.match?(/\A01[016789]\d{7,8}\z/)
    end

    def rate_limited?
      return true if PhoneVerification.sent_within(1.minute).where(phone: @phone).exists?

      PhoneVerification.sent_within(1.hour).where(phone: @phone).count >= RATE_LIMIT_PER_HOUR
    end

    # 발송 분기(AUTH-9 — 2026-11-19 알림톡 전환). credentials solapi.template_ids에
    # phone_verification 키가 있으면 알림톡을 시도하고, 솔라피 API가 요청 자체를 거부하는
    # 경우(템플릿 검수중·미승인 — 대체문자도 미발동) SMS 코드 폴백으로 가입을 무중단 유지
    # 한다. 승인 후 정상 발송에서는 폴백이 발동하지 않으므로 이중발송은 없다. 키 부재 시
    # (템플릿 등록 전 임시) 기존 SMS 경로로 발송한다(NOTI-3 선례). 최종 실패(알림톡·SMS
    # 모두 실패)는 상위 rescue(Solapi::ApiError → 행 destroy·rate limit 미소진)로 흡수된다.
    def deliver!(code)
      if @client.template_ids.key?(TEMPLATE_KEY)
        begin
          @client.send_alimtalk(template_key: TEMPLATE_KEY, to: @phone,
                                variables: { "인증번호" => code })
        rescue Solapi::ApiError
          # 검수중 가입 무중단 — 알림톡 거부(미승인 등) 시 SMS로 폴백한다.
          @client.send_sms(to: @phone, body: verification_message(code))
        end
      else
        @client.send_sms(to: @phone, body: verification_message(code))
      end
    end

    def verification_message(code)
      "[받을돈] 휴대폰 인증번호는 [#{code}]입니다. #{PhoneVerification::CODE_TTL / 60}분 이내에 입력해 주세요."
    end

    # 응답·로그용 마스킹 — 가운데 4자리 가리기(개인정보 최소 노출).
    def masked_phone
      return @phone if @phone.length < 7

      "#{@phone[0, 3]}****#{@phone[-4, 4]}"
    end

    def failure(message)
      Result.new(success?: false, error: message, masked_phone: nil)
    end
  end
end

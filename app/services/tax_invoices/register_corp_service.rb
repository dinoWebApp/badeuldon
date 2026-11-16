# TAX-1 발행 설정 1단계 — U1 사업자 정보 저장 + 바로빌 회원사 가입(RegistCorp). 바로빌 아이디는
# 받을돈이 채번한다("bd" + user_id 18자리 0패딩 = 20자 — RegistCorp ID 규격 6~20자·결정적이라
# 재호출 시에도 동일 아이디가 된다). 비밀번호는 바로빌 회원 계정용이지만 GetBaroBillURL이
# PWD를 더 이상 요구하지 않으므로(빈 문자열 허용 — /tmp/barobill_common.txt) 로그인 용도가
# 없는 난수로 채번 후 보존하지 않는다(분실 시 바로빌 사이트에서 재설정 — 설정 화면 안내).
# -32000(이미 가입된 회원사)은 정상 시나리오로 흡수해 정보 저장을 계속한다(/tmp/barobill_join.txt).
module TaxInvoices
  class RegisterCorpService
    BAROBILL_ID_PREFIX = "bd"
    BAROBILL_ID_LENGTH = 20

    # user: 저장 대상(스칼라 아님 — 폼 업데이트 대상 AR), attributes: 사업자 정보 해시.
    # client: BaroBill::ClientService(기본 생성 — 테스트 stub 주입 지점).
    def initialize(user:, attributes:, client: BaroBill::ClientService.new)
      @user = user
      @attributes = attributes
      @client = client
    end

    # 성공 시 true. 실패는 false + user.errors(컨트롤러가 422 재렌더 — 규약 응답 전략).
    def call
      return false unless validate_input

      @user.assign_attributes(normalized_attributes)
      @user.barobill_id ||= generate_barobill_id
      return false unless validate_locally

      return false unless register_with_barobill

      @user.save!
      true
    end

    private

    # Phase 6 W-3 — 외부 호출·enum 할당 이전의 입력 하드닝. 조작된 tax_type 임의값은 enum
    # 할당 시 ArgumentError(500)가 되므로 화이트리스트로 선검증해 422로 수렴시킨다.
    def validate_input
      tax_type = @attributes[:tax_type].to_s.presence
      if tax_type && !User.tax_types.key?(tax_type)
        @user.errors.add(:tax_type, :invalid)
        return false
      end

      true
    end

    # 하이픈 제외 정규화(corp_num은 바로빌 CorpNum 규격 — 10자리 숫자만). 표시 계열은 strip.
    def normalized_attributes
      attrs = @attributes.slice(:corp_num, :corp_name, :ceo_name, :corp_addr, :contact_name, :phone, :tax_type)
      attrs[:corp_num] = attrs[:corp_num].to_s.gsub(/\D/, "").presence if attrs[:corp_num]
      attrs
    end

    def validate_locally
      # 사업자번호·연락처는 RegistCorp 전제라 필수 — 나머지는 RegistCorp 파라미터 필수 세트와 정합.
      required = %i[corp_num corp_name ceo_name corp_addr contact_name phone]
      missing = required.select { |key| @user.public_send(key).blank? }
      missing.each { |key| @user.errors.add(key, :blank) }
      validate_corp_num_format
      missing.empty? && @user.errors.none?
    end

    # Phase 6 W-3 — RegistCorp 외부 호출 전에 corp_num 포맷(10자리 숫자)을 검증해
    # RecordInvalid 500 여지를 제거한다.
    def validate_corp_num_format
      return if @user.corp_num.blank? || @user.corp_num.match?(/\A\d{10}\z/)

      @user.errors.add(:corp_num, "은(는) 하이픈 없이 10자리 숫자로 입력해 주세요")
    end

    def register_with_barobill
      @client.register_corp(
        corp_num: @user.corp_num, corp_name: @user.corp_name, ceo_name: @user.ceo_name,
        # 업태·업종은 RegistCorp 필수 — 받을돈이 보유하지 않는 정보라 기본값 구성으로 채운다.
        biz_type: "서비스", biz_class: "프리랜서 서비스", addr1: @user.corp_addr,
        member_name: @user.contact_name, barobill_id: @user.barobill_id,
        barobill_pwd: SecureRandom.alphanumeric(16), tel: @user.phone,
        email: @user.email
      )
      true
    rescue BaroBill::ClientService::ApiError => e
      if e.code == BaroBill::ClientService::ALREADY_MEMBER_CODE
        Rails.logger.info("[TAX-1] RegistCorp -32000 — 기가입 회원사, 설정 저장만 진행: #{@user.id}")
        return true
      end

      @user.errors.add(:base, "바로빌 회원사 가입에 실패했습니다(오류코드 #{e.code}). 잠시 후 다시 시도해 주세요.")
      false
    end

    def generate_barobill_id
      format("#{BAROBILL_ID_PREFIX}%0#{BAROBILL_ID_LENGTH - BAROBILL_ID_PREFIX.length}d", @user.id)
    end
  end
end

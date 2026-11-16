# 바로빌(전자세금계산서·공통) SOAP API 래퍼(TAX-1 — §6.19 EXT-1 지정사 (주)케이넷). 솔라피
# 래퍼(Solapi::ClientService)와 같은 패턴 — credentials 기본값 + 초기화 인자 주입 + fail-fast +
# ActiveRecord 비의존 순수 클래스라 테스트에서 stub 주입이 가능하다. savon(WSDL 기반 SOAP)으로
# 호출하며, 개발·테스트에서 실수로 호출되지 않게 client Factory를 주입 가능하게 뒀다.
#
# 엔드포인트(공식 문서 2026-11 확인 — /tmp/barobill_common.txt·barobill_ti.txt):
#   TESTBED  https://testws.baroservice.com/{TI,CORPSTATE}.asmx?WSDL
#   RELEASE  https://ws.baroservice.com/...
#   공통 API는 전용 asmx가 없고 각 서비스 asmx에 포함된다(2026-11-16 TESTBED 실측 —
#   BAROBILL.asmx는 404·TI/CORPSTATE 양쪽 WSDL에서 공통 오퍼레이션 14회씩 검출).
#   공통 호출은 TI.asmx를 사용한다.
#
# 응답 규격: int 반환 API는 XML 요소 {메서드명}Result에 정수(1 성공·음수 실패), URL 반환은
# 문자열(실패는 음수 문자열), 상태 조회는 구조체(TaxInvoiceStateEX·CorpStateEX)로 온다.
# 오류 시 BaroBill::ClientService::ApiError(code: 음수 코드·message)로 정규화한다 — fail-fast.
require "savon"

module BaroBill
  class ClientService
    # 오류 정규화 — code는 바로빌 음수 오류코드(문자열 보관), message는 개발자센터 오류코드표 근거.
    ApiError = Class.new(StandardError) do
      attr_reader :code

      def initialize(code:, message:)
        @code = code
        super(message)
      end
    end

    TEST_HOST = "https://testws.baroservice.com"
    RELEASE_HOST = "https://ws.baroservice.com"
    TIMEOUT_SECONDS = 15
    CERT_REGISTER_TOGO = "CERT" # GetBaroBillURL TOGO 코드 — 공동인증서 등록 팝업(/tmp/barobill_cert.txt)
    # -32000 — 이미 가입된 회원사(/tmp/barobill_join.txt 프로세스: 가입 여부 확인 후 RegistCorp,
    # -32000 재호출은 정상 시나리오로 흡수 — RegisterCorpService가 이 상수로 판정).
    ALREADY_MEMBER_CODE = "-32000"

    # credentials 키(:barobill)는 02_prd_update 이전에 사용자 등록 완료(2026-11-13 Phase 2).
    # release 판정: 운영 환경 + release_auth_key 등록 시 RELEASE 엔드포인트·키 사용 — TESTBED가
    # 기본이며(코드 완성 기준·운영 전환은 계약 후) 명시적 인자 override가 최우선이다.
    def initialize(auth_key: default_auth_key, release: release_mode?,
                   savon_factory: ->(wsdl) { Savon.client(wsdl:, convert_request_keys_to: :none,
                                                          open_timeout: TIMEOUT_SECONDS,
                                                          read_timeout: TIMEOUT_SECONDS, log: false) })
      @auth_key = auth_key
      @release = release
      @savon_factory = savon_factory
    end

    # ── 회원사 가입(공통 API RegistCorp) ────────────────────────────────────
    # 성공 1·음수 실패. -32000(이미 가입)은 ApiError로 올리되 code로 판정해 상위에서 흡수한다.
    def register_corp(corp_num:, corp_name:, ceo_name:, biz_type:, biz_class:, addr1:,
                      member_name:, barobill_id:, barobill_pwd:, tel:, email:)
      call_common(:regist_corp, CERTKEY: @auth_key, CorpNum: corp_num, CorpName: corp_name,
                  CEOName: ceo_name, BizType: biz_type, BizClass: biz_class,
                  # PostNum·JuminNum은 더 이상 사용되지 않는 항목 — 문서 지시대로 빈 문자열.
                  PostNum: "", Addr1: addr1, Addr2: "", MemberName: member_name, JuminNum: "",
                  ID: barobill_id, PWD: barobill_pwd, Grade: "", TEL: tel, HP: "", Email: email)
    end

    # ── 공동인증서 등록 URL(공통 API GetBaroBillURL · TOGO="CERT") ──────────
    # URL은 60초 유효(/tmp/barobill_common.txt) — 반환 직후 화면 안내용으로만 쓴다.
    def certificate_register_url(corp_num:, barobill_id:)
      call_common_returning_url(:get_baro_bill_url, CERTKEY: @auth_key, CorpNum: corp_num,
                                ID: barobill_id, PWD: "", TOGO: CERT_REGISTER_TOGO)
    end

    # ── 공동인증서 유효성 검증(공통 API CheckCERTIsValid) ───────────────────
    # 1=유효, 음수=미등록·오류. App::TaxInvoiceSettingsController#confirm_certificate가
    # "등록 완료" 판정의 실시간 근거로 사용한다(문서에 전용 등록완료 콜백은 없다 — 런 리스크 #1).
    def check_cert_is_valid(corp_num:)
      call_common(:check_cert_is_valid, CERTKEY: @auth_key, CorpNum: corp_num) == 1
    end

    # ── 휴폐업 조회(사업자등록 상태조회 API GetCorpStateEx) ─────────────────
    # CorpStateEX.State: 1 계속사업자·2 휴업·3 폐업(양수) / 음수 오류. IssueService가 폐업(3)을
    # 발행 차단 근거로 쓴다. [INFERENCE] 상태 코드 3종 구분은 바로빌 표준 휴폐업 코드 관행.
    def get_corp_state(corp_num:, check_corp_num:)
      response = call_corpstate_raw(:get_corp_state_ex, CERTKEY: @auth_key, CorpNum: corp_num,
                                    CheckCorpNum: check_corp_num)
      struct = response.body.dig(:get_corp_state_ex_response, :get_corp_state_ex_result) || {}
      state = struct[:state]
      raise ApiError.new(code: state.to_s, message: "휴폐업 조회 실패(코드 #{state})") if state.to_i.negative?

      { state: state.to_i, corp_name: struct[:corp_name], type_of_business: struct[:type_of_business] }
    end

    # ── 세금계산서 저장+발급(TI API RegistAndIssueTaxInvoice) ───────────────
    # invoice_hash는 TaxInvoice 구조체 규격(TaxInvoice·InvoiceParty·TaxInvoiceTradeLineItem —
    # 구성은 TaxInvoices::IssueService 책임, 래퍼는 전송만). 성공 1·음수 실패.
    def regist_and_issue_tax_invoice(corp_num:, invoice:)
      call_ti(:regist_and_issue_tax_invoice, CERTKEY: @auth_key, CorpNum: corp_num,
              Invoice: invoice, SendSMS: false, ForceIssue: false, MailTitle: "")
    end

    # ── 세금계산서 상태 조회(TI API GetTaxInvoiceStateEX) ───────────────────
    # 정발행 건 조회 주체는 공급자 사업자번호. NTSSendKey(국세청 승인번호 — TAX-2)를 포함한다.
    def get_tax_invoice_state(corp_num:, mgt_num:)
      response = call_ti_raw(:get_tax_invoice_state_ex, CERTKEY: @auth_key, CorpNum: corp_num,
                             MgtKey: mgt_num)
      struct = response.body.dig(:get_tax_invoice_state_ex_response, :get_tax_invoice_state_ex_result) || {}
      state = struct[:barobill_state]
      raise ApiError.new(code: state.to_s, message: "세금계산서 상태 조회 실패(코드 #{state})") if state.to_i.negative?

      struct
    end

    # ── 발급 취소(TI API ProcTaxInvoice · ProcType="ISSUE_CANCEL") ─────────
    # 발급완료 세금계산서 취소는 국세청 전송 전에만 가능하다(문서 — 취소 실패는 명확한 예외로).
    def cancel_tax_invoice(corp_num:, mgt_num:, memo: "")
      call_ti(:proc_tax_invoice, CERTKEY: @auth_key, CorpNum: corp_num, MgtKey: mgt_num,
              ProcType: "ISSUE_CANCEL", Memo: memo)
    end

    private

    def default_auth_key
      Rails.application.credentials.dig(:barobill, :test_auth_key)
    end

    def release_mode?
      Rails.env.production? && Rails.application.credentials.dig(:barobill, :release_auth_key).present?
    end

    def release_auth_key
      Rails.application.credentials.dig(:barobill, :release_auth_key)
    end

    def wsdl(service)
      "#{@release ? RELEASE_HOST : TEST_HOST}/#{service}.asmx?WSDL"
    end

    # int 결과 정규화 — {메서드}Result 정수. 음수는 오류코드로 ApiError(fail-fast — 상위에서
    # 특정 코드(-32000 등)만 선별 흡수한다).
    def call_common(method, message)
      result = soap_result(wsdl("TI"), method, message)
      raise_api_error!(method, result) if result.to_i.negative?
      result.to_i
    end

    def call_ti(method, message)
      result = soap_result(wsdl("TI"), method, message)
      raise_api_error!(method, result) if result.to_i.negative?
      result.to_i
    end

    def call_common_returning_url(method, message)
      raw = soap_result(wsdl("TI"), method, message)
      value = raw.to_s
      raise_api_error!(method, value) if value.match?(/\A-\d+\z/)
      value
    end

    def call_corpstate_raw(method, message)
      client(wsdl("CORPSTATE")).call(method, message:)
    rescue Savon::Error => e
      raise ApiError.new(code: "SOAP", message: "#{method} 호출 실패: #{e.message}")
    end

    def call_ti_raw(method, message)
      client(wsdl("TI")).call(method, message:)
    rescue Savon::Error => e
      raise ApiError.new(code: "SOAP", message: "#{method} 호출 실패: #{e.message}")
    end

    def soap_result(service_wsdl, method, message)
      response = client(service_wsdl).call(method, message:)
      response.body[:"#{method}_response"][:"#{method}_result"]
    rescue Savon::Error => e
      raise ApiError.new(code: "SOAP", message: "#{method} 호출 실패: #{e.message}")
    end

    def raise_api_error!(method, code)
      raise ApiError.new(code: code.to_s, message: "#{method} 실패 — 바로빌 오류코드 #{code}")
    end

    def client(service_wsdl)
      @clients ||= {}
      @clients[service_wsdl] ||= @savon_factory.call(service_wsdl)
    end
  end
end

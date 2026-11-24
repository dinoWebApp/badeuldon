# TAX-1 발행 설정(/app/tax_invoice_setting) — 2단계 온보딩. ① 사업자 정보 저장(=바로빌
# RegistCorp — TaxInvoices::RegisterCorpService) ② 공동인증서 등록(GetBaroBillURL CERT 팝업
# URL 안내 + 등록 완료 자체 갱신). "등록 완료" 판정은 CheckCERTIsValid 실시간 조회로 수행한다
# — 바로빌에 등록완료 콜백·전용 상태조회 화면 API가 없어(/tmp/barobill_cert.txt·공통 API 문서
# 재조사 결과 — 런 리스크 #1) 사용자가 팝업 등록 후 버튼으로 완료를 확정하는 방식이며, 유효성
# 검증 API로 오표시를 방지한다(조회 실패 시 마킹하지 않고 재시도를 안내).
class App::TaxInvoiceSettingsController < App::BaseController
  include TaxInvoiceGate

  # TAX-4 — 운영 준비 게이트(기본 꺼짐): 설정 플로우 전 액션을 직접 URL 접속에서 차단해
  # 대시보드로 되돌린다(사이드바 메뉴도 함께 비노출 — App::BaseHelper).
  # 구현은 TaxInvoiceGate concern(리뷰 W-2 — 발행 컨트롤러와 단일 출처).
  before_action :require_tax_invoice_feature
  # TAX-3 — 과세 유형 자격 컨텍스트(뷰의 모델 메서드 호출 금지 — @변수로 공급). update
  # 실패 시 :show 재렌더(422)에서도 같은 @변수가 필요하므로 함께 적재한다.
  before_action :set_tax_type_context, only: %i[ show update ]

  def show; end

  def update
    @saved = TaxInvoices::RegisterCorpService.new(
      user: Current.user,
      attributes: tax_invoice_setting_params.to_hash.symbolize_keys  # W-3 — params 직접 주입 금지(규약 §4.2)
    ).call

    if @saved
      redirect_to app_tax_invoice_setting_path, status: :see_other, notice: saved_notice
    else
      render :show, status: :unprocessable_entity
    end
  end

  # 인증서 등록 팝업 URL(GetBaroBillURL CERT — 60초 유효)을 안내 화면으로 렌더한다.
  def register_certificate
    unless Current.user.barobill_id.present?
      redirect_to app_tax_invoice_setting_path, status: :see_other,
                  alert: "먼저 사업자 정보를 저장해 주세요."
      return
    end

    @cert_url = BaroBill::ClientService.new.certificate_register_url(
      corp_num: Current.user.corp_num, barobill_id: Current.user.barobill_id
    )
  rescue BaroBill::ClientService::ApiError => e
    redirect_to app_tax_invoice_setting_path, status: :see_other,
                alert: "인증서 등록 URL 발급에 실패했습니다(오류코드 #{e.code}). 잠시 후 다시 시도해 주세요."
  end

  # 등록 완료 자체 갱신 — CheckCERTIsValid로 실제 등록 여부를 검증한 뒤 마킹한다.
  def confirm_certificate
    valid = BaroBill::ClientService.new.check_cert_is_valid(corp_num: Current.user.corp_num)

    if valid
      Current.user.update!(barobill_cert_registered: true)
      redirect_to app_tax_invoice_setting_path, status: :see_other,
                  notice: certificate_confirmed_notice
    else
      redirect_to register_certificate_app_tax_invoice_setting_path, status: :see_other,
                  alert: "아직 인증서가 확인되지 않았습니다. 팝업에서 등록을 완료한 뒤 다시 시도해 주세요."
    end
  rescue BaroBill::ClientService::ApiError => e
    redirect_to register_certificate_app_tax_invoice_setting_path, status: :see_other,
                alert: "인증서 상태 확인에 실패했습니다(오류코드 #{e.code}). 잠시 후 다시 시도해 주세요."
  end

  private

  # TAX-3(리뷰 W-3) — 저장 성공 안내는 자격에 따른다. 부적격(간이과세·면세사업자) 사용자에게
  # "다음으로 공동인증서를 등록해 주세요"는 등록해도 발행되지 않으므로 사실이 아니다 —
  # 단일 출처 발급 불가 문구(User#tax_invoice_ineligibility_notice)를 이어 붙인다.
  def saved_notice
    if Current.user.tax_invoice_eligible?
      "사업자 정보가 저장되었습니다. 다음으로 공동인증서를 등록해 주세요."
    else
      "사업자 정보가 저장되었습니다. #{Current.user.tax_invoice_ineligibility_notice}"
    end
  end

  # TAX-3 — 저장된 과세 유형이 간이과세·면세사업자면 설정 화면에 발급 불가 안내를 보인다.
  # 저장 자체는 막지 않는다(바로빌 회원 등록에 쓰는 실제 사업자 정보 — 발행만 차단, Q25).
  def set_tax_type_context
    @tax_type_ineligible = !Current.user.tax_invoice_eligible?
    @tax_type_notice = @tax_type_ineligible ? Current.user.tax_invoice_ineligibility_notice : nil
  end

  # TAX-3 — 등록 완료 안내는 자격에 따라 다르다. 부적격 사용자에게 "이제 발행할 수 있습니다"는
  # 사실이 아니므로 단일 출처 문구(User#tax_invoice_ineligibility_notice)로 대체한다.
  def certificate_confirmed_notice
    if Current.user.tax_invoice_eligible?
      "공동인증서 등록이 확인되었습니다. 이제 전자세금계산서를 발행할 수 있습니다."
    else
      "공동인증서 등록이 확인되었습니다. #{Current.user.tax_invoice_ineligibility_notice}"
    end
  end

  def tax_invoice_setting_params
    params.expect(tax_invoice_setting: %i[corp_num corp_name ceo_name corp_addr contact_name phone tax_type])
  end
end

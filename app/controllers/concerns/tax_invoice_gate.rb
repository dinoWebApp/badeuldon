# TAX-3/4 — 전자세금계산서 발행 진입 게이트 공용 관심사(리뷰 W-2 — 두 컨트롤러에 복제된
# require_tax_invoice_feature의 단일 출처). 대상: App::TaxInvoicesController(발행 진입)·
# App::TaxInvoiceSettingsController(설정 플로우). RemindersContext 선례의 컨트롤러 concern.
module TaxInvoiceGate
  extend ActiveSupport::Concern

  private

  # TAX-4 — 운영 준비 게이트(Q26 — 기본 꺼짐·fail-closed). 기능이 꺼진 동안 발행·설정
  # 진입을 대시보드로 되돌린다. 문구는 TaxInvoice::FEATURE_DISABLED_NOTICE 단일 출처.
  def require_tax_invoice_feature
    return if TaxInvoice.feature_enabled?

    redirect_to app_root_path, status: :see_other, alert: TaxInvoice::FEATURE_DISABLED_NOTICE
  end

  # TAX-3/4(리뷰 C-2) — 미결제(pending) 주문의 결제 진입 차단 판정. pending 주문의 상세
  # 화면은 결제 화면이기도 하므로, 꺼짐·부적격이면 결제 위젯 대신 이 안내를 그린다.
  # 꺼짐이 우선하고, 조회 자체는 200으로 유지한다(TAX-4 ④ — paid 주문의 조회·취소는 허용).
  def tax_invoice_payment_block_notice
    return TaxInvoice::FEATURE_DISABLED_NOTICE unless TaxInvoice.feature_enabled?
    return Current.user.tax_invoice_ineligibility_notice unless Current.user.tax_invoice_eligible?

    nil
  end
end

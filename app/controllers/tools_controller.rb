# 무료 도구 3종(LP-11 — /tools 허브). 가입·로그인 없이 동작(P3)·입력은 GET params만 —
# 세션·쿠키·DB 저장 일절 없음. 색인 허용(SURF-3 예외 — NOINDEX_PATH_PREFIXES 미포함).
# Routes(3-S 결선 계약): GET /tools, /tools/reminder-generator, /tools/tax-calculator,
# /tools/invoice-template, /tools/invoice-template.pdf
class ToolsController < ApplicationController
  include AllowAllBrowsers
  allow_unauthenticated_access

  layout "tools"

  def index
  end

  # 독촉 문구 생성기 — 폼+결과 동일 페이지(GET params). ToolsController 톤 미선택 → 정중 기본.
  def reminder_generator
    @tone = params[:tone]
    @client_name = params[:client_name]
    @amount = params[:amount]
    @due_date = params[:due_date]
    @messages = Tools::ReminderTextLibrary.messages(
      tone: @tone, client_name: @client_name, amount: @amount, due_date: @due_date
    )
  end

  # 3.3% 계산기 — 폼+결과 동일 페이지(GET params, 공유 URL 가능).
  def tax_calculator
    @amount_raw = params[:amount]
    @vat_included = params[:vat_included]
    @result = Tools::TaxCalculatorService.call(amount_raw: @amount_raw, vat_included: @vat_included)
  rescue Tools::TaxCalculatorService::InvalidAmount => e
    @calculation_error = e.message unless @amount_raw.blank?
    @result = nil
  end

  # 청구서 양식 PDF — 입력 폼 페이지.
  def invoice_template
  end

  # 청구서 양식 PDF 생성·다운로드(send_data). 저장 없음.
  def invoice_template_pdf
    pdf = Tools::TemplatePdfService.call(
      client_name: params[:client_name], item_name: params[:item_name],
      quantity: params[:quantity], unit_price: params[:unit_price]
    )
    send_data pdf, filename: "청구서양식.pdf", type: "application/pdf", disposition: "attachment"
  end
end

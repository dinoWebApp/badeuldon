# 표면 ② 대시보드 — DASH-1 요약 실데이터, DASH-4 목록(연체일 내림차순 상위 N),
# ONB-1 CTA. 집계는 Invoice 스코프 조합으로 컨트롤러에서 산출하고 뷰는 @변수만 소비한다.
class App::DashboardsController < App::BaseController
  DASHBOARD_LIST_COUNT = 5

  def show
    @user = Current.user
    invoices = @user.invoices

    @has_invoices = invoices.exists?
    @unsettled_total = invoices.unsettled.sum(:total_amount)                 # DASH-1 미수 총액
    overdue_scope = invoices.overdue                                         # DASH-1 연체(파생 판정)
    @overdue_count = overdue_scope.count
    @overdue_total = overdue_scope.sum(:total_amount)
    @due_soon_count = invoices.due_within(Date.current..Date.current + 7).count  # 7일 내 만기
    @invoices = invoices.includes(:client).sorted_by_due.limit(DASHBOARD_LIST_COUNT)  # DASH-4
    load_action_items(invoices)  # DASH-2 — 마감 대기·답변 대기(F-PROMISE 첫 실데이터)
  end

  private

  # DASH-2 — 오늘의 액션: ① 마감 대기 = 입금 완료 회신(PROMISE-7)이 접수된 미마감 청구
  # ( unsettled — 수금 마감은 PAY에서 U1 확인으로만 ), ② 답변 대기 = 무답변 문의(PROMISE-6).
  # REM 이벤트(발송 예정 등)는 F-REM 구현 전까지 비표시다.
  def load_action_items(invoices)
    @closure_awaiting_invoices = invoices.unsettled
      .where(id: Promise.paid_report.select(:invoice_id))
      .includes(:client).sorted_by_due
    @awaiting_answer_inquiries = Promise.inquiry.unanswered
      .where(invoice_id: invoices.select(:id))
      .includes(invoice: :client).order(created_at: :desc, id: :desc)
  end
end

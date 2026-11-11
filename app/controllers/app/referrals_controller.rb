# REF(추심 상담 소개) — REF-1~4·P5. 소개 화면 제공만이 목적인 단일 index 액션이며,
# 받을돈은 채권 수임·중개 행위를 수행하지 않는다(P5). D+30 도달·미수 청구만 모집합으로
# 하며(REF-1 — Inv#unsettled && due_on+30 < 오늘), 조회는 Current.user.invoices로
# 스코프해 소유권을 격리한다. 제휴사 데이터는 미계약 상태로 화면 고지(REF-2/3/4)만 수행한다.
class App::ReferralsController < App::BaseController
  def index
    @referral_invoices = Current.user.invoices
                                     .unsettled
                                     .where(due_on: ...Date.current - 30)
                                     .includes(:client)
                                     .sorted_by_due
  end
end

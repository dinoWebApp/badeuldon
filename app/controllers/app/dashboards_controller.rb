# 표면 ② 대시보드 — /app 진입 셸. DASH-1 요약·DASH-2 오늘의 액션·DASH-4 목록은
# F-INV·F-CLIENT 데이터 확보 전까지 빈 상태 안내로 렌더링한다(거짓 수치 금지 — 02_prd_update 결정).
class App::DashboardsController < App::BaseController
  def show
    @user = Current.user
  end
end

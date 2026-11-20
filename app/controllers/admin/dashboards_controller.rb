# 관리자 운영 대시보드(ADMIN-1·5) — Run B: 쿼리 오브젝트 5종으로 실데이터 지표 확장.
# 컨트롤러는 호출 위임만(규약 §3.2 — 집계는 app/queries/admins/ 소관, 뷰는 @변수만 소비).
# T4(2026-11-20): 솔라피 잔액(ADMIN-5·REM-10) 추가 — 래퍼 호출·캐시만 담당, 표현은 헬퍼.
class Admin::DashboardsController < Admin::BaseController
  # 성공 캐시 5분 — 대시보드 새로고침 폭주 시 외부 API 호출을 절제한다(읽기 전용 조회지만
  # 호출 절제는 지연·한도 측면에서도 기본). 실패 캐시 1분 — 장애 중 재시도 폭주를 막되
  # 복구 지연은 최소화한다(실패는 nil로 뷰에 건네 "일시 조회 불가" 표시 — 캐시 미기록이
  # 아니라 단기 기록이라 병렬 요청 전부가 타임아웃까지 대기하는 낙수를 방지).
  SOLAPI_BALANCE_CACHE_KEY = "admin/dashboards/solapi_balance"
  BALANCE_CACHE_TTL = 5.minutes
  BALANCE_FAILURE_CACHE_TTL = 1.minute
  # 실패 센티널 — 캐시 없음(nil)·조회 실패를 구분한다.
  BALANCE_UNAVAILABLE = :unavailable

  def show
    load_metrics
  end

  private

  def load_metrics
    @user_count = User.count
    @unsettled_invoice_count = Invoice.unsettled.count
    @today_message_count = MessageLog.sent.where(created_at: Time.current.all_day).count
    @signup_stats = Admins::SignupStatsQuery.call
    @collection_stats = Admins::CollectionStatsQuery.call
    @plan_funnel = Admins::PlanFunnelQuery.call
    @message_stats = Admins::MessageStatsQuery.call
    @revenue_stats = Admins::RevenueStatsQuery.call
    @solapi_balance = load_solapi_balance
  end

  def load_solapi_balance
    cached = Rails.cache.read(SOLAPI_BALANCE_CACHE_KEY)
    return nil if cached == BALANCE_UNAVAILABLE
    return cached if cached

    Solapi::ClientService.new.get_balance.tap do |balance|
      Rails.cache.write(SOLAPI_BALANCE_CACHE_KEY, balance, expires_in: BALANCE_CACHE_TTL)
    end
  rescue Solapi::ApiError => e
    Rails.logger.warn("[ADMIN-5] 솔라피 잔액 조회 실패 code=#{e.code} message=#{e.message}")
    Rails.cache.write(SOLAPI_BALANCE_CACHE_KEY, BALANCE_UNAVAILABLE,
                      expires_in: BALANCE_FAILURE_CACHE_TTL)
    nil
  end
end

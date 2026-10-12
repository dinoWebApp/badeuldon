# 표면 ① 랜딩(SURF-1) — 비로그인 공개 표면이므로 인증을 요구하지 않는다(공개 예외 선언).
# LP-1~8·10 전체 구성 — 정적 마크업(뷰만 렌더)으로 모델·서비스 의존 없음(SURF-6 경량 렌더링).
class LandingController < ApplicationController
  allow_unauthenticated_access

  # 표면 ① 전용 레이아웃 — 상단 바·LP-10 푸터 포함, 앱 자원·내비 미포함(SURF-6 예산 분리)
  layout "landing"

  def index
    # 뷰 렌더용 빈 액션
  end
end

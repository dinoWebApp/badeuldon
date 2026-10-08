# 표면 ① 랜딩(SURF-1) — 비로그인 공개 표면이므로 인증 before_action을 두지 않는다.
# LP-1 히어로는 정적 마크업(뷰만 렌더) — 모델·서비스 의존 없음(SURF-6 경량 렌더링).
class LandingController < ApplicationController
  def index
    # 뷰 렌더용 빈 액션
  end
end

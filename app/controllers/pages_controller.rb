# 공개 법적 고지 페이지 — 이용약관(/terms)·환불 정책(/refund)·개인정보처리방침(/privacy).
# PG(PortOne/KG이니시스) 심사 요건 충족용 정적 문서로, 모델·서비스 의존 없음(랜딩과 동일 경량 렌더링).
# 비로그인 공개 표면이므로 인증을 요구하지 않는다. /terms 등은 NOINDEX_PATH_PREFIXES에 없어 색인 허용(SURF-3).
class PagesController < ApplicationController
  # VIEW-1 — 공개 표면은 모든 브라우저·인앱 웹뷰 허용(랜딩과 동일).
  include AllowAllBrowsers
  allow_unauthenticated_access

  # 랜딩과 동일한 공개 크롬(상단 바·LP-10 푸터) — 앱 자원·내비 미포함(SURF-6 예산 분리)
  layout "landing"

  def terms
    # 정적 문서 렌더용 빈 액션
  end

  def refund
    # 정적 문서 렌더용 빈 액션
  end

  def privacy
    # 정적 문서 렌더용 빈 액션
  end
end

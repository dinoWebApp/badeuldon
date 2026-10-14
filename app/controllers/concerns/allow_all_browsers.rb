# 공개 표면(① 랜딩·인증 3종·③ 뷰어) 전용 — ApplicationController 상속의
# allow_browser versions: :modern 게이트를 표면 단위로 무효화한다.
#
# VIEW-1·P3 — 공개 표면은 정적 문서 수준의 마크업(모던 JS 불필요, 클립보드 수동 복사
# fallback 존재)이라 모든 브라우저·인앱 웹뷰를 허용한다. 운영 실측(badeuldon.kr):
# 카카오톡 인앱 WebView(iOS 16.x + Safari/604.1)가 랜딩에서 406 Not Acceptable로
# 차단됐다. actionpack 8.1은 versions: :all을 지원하지 않고(NoMethodError 실증),
# 상속 before_action은 익명 람다라 skip_before_action으로도 해제할 수 없어 같은 이름의
# 인스턴스 메서드를 no-op으로 대체해 게이트를 무효화한다. /app·/admin의 :modern
# 정책은 불변(Turbo·모던 JS 전제 화면).
module AllowAllBrowsers
  extend ActiveSupport::Concern

  private
    # :modern 브라우저 검사 본문 대체 — 상속 람다가 호출해도 아무 검사도 하지 않는다.
    def allow_browser(**); end
end

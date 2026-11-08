# T3 — ViewEvent 강화(봇 UA 필터 + 하드닝) 구현 산출물

## 변경 파일
1. `app/models/view_event.rb` — `BOT_UA_PATTERN` 정규식과 `ViewEvent.bot?(user_agent)` 모듈 수준 공개 메서드 추가(봇 판정 단일 출처). 주석에 SHARE-3·PRD v0.27 인용 및 HeadlessChrome 의도적 제외 사유 기록.
2. `app/services/view_events/track_service.rb` — `#call` 선두에서 `ViewEvent.bot?(@user_agent)`면 `self` 즉시 반환(무기록 — "기록 제외"가 확정 설계). ViewEvent 미기록 → `mark_viewed!` 미호출 → noti_opened 훅 자연 차단. IP 저장 정규화 `normalized_ip`(공백 제거 + 45자 절단, 컬럼 limit 45 유지).
3. `test/services/view_events/track_service_test.rb` — 신규 테스트 3건(봇 UA 10종 무기록·무전이 / HeadlessChrome·nil·빈값 비봇 / 일반 600자 UA 정상 기록 + IP 45자 정규화).
4. `_workspace/parallel/T3/03_implementation.md` — 본 문서.

ViewerController는 변경 없음 — 봇 무동작은 TrackService 계약으로 흡수된다(호출부 무영향).

## 봇 패턴 목록 (대소문자 무시, /ix)
Googlebot · bingbot · Yeti · slurp · Mediapartners · crawl · spider · curl · wget · python-requests

- **HeadlessChrome 미포함(의도)** — Capybara 시스템 테스트 UA라 포함 시 테스트 전체 파괴. viewer 컨트롤러 테스트 21건 무영향 확인.
- UA는 저장 컬럼이 없음(`db/schema.rb` view_events에 user_agent 없음 — device 판정 입력으로만 사용) → 500자 UA 절단은 저장 대상이 없어 미적용. device는 원본 UA 기준 판정 유지. 이 사실을 track_service 주석에 명시.

## Phase 5 리뷰 반영 (APPROVED B0·C0 — WARNING 소화)

- **W-1 반영** — `BOT_UA_PATTERN`에 메신저 링크 프리뷰 계열 추가: `Slackbot`·`facebookexternalhit`·`WhatsApp`·`Twitterbot`·`Discordbot`·`TelegramBot`(/ix 유지, HeadlessChrome 비포함 원칙 유지). 테스트 봇 목록에 Slackbot·Discordbot 2종 단언 추가(총 12종).
- **W-2 반영** — `app/assets/tailwind/application.css` stale 주석 1줄 정정: "layout에서 CDN 로드" → "본 파일 @font-face로 셀프호스팅(/fonts/PretendardVariable.woff2)". (오케스트레이터 지시로 스코프 확장 적용)
- **W-3 미반영(기록)** — public/fonts 장기 캐시 헤더(Thruster CACHE_CONTROL·CF 엣지)는 운영 구성 과제로 코드 밖 — 기술 부채로 기록, 이번 배치 제외.

## 자기 스코프 검증 결과
- `bin/rails test test/services/view_events/` → 9 runs, 47 assertions, 0 failures, 0 errors (리뷰 반영 후 재검증)
- `bin/rails test test/controllers/viewer_controller_test.rb` → 21 runs, 152 assertions, 0 failures (HeadlessChrome UA 무영향 확인)
- `bin/rubocop` (소유 파일 3종) → 3 files inspected, no offenses
- 전체 테스트·문서·화이트리스트 외 파일: 미수정

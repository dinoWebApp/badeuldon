# 05_review — 기술 부채 병렬 배치 T1~T4 (Phase 5, 2026-11-09, Reviewer)

**status: APPROVED** (BLOCKER 0 · CRITICAL 0 · WARNING 3)

> 대상: 미커밋 변경 전체 — T1 Pretendard 셀프호스팅 · T2 ko locale · T3 ViewEvent 강화 · T4 거래처 삭제 가드.
> 판정 기준: PRD v0.27(CLIENT-1·SHARE-3·DESIGN-3 확정 해석 반영)·P1~P5·ARCHITECTURE_CONVENTION.
> 검증 방법: 전체 diff 정적 검토 + `bin/rails runner -e test` 실행 재현 6건(트랜잭션 롤백 — 데이터 비오염) + Rails 8.1 소스 대조. `bin/rails test` 643건·`bin/rubocop`은 오케스트레이터 확인치로 간주(재실행하지 않음).

---

## 1. 이슈 목록 (전부 WARNING — 수정은 다음 해당 파일 접촉 시로 충분, 재리뷰 불요)

### W1 · WARNING · SHARE-3 · `app/models/view_event.rb:15-18`
- **내용**: 봇 판정 커버리지 갭. `BOT_UA_PATTERN`이 범용 `bot` 토큰과 링크 프리뷰 계열(Slackbot·Discordbot·Twitterbot·facebookexternalhit·WhatsApp)·검색 봇 나머지(Applebot·YandexBot·DuckDuckGoBot·GPTBot)를 포함하지 않는다. 이 계열은 U1이 링크를 메신저에 붙여넣는 **가장 현실적인 오알림 경로**(링크 프리뷰 선취 → ViewEvent 기록 → SHARE-4 "열었습니다" 오알림)다. 배치의 T3 목적(오열람 알림 방지) 관점에서 커버리지 보완 권고.
- **왜 CRITICAL 아님**: PRD는 봇을 열거하지 않고, 확정 해석도 Googlebot 등 명시 봇 테스트만 요구. 로직 오류가 아니라 커버리지 판단이며, `ViewEvent.bot?` 단일 출처 설계 덕에 정규식 한 줄 추가로 확장 가능.
- **권고**: `BOT_UA_PATTERN`에 `facebookexternalhit|Slackbot|Discordbot|Twitterbot|WhatsApp|Applebot|YandexBot|DuckDuckGo|GPTBot` 계열 추가. 범용 `bot` 단독 토큰은 카카오톡 인앱 UA 등 정상 UA 오탐 가능성을 먼저 실측한 뒤 포함(위양성 주의).

### W2 · WARNING · DESIGN-3(주석 정합) · `app/assets/tailwind/application.css:14`
- **내용**: 토큰 블록 주석이 "국문 우선 폰트는 Pretendard(layout에서 CDN 로드)"로 남아 CDN 제거와 모순. 유지보수자가 CDN 재도입을 오인할 수 있다.
- **권고**: "layout에서 CDN 로드" → "public/fonts 셀프호스팅(@font-face는 본 파일 최상단)"으로 갱신.

### W3 · WARNING · PERF-2(성능 마무리) · `public/fonts/PretendardVariable.woff2`
- **내용**: 2.0MB immutable 자산이 무핑거 `public/` 경로로 서빙됨. Thruster는 `/assets/*`(핑거프린트)에만 immutable 장기 캐시를 부여하고 그 외 정적은 ETag 재검증 수준 — 리뷰어 환경에서 바이너리 소스 대조는 불가, README 동작 기준. 기능 문제는 아님(304 재검증 동작, `font-display: swap`으로 렌더 차단 없음).
- **권고(선택)**: Thruster 정적 캐시 설정(`CACHE_CONTROL`) 또는 Cloudflare 엣지 룰로 `/fonts/*`에 `public, max-age=31536000, immutable` 부여. 운영 배포 노트에 기록 후 다음 인프라 접촉 시 반영으로 충분.

---

## 2. Rule ID 준수 매핑 (검증 근거 포함)

| Rule | 판정 | 근거 |
|:---|:---|:---|
| **CLIENT-1** (T4) | 통과 | 가드 조건 = `status != :draft` 존재 시 차단 — PRD "삭제는 발행 이력이 없는 거래처(초안만 보유)에 한한다"와 정확히 일치. runner 재현: issued 차단+오류 문구·**voided도 발행 계열로 차단**·초안 전용은 초안 소거 후 삭제·청구서 0건 정상 삭제. `invoices.client_id` FK가 RESTRICT(schema.rb:204)라 초안 소거 없이는 500이 나므로 소거가 필수임이 스키마로 입증 |
| **P4** (T4) | 통과 | client 삭제 경로의 message_logs 연쇄 소실이 차단됨. `message_logs.invoice_id on_delete: :cascade`(schema.rb:207)가 살아있는 invoice만을 전제 — 가드가 그 전제를 보장. (사용자 탈퇴 연쇄의 전체 삭제는 AUTH-1.5 데이터 소멸 설계로 본 배치 스코프 밖 — 기존 설계 유지 확인) |
| **AUTH-1.5** (T4) | 통과(무충돌) | `user.rb` invoices→clients 선언 순서 주석("순서 변경 금지") + 모델/컨트롤러 테스트 + runner 재현(발행 이력 보유 client 보유 상태 user destroy 성공, 잔여 0건). Rails 8.1 `destroy`는 `with_transaction_returning_status`로 트랜잭션 래핑(transactions.rb:375) — 가드 내 초안 소거와 client DELETE가 원자적이고, abort 시 Rollback으로 초안 소거도 무효화(부분 삭제 없음) |
| **SHARE-3** (T3) | 통과 | runner 재현: 봇 UA 10종 → ViewEvent 0건·상태 issued 유지 / 정상 UA → 기록·issued→viewed·first=true. 무기록 → `mark_viewed!` 미호출 → noti_opened 훅 자연 차단으로 이력·전이·알림 3종 동시 제외. HeadlessChrome 제외는 확정 해석(테스트 UA 보호)대로 구현·주석 명시. 뷰어 렌더링은 봇도 유지(기록만 제외 — PRD 문자 그대로) |
| **DESIGN-3** (T1) | 통과 | CDN `<link>` 제거 확인 — 잔여 CDN은 포트원 SDK(`app/billings/show.html.erb`, PLAN-5·스코프 외)뿐. `@font-face`(font-weight 100 900·swap·woff2-variations)가 `@import "tailwindcss"` **뒤** 위치(CSS 규칙 정상)이며, **빌드 산출물** `app/assets/builds/tailwind.css`(신규 파일 이후 타임스탬프)에서 `@font-face{font-family:Pretendard Variable;...src:url(/fonts/PretendardVariable.woff2)format("woff2-variations")}` 실측. `--font-sans` "Pretendard Variable"과 family명 일치. 폰트 파일 WOFF2 v2 검증(2,057,688B) |
| **PERF-2** (T1) | 통과 | CDN RTT 제거로 뷰어 2초 예산 방향 정합 — 캐시 헤더 여지는 W3 |
| **TIME-1·ko locale** (T2) | 통과 | `default_locale=:ko`·`available_locales=[:en,:ko]`. **I18n 숨은 영향 전수 확인**: 앱 코드에 `I18n.l`/`l()` 사용 0건, 리마인더 `format_date`는 수동 포맷(`"#{date.mon}월 #{date.day}일(#{WEEKDAY_NAMES[date.wday]})"` — locale 무의존, 솔라피 variables 무영향), `number_with_delimiter`는 ko 구분자가 콤마로 동일, `passwords_mailer` 제목 하드코딩 한국어, 폼 라벨 하드코딩 — 회귀면은 검증 메시지뿐이며 3-S에서 ko.yml 이식으로 해소(643건 0실패). ko.yml에 사용자 입력·HTML 없음 |
| **보안·무결성 (전수)** | 통과 | T4 오류 메시지는 비즈니스 안내만(정보 누출 없음), controller는 `destroy!`→`destroy` 분기로 abort를 303+alert로 수렴(기존 redirect 패턴 준용). T3 정규식은 선형 alternation — ReDoS 없음. `normalized_ip` 공백 제거+45자 절단(컬럼 limit 45 유지, null:false 안전). 소유권 화일수록 준수(T1 layouts/fonts·T2 Gemfile/locales·T3 view_events 계열·T4 client/controller), 타 도메인 미접점 |
| **ARCHITECTURE §4** | 통과 | Service는 params/Current 미참조, Model은 Controller 미참조, 뷰 쿼리 없음, 컨트롤러 얇게 유지. 의존 방향 위반 0건 |

## 3. 확정 해석 편차 (확인 후 수용 — 이슈 아님)

1. **T3 "UA 500자 절단 하드닝" 미적용**: view_events에 user_agent 저장 컬럼이 없음(schema.rb:191-200 실측) — 절단 대상 부재, device는 원본 UA 판정. 사유가 track_service 주석에 명시되어 있어 수용. (정상 UA 600자 기록 테스트로 회귀도 보호)
2. **T4 마이그레이션 불요**: 01_plan은 migrate 후보로 열어뒀으나 02_prd_update가 "스키마 변경 없는 모델 가드"로 정제 — 최신 확정 해석 기준 준수.
3. **T2 en.yml 한국어 블록 잔존**: :ko 전환으로 로딩되지 않는 백업이며 "정리 과제" 주석 명시 — 수용.

## 4. 설계 트레이드오프 (Tester·운영 유의)

- **봇 UA 스푸핑으로 열람 회피 가능**: 토큰 보유자가 `curl` UA로 열람하면 U1에게 열람이 보이지 않는다. 봇 제외 명세의 본질적 트레이드오프(토큰=권한 구조는 유지) — 제품 관점 수용 확인만 필요.
- **동시 경합 초안 생성 race**: 가드 exists? 판정 후 초안 INSERT 경합 시 FK RESTRICT 500 가능 — 단일 사용자 DELETE 흐름에서 사실상 불가능한 타이밍. 기록용.
- **이전 리뷰 잔존 2건**(F-REM — DeliverJob origin 갱신·테스트 Solapi 공용 stub)은 이번 배치 파일과 무관, 본 리뷰에서 중복 지적하지 않음.

## 5. Tester 중점 테스트 제안 (다음 파이프라인 전달)

1. **W1 재현 시나리오**: `facebookexternalhit`·`Slackbot` UA로 `/b/:token` GET → 현재는 ViewEvent 기록·SHARE-4 알림 큐잉이 실제로 발생하는지 시스템 레벨 확인(정책 수용 여부 판단 자료).
2. **뷰어 폰트 로드**: viewer 시스템 테스트에서 `/fonts/PretendardVariable.woff2` 200 응답 + 빌드 CSS에 @font-face 포함 확인(인앱 UA 시뮬레이션 겸용 — VIEW-1 회귀).
3. **삭제 UX**: 발행 이력 보유 거래처 삭제 시 alert flash가 실제 화면(Turbo 흐름)에 표시되고 목록이 유지되는지 시스템 테스트.
4. **ko 회귀 샘플**: 뷰어·알림톡 문구가 I18n 전환의 영향권 밖임을 문구 스냅샷으로 고정(REM-2 톤 불변).

## 6. 통과 커버리지

- 정적: 전체 diff 28파일 + 연관 원문(client/invoice/user/message_log/view_event 모델·track_service·viewer_controller·schema FK·_head·application.css·ko/en.yml·mailers·reminders format_date·Thruster/Gem 소스)
- 실행 재현(`bin/rails runner -e test`, 롤백): T4-1 issued 차단 / T4-2 voided 차단 / T4-3 초안 소거+삭제(아이템 포함) / T3-1 봇 무기록·무전이 / T3-2 정상 기록·전이 / T4-4 탈퇴 연쇄 무충돌 — **6/6 통과**
- T1 빌드 반영: `bin/rails tailwindcss:build` 실행 후 산출물에서 @font-face 실측

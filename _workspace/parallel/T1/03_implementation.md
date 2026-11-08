# T1 — Pretendard 셀프호스팅 구현 산출물 (2026-11-09)

PRD v0.27 DESIGN-3 — CDN 의존 없는 Pretendard 셀프호스팅(PERF-2 정합).

## 변경 파일 목록

| 파일 | 변경 |
|:---|:---|
| `public/fonts/PretendardVariable.woff2` | 신규 — Pretendard Variable 가변 폰트 단일 파일 |
| `app/views/layouts/_head.html.erb` | Pretendard CDN `<link>`(jsdelivr pretendardvariable-dynamic-subset.min.css) 제거, 셀프호스팅 주석으로 대체 |
| `app/assets/tailwind/application.css` | 최상단에 `@font-face` 추가(font-family "Pretendard Variable", weight 100 900, font-display: swap, url("/fonts/PretendardVariable.woff2") format("woff2-variations")) |

## CDN 제거 위치

- `app/views/layouts/_head.html.erb` 20~21행 — 유일한 Pretendard CDN 참조.
  (application·landing·app·viewer 레이아웃이 모두 _head를 사용/viewer는 주석으로 _head 원본 사용 명시 — 추가 제거 위치 없음)
- 잔여 확인: `grep jsdelivr|cdn.` app/views+app/assets → 포트원 브라우저 SDK(`app/billings/show.html.erb`)만 잔여 — 폰트 무관, T1 스코프 외(PLAN-5).

## 폰트 파일

- 소스: `https://cdn.jsdelivr.net/npm/pretendard@1.3.9/dist/web/variable/woff2/PretendardVariable.woff2`
  (gh/orioncactus 경로는 해당 파일 미존재 — npm 패키지 경로 사용)
- 크기: 2,057,688 bytes (~2.0MB), `file` 검증: Web Open Font Format v2
- 서빙: `public/fonts/` 정적 서빙 — Sprockets/Propshaft 파이프라인 우회, 경로 `/fonts/PretendardVariable.woff2`

## CSS 정합성

- 기존 `--font-sans`가 `"Pretendard Variable", Pretendard, ...` 스택 — @font-face 명칭 "Pretendard Variable"로 일치시켜 CSS 스택 변경 없음(최소 변경).

## 자기 스코프 검증 결과

- `bin/rails runner 'assets.paths stylesheets count'` → 2 (정상 부트, 가벼운 확인만 — repo-wide 마이그레이션 미실행)
- `bin/rails test test/system/viewer_test.rb` → 3 runs, 17 assertions, 0 failures
- `bin/rails test test/system/viewer_promise_test.rb viewer_refusal_test.rb` → 3 runs, 0 failures
- `bin/rails test test/system/app_invoice_reminders_test.rb` → 최초 1회 selenium 플래키 1 error, 재실행 2 runs, 22 assertions, 0 failures/0 errors (폰트 무관 타이밍 이슈)
- `bin/rubocop app/views/layouts app/assets` → 0 offenses

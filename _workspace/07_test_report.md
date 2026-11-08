# 07 테스트 보고서 — 기술 부채 병렬 배치(T1~T4) 테스트 보강 + 7-S 전체 게이트

- 실행일: 2026-11-09 · 실행자: badeuldon-tester · 대상: 리뷰(APPROVED·W3) Tester 전달 사항 보강 + 전체 회귀
- 기준: `_workspace/05_review.md` §5 Tester 중점 제안, `_workspace/parallel/T1~T4/03_implementation.md`, `_workspace/02_prd_update.md`(PRD v0.27)

## 1. 보강 시나리오 (신규 4건)

| # | Rule ID | 시나리오 | 파일 | 결과 |
|:--|:---|:---|:---|:---|
| 1 | SHARE-3·SHARE-4·INV-4 | 링크 프리뷰 봇 UA(Slackbot-LinkExpanding·facebookexternalhit·Discordbot)로 `/b/:token` GET 3회 → 각 200 렌더 유지(View-1), ViewEvent 0건, issued→viewed 전이 없음(SHARE-4 오알림 원천 차단). W1 보완분(Slackbot·facebookexternalhit 계열)이 실제로 무기록임을 컨트롤러 레벨로 고정 | `test/controllers/viewer_controller_test.rb` | 통과 |
| 2 | DESIGN-3·PERF-2 | `/fonts/PretendardVariable.woff2` 200 응답 + 뷰어 응답 본문에 jsdelivr 참조 0건(CDN 재도입 회귀 방지) + 빌드 산출물 `app/assets/builds/tailwind.css`에 `@font-face src(/fonts/PretendardVariable.woff2)` 존재(실제 로드 성립 근거) | 동일 파일 | 통과 |
| 3 | CLIENT-1·P4 | 발행 이력 보유 거래처 삭제 → 303+alert 후 리다이렉트된 목록 화면에 `p#alert` 문구 실렌더 확인 + 거래처 카드 링크 유지(레코드 보존). 기존 flash 값 단언에서 화면 렌더 단언으로 강화 | `test/controllers/app/clients_controller_test.rb` | 통과 |
| 4 | REM-2·TIME-1(T2 회귀 방어) | `SendService#build_variables` 스냅샷 — `I18n.with_locale(:en)` 전환 전후 변수 맵이 완전 동일(`만기일: "11월 9일(월)"`, `금액: "110,000"` 포함). format_date가 수동 포맷이라 locale 무의존임을 고정 — 솔라피 템플릿 치환 보호 | `test/services/reminders/send_service_test.rb` | 통과 |

- 외부 API 실호출 0건(4번은 build_variables 직접 스냅샷, FakeSolapiClient 주입만 사용).
- W1 잔여: 범용 `bot` 단독 토큰은 리뷰어 권고대로 위양성 실측 전 미포함 — 본 테스트도 범용 토큰을 단언하지 않는다(정책 확정 시 추가).

## 2. 7-S 전체 게이트 결과

- `bin/rails test` **647 runs, 3809 assertions, 0 failures, 0 errors, 0 skips** (기존 643 + 보강 4)
- `bin/rubocop`: 169 files inspected, no offenses detected
- 실패 이력: 보강 3번 최초 1건 실패(테스트 오류 — 목록이 테이블이 아닌 카드 레이아웃이라 `td` 셀렉터 부적합) → `a` 링크 셀렉터로 자체 수정 후 통과. **코드 버그 0건** — Developer 위임 불요.

## 3. 미검증·운영 과제

- **W-3(PERF-2)**: `/fonts/*` 캐시 헤더(Thruster `CACHE_CONTROL` 또는 Cloudflare 엣지 룰)는 인프라 설정 영역으로 **이번 게이트에서 미검증** — 리뷰 권고대로 운영 배포 노트 기록 후 다음 인프라 접촉 시 반영·실측 필요.
- 시스템(브라우저) 레벨의 폰트 실로드·Turbo confirm 대화상자는 headless 환경 한계로 컨트롤러/통합 레벨로 대체 검증함(리뷰어 제안의 "시스템 테스트 수준"은 컨트롤러 테스트로 충족 — 지시 1·3의 허용 범위).

## 4. 결론

보강 4건 전부 통과, 전체 647건 0실패, RuboCop 0위반 — 게이트 통과. 코드 수정 0건(테스트 파일 3개만 변경).

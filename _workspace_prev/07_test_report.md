# 07_test_report.md — Phase 7 테스트: 랜딩 루트 화면(표면 ① 최소 골격)

- **일자**: 2026-10-08
- **Tester**: LandingTester
- **대상**: Phase 3 구현 + Phase 5 APPROVED — `app/controllers/landing_controller.rb`, `app/views/landing/index.html.erb`, `config/routes.rb`(root)
- **계층**: 컨트롤러 통합 테스트(`test/controllers/`) — 시스템 테스트 불요(정적 페이지, 핵심 여정 아님)

## 실행 결과 요약

| 항목 | 결과 |
|:---|:---|
| `bin/rails test` | **7 runs, 24 assertions, 0 failures, 0 errors, 0 skips** — 전체 통과 |
| `bin/rubocop` | `27 files inspected, no offenses detected` (exit 0) |

## 신규 테스트 파일

| 파일 | 내용 |
|:---|:---|
| `test/controllers/landing_controller_test.rb` | 시나리오 1~6 (6 test, 23 assertions) |
| `test/integration/health_check_test.rb` | 시나리오 7의 /up 회귀 가드 (1 test) |

## 시나리오별 결과

| # | 시나리오 | 테스트 | 결과 |
|:---|:---|:---|:---|
| 1 | SURF-1/LP-1 정상: GET / 비로그인 200 + landing/index 렌더 | `GET /는 비로그인 200으로 landing/index 히어로를 렌더한다` | ✅ 통과 |
| 2 | LP-1 헤드라인: h1 Q6 확정 문구 매칭 | `h1 헤드라인이 Q6 확정 문구와 일치한다` — 리뷰 제시 정규식(`/말하기 어려운 '돈 다오',\s*받을돈이 대신합니다/`) 그대로, `<br>` 개행·ASCII 작은따옴표(0x27 실측 확인) 커버 | ✅ 통과 |
| 3 | LP-1 구성요소: 서브카피 4단계 어휘·주 CTA·「무료 · 카드등록 없음 · 3분」·보조 CTA | `LP-1 구성요소 4종이 모두 노출된다` | ✅ 통과 |
| 4 | SURF-3 역방향: noindex 부재 + title = content_for :title 값 | `표면 ①은 noindex 없이 content_for :title을 렌더한다` | ✅ 통과 |
| 5 | SURF-4: `<a>` 요소 0개 + 주 CTA disabled/aria-disabled | `a 요소는 0개이고 모든 CTA는 disabled 버튼이다` — `assert_select "a", count: 0`(Nokogiri 요소 매칭으로 `<article>` 등 오탐 방지) | ✅ 통과 |
| 6 | LP-12: 금지 표현 「100%」·「보장」 부재 | `LP-12 금지 표현이 응답에 없다` — 부문자열 검증 | ✅ 통과 |
| 7 | 회귀: /up 헬스체크 + 전체 스위트 | `GET /up는 200을 반환한다` + 전체 실행 | ✅ 통과 |

## 구현 참고 사항 (테스트 설계 판단 기록 — 오류 아님)

1. **`assert_template` 미사용**: `rails-controller-testing` 젬이 도입되지 않아 Rails 5+ 표준 설치에서 `assert_template`은 NoMethodError. 시나리오 1의 "landing/index 렌더"는 **뷰 고유 콘텐츠(h1) 렌더**로 증명(레이아웃에는 h1이 없음). 젬 추가는 이번 범위 밖.
2. **/up 테스트 신규 작성 배경**: `test/`에 기존 테스트가 0건(`.keep`만 존재)하여 "기존 테스트 전체 실행"만으로는 회귀 가드가 성립하지 않음. Reviewer tester_focus #5(기존 경로 /up 영향 없음)를 영구 가드로 만들기 위해 통합 테스트 1건 추가.
3. **비로그인 상태**: F-AUTH 미구현으로 세션 인프라 자체가 없음 — 요청이 정의상 익명. 리뷰가 언급한 "로그인 상태에서도 동일"은 F-AUTH 시점 재검증 항목(05_review.md 후속 후보와 일치).
4. **외부 API 실호출 0건**: 정적 페이지로 stub 대상 자체가 없음. 시간 의존 로직 없어 `travel_to` 불요.

## 원인 분류

- **실패 0건** — 코드 버그/테스트 오류 분류 대상 없음. 수정 대상 코드 없음(Developer 위임 불필요).
- 1차 실행부터 전부 통과(재시도·회귀 수정 없음).

## 자체 점검 (Tester 완료 전)

- [x] 시나리오 1~7 전부 커버 (Rule ID: SURF-1/3/4/6·LP-1·LP-12)
- [x] 외부 API 실호출 0건
- [x] 미사용 정의 0건, `bin/rubocop` 통과, 들여쓰기 2칸
- [x] 전체 회귀 `bin/rails test` 통과 (7 runs / 0 failures / 0 errors)

## 후속 시점 재검증 항목 (Phase 5 리뷰 후속과 정합)

- F-AUTH 구축 시: 주 CTA 링크 연결 후 SURF-4 단일 진입 재검증(본 테스트의 `count: 0`·disabled 단언은 그 시점 갱신 대상), 로그인 상태 GET / 동일 응답 확인
- LP-2~13 구축 시: SEO 메타 적용(SURF-3 정방향), 시나리오 6 금지 표현 목록 확대 여부

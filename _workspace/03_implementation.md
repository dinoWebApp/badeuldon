# 03_implementation — CLIENT-3/4·PROMISE-5 (2026-11-10, Developer-lite)

## 변경 파일 목록

| 구분 | 파일 | 변경 |
|---|---|---|
| Query(신규) | `app/queries/clients/payment_scorecard_query.rb` | CLIENT-4 성적표 집계 — 누적 청구액(발행 계열)·진행 중 건수·평균 지급 지연일(약속일 대비)·이행률·6개월 월별 추이 + 비교용 사용자 전체 평균·거래처 수 |
| Query(신규) | `app/queries/clients/promise_compliance_query.rb` | CLIENT-3·PROMISE-5 약속 이력 목록 — Q14 3상태(fulfilled/broken/pending)·최신 약속순·마감 입금일 병기 |
| 컨트롤러 | `app/controllers/app/clients_controller.rb` | show 확장 — @scorecard·@compliance 적재(본인 거래처 한정, before_action set_client 유지) |
| 컨트롤러 | `app/controllers/app/invoices_controller.rb` | `scorecard` 신규 — `Current.user.clients.find(params.expect(:client_id))` 소유권 격리(타인 404)·`_scorecard_summary` 파셜 렌더 |
| 라우트 | `config/routes.rb` | `resources :invoices` collection `get :scorecard` — 헬퍼 `scorecard_app_invoices_path` |
| 헬퍼(신규) | `app/helpers/app/clients_helper.rb` | 지연일/이행률 "-" 표기·비교 배지(차이 ≥1일·거래처 2개 이상)·6개월 막대 정규화·3상태 배지(DESIGN-2) |
| 뷰 | `app/views/app/clients/show.html.erb` | 거래처 정보 아래 — 성적표 카드(CLIENT-3/4·"약속일 대비" 부제·DASH-5 구분 문구·6개월 CSS 막대·비교 배지) + 약속 이행 이력 목록 + 빈 상태 안내 |
| 뷰(신규) | `app/views/app/invoices/_scorecard_summary.html.erb` | 발행 폼용 1~2줄 요약(지연일·이행률·배지·null "-"·부제) |
| 뷰 | `app/views/app/invoices/_form.html.erb` | 거래처 select 래퍼에 `client-scorecard` 컨트롤러·summary div(hidden) — 기존 invoice-form 로직 무손상(별도 컨트롤러 격리) |
| JS(신규) | `app/javascript/controllers/client_scorecard_controller.js` | select change 시 fetch 갱신·수정 화면 진입 시 프리로드·미선택 시 비노출 |
| 테스트(신규) | `test/queries/clients/payment_scorecard_query_test.rb` | 5건 — 3상태·부분입금 최종 입금일(행 가중 반전 검출)·6개월 월 경계·null 처리·전체 평균·소유권 격리 |
| 테스트(신규) | `test/queries/clients/promise_compliance_query_test.rb` | 3건 — == 경계 이행·도과+1 미이행·최신순·재응답 최신 약속 1건(P4)·격리 |
| 테스트(신규) | `test/controllers/app/clients_scorecard_test.rb` | 5건 — 비인증 302·show 렌더(카드·빈 상태)·타인 거래처 404·scorecard 200·scorecard 타인 404 |

마이그레이션 불요(Q14 파생 계산 — 별도 기록 컬럼 없음). 모델 변경 없음(판정 로직은 Query Object로 격리 — 규약 §3.2).

## Rule ID 매핑

- **CLIENT-3**: show 거래처 카드(누적 청구액·진행 중 건수) + 약속 이행 이력 목록 — `clients/show.html.erb` + `PromiseComplianceQuery`
- **CLIENT-4**: 평균 지급 지연일(약속일 대비·약속 없던 마감 제외)·이행률·6개월 CSS 경향·비교 배지·발행 폼 Turbo fetch 요약 — `PaymentScorecardQuery` + 헬퍼 + `_scorecard_summary` + `scorecard` 엔드포인트
- **PROMISE-5**: "자동 기록" = Q14 파생 집계 — `PaymentScorecardQuery::OPERATIVE_PROMISE_JOIN`(청구별 최신 약속) + `PromiseComplianceQuery.status_key`
- **Q14**: 이행 = paid && 마감 입금일(MAX paid_on) ≤ 약속일 / 미이행 = 도과 후 미수 **또는 도과 후 입금**(3분류 배타 귀결 — paid+지연은 이행도 판정 중도 아님) / 판정 중 = unsettled && promised_on ≥ today. 구현 위치: `PromiseComplianceQuery.status_key`(단일 출처)·`PaymentScorecardQuery#compliance_rate`(동일 정의 SQL)
- 보조: PAY-1/2(마감 입금일 = payments MAX paid_on·행 가중 방지 — DASH-5 C-1 선례), TIME-1(Date.current KST), P1(문구 톤)

## 판정 정의 정합성 설계

- 운영 약속 = 약속일 보유 응답 중 MAX(id) 1건 — 재응답·inquiry 섞임에도 이중 행 없음(P4 최신 기준)
- 평균 지연일 분모 = 약속 있던 마감 건만(약속 없는 마감·미수 제외) — nil이면 뷰 "-"·배지 미노출
- 이행률 분모 = 확정 건(이행+미이행)만 — 판정 중 제외, 확정 0건이면 nil
- 비교 배지 = 사용자 전체 거래처 평균 대비 차이 ≥1일, 거래처 1개면 미노출
- 6개월 경향 = 마감 입금월 strftime 그룹핑, 창 밖 마감 버림·빈 달 nil

## 자기 스코프 검증 결과

- 신규 테스트 13건 전부 통과(쿼리 8 + 통합 5)
- `bin/rails zeitwerk:check` 통과
- `bin/rubocop` 대상 8파일 0 위반(JS 컨트롤러는 RuboCop 대상 아님 — 기존 JS 전체가 동일)
- 회귀: `bin/ci` 게이트 전체 통과(rubocop 0·brakeman 0경고·테스트 954건 0 실패·seeds) — ※ 전체 스위트 포함이었으나 산출 전 검증으로 1회만 실행, 임시 레코드 없음(테스트 트랜잭션 롤백)
- `params.expect(:client_id)` 스칼라 문법 동작 실측(엔드포인트 테스트 경유)

## Phase 5 후속 수정 (2026-11-10 — 05_review.md CHANGES_REQUESTED C-1·W-1)

| 이슈 | 수정 내용 |
|---|---|
| C-1 (CRITICAL — voided·draft 약속 모집단 불일치) | `PromiseComplianceQuery.call`의 client_scope에 `where.not(status: [ :draft, :voided ])` 추가 — PaymentScorecardQuery(이행률·평균 지연일)와 동일 발행 계열 모집단. 주석에 "목록과 성적표가 동일 모집단 — 무효·초안 청구의 약속은 표기 제외"·Q14·P1 명시, status_key 주석에 "호출 스코프가 발행 계열 한정 — voided·draft는 판정 자체를 하지 않는다" 갱신. 재발 방지 테스트 1건 추가(promised 상태에서 void! → 목록 0행·broken 0) |
| W-1 (WARNING — 배지 색 판정) | `client_comparison_badge`가 [문구, class] 반환으로 변경 — 빠름=emerald·느림=주황(DESIGN-2 지연 계열). 뷰 하드코딩 색 제거 — `clients/show.html.erb`·`_scorecard_summary.html.erb` 양쪽 동일 helper 소비 |

**재검증 결과**
- 신규·수정 테스트 14건 통과(쿼리 9 + 컨트롤러 5)
- runner 실측(RAILS_ENV=test·트랜잭션 롤백 정리): voided+과거 약속 시드 → 목록 미노출·이행률 100%(분모 일치)·"빠른" 배지 emerald·"느린" 배지 orange 확인
- `bin/rubocop` 수정 .rb 3파일 0 위반·`bin/rails zeitwerk:check` 통과
- 소유권 범위 준수: `promise_compliance_query.rb`·`clients_helper.rb`·`show.html.erb`·`_scorecard_summary.html.erb`·`promise_compliance_query_test.rb`만 변경

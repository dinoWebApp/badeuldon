# 05_review — CLIENT-3/4·PROMISE-5 지급 성적표 (2026-11-10, Reviewer)

## Status: CHANGES_REQUESTED

BLOCKER 0 · CRITICAL 1 · WARNING 1 — CRITICAL 1 수정 후 재리뷰 대상.

## 검증 방법 (컨트롤러 경유 통합 재현 — Run A~C 교훈 반영)

정적 분석에 더해 실측 재현을 수행했다(재현 파일·스크립트는 검증 후 전부 삭제·레코드 정리 완료 — 잔여 0건).

1. **Integration 5건 신규 작성·실행 통과**: ① 마감·약속 있음 show 렌더(3상태 배지·입금일 병기·비교 배지 "느린" 방향·경향 바·DASH-5 구분 문구) ② scorecard 파라미터 조작(비숫자·미전달 400대 수렴·음수·미존재·타인 거래처 404 — 500 없음) ③ 발행 폼 new에 client-scorecard·invoice-form 컨트롤러 공존(select·summary 타깃·rowTemplate 무손상) ④ edit 폼 공존 ⑤ U1 세션 격리(gamma 응답에 beta 데이터 미노출)
2. **runner 실측(RAILS_ENV=test·KST 2026-11-10)**: Q14 경계(마감 입금일 == 약속일 → fulfilled·+1일 → broken)·부분입금 최종 입금일(MAX paid_on — 행 가중 없음, (0+1+2)/3=1 실측)·재응답 최신 약속 1건·kind 필터(paid_report·inquiry-only 제외·this_week은 뷰어 실제 저장 경로(검증 통과 save)에서 포함·pending)·voided/draft 분류·enum status getter 타입(String — `== "paid"` 비교 정상)
3. **기존 신규 테스트 13건 통과**(쿼리 8 + 컨트롤러 5)·`zeitwerk:check` 통과
4. git diff 교차 확인 — 변경 파일이 03 산출물 목록과 정확히 일치·`invoice_form_controller.js` 미변경(무손상 실측)

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| C-1 | CRITICAL | PROMISE-5·CLIENT-3·Q14·P1 | app/queries/clients/promise_compliance_query.rb:12-44(status_key 36-44) | **voided(무효)·draft 청구의 과거 약속이 "미이행"으로 목록에 노출되는데, 같은 화면의 PaymentScorecardQuery#compliance_rate·avg_delay_days는 voided를 모집단에서 제외한다 — 동일 화면에서 이행률과 이력 목록이 모순된다.** 실측 재현: voided+과거 약속 1건·이행 1건 시드 → 목록에 "미이행" 행 노출(true)·이행률=100%(voided 분모 제외). VOIDABLE_STATUSES에 promised·partially_paid가 포함되므로 "채무자가 약속한 뒤 채권자가 청구를 무효화"하는 실제 시나리오에서 채무자가 영구 "미이행" 표기된다 — 채권자 사유 정리를 채무자 불이행으로 기록하는 것은 P1(관계 보존 최우선)에도 반하며, 두 쿼리가 "동일 정의 단일 출처"라는 코드 주석과도 불일치한다. Q14 문언(이행=paid+입금≤약속일/미이행=도과 후 미수/판정 중=유효)은 voided를 정의하지 않으므로, scorecard 쪽 제외 해석이 합리적 귀결이다 | PromiseComplianceQuery.call의 client_scope에 `where.not(status: [ :draft, :voided ])`를 추가해 PaymentScorecardQuery와 모집단을 일치시킨다(무효·초안은 약속 판정 자체가 무의미 — 이행률·평균 지연일과 같은 모집단). status_key의 `elsif promised_on < today` 폴백은 운영 상태(issued~partially_paid·paid)만 받게 된다. 재발 방지 테스트: voided 약속 건이 목록에 없고 이행률과 broken 행 수가 일치하는 케이스 추가 |
| W-1 | WARNING | DESIGN-2·UI 품질 기준 | app/views/app/clients/show.html.erb:46 · app/views/app/invoices/_scorecard_summary.html.erb:10 | 비교 배지의 부정 신호("평균보다 N일 느린 거래처")도 emerald 녹색(긍정 상태색)으로 표기된다. DESIGN-2 상태색 3종 원칙(지연·연 계열=주황)과 배치돼 U1 빠른 훑기에서 "빠른 거래처"와 동일하게 긍정으로 오인된다. 실측에서 "평균보다 1일 느린 거래처"가 녹색 배지로 렌더됨을 확인 | 방향 색 판정을 뷰 하드코딩에서 helper로 이동 — `client_comparison_badge`가 [문구, class]를 반환하고 느림=주황(bg-orange-50/text-orange-600)·빠름=emerald로 분기. show와 summary 양쪽에 적용 |

## Rule ID 준수 매핑 (구현이 반영한 Rule — 실측 근거 포함)

| Rule | 구현 위치 | 판정 |
|:---|:---|:---|
| Q14 | PromiseComplianceQuery.status_key(단일 출처) + PaymentScorecardQuery SQL 동일 정의 | **정합(경계 전수 실측)** — == → 이행·+1일 → 미이행·도과 후 미수/입금 → 미이행·유효 → 판정 중. "미이행 = 도과 후 입금 포함" 확장은 3분류 배타·전포괄의 유일한 합리적 귀결로 Q14 문언과 정합. 단 voided·draft는 Q14 미정의 영역으로 C-1 불일치 |
| PROMISE-5 | OPERATIVE_PROMISE_JOIN(promised_on NOT NULL 응답 중 MAX(id) 1건) | **정합** — "자동 기록"을 파생 집계로 충족(Q14). 재응답 시 최신 약속 1건(P4) 실측. this_week(서버 산정 금요일)·date_selected 포함·paid_report·inquiry·refusal 제외 실측 |
| CLIENT-3 | clients/show 카드(누적 청구액·진행 중 건수·이력 목록 3상태) | **정합** — 누적 청구액은 발행 계열(draft·voided 제외 — INV-6 무효는 미청구 취급)·unsettled 건수. 빈 상태 안내 확인 |
| CLIENT-4 | PaymentScorecardQuery + 헬퍼 + _scorecard_summary + scorecard 엔드포인트 | **정합** — 평균 지연일은 약속 있던 마감 건 한정·약속 없는 거래처 nil("-")·이행률 확정 건만·6개월 마감 입금월 그룹핑(창 밖 버림·빈 달 nil)·비교 배지(02 확정 해석 3 — 모든 거래처 평균 대비·차이 ≥1일·거래처 1개 미노출)·발행 폼 select fetch 갱신·"약속일 대비" 부제 + DASH-5(만기 대비) 구분 문구 실측 |
| PAY-1/2 | 마감 입금일 = payments MAX(paid_on) 청구별 1행 | **정합** — 부분입금 행 가중 없음 실측(DASH-5 C-1 선례 준용 — 분할 입금 2행이 평균에 이중 반영되지 않음을 (0+1+2)/3=1로 검증) |
| TIME-1 | Date.current(KST)·t.date 컬럼 julianday 산술 | **정합** — time_zone Seoul 실측·date 컬럼이라 CAST 절삭 오차 없음·월 경계 strftime 정확 |
| 소유권 격리(SEC) | 쿼리 이중 스코프(client_id + user_id) + 컨트롤러 Current.user.clients.find | **정합** — 타인 거래처 show·scorecard 404·비인증 302·파라미터 조작(비숫자·음수·미존재) 400대/404 수렴·500 없음 실측. 쿼리가 client.user_id를 재단언하는 방어층도 적절 |
| INV-6 무효 | voided 제외(누적 청구액·이행률) | 정합 — 단 목록 쪽 미제외가 C-1 |
| 아키텍처 §3.2·§4 | app/queries/clients/ Query 2종(.call 진입점·today 주입)·뷰는 결과만 소비·표현 로직 헬퍼 분리 | **정합** — F-DASH 리포트(app/queries/reports/) 선례와 동일 패턴·params/Current 미유입·컨트롤러 액션 ≤10줄·params.expect 스칼라 실측 동작 |
| 라우트(SURF-1) | invoices collection GET scorecard | **정합** — 읽기 조회의 collection GET 정당화 주석·경로 헬퍼 사용·URL 동사 없음 |
| Stimulus 격리 | client-scorecard 별도 컨트롤러(select·summary 타깃·url value) | **정합** — invoice-form(품목·금액 계산) 파일 미변경 실측 + new/edit 렌더에 양쪽 컨트롤러·타깃 공존 확인. recalculate 액션이 금액 요약 dl에 한정돼 select change와 이벤트 충돌 없음 |

## Tester에게 제안하는 중점 테스트 영역

1. **C-1 재발 방지(수정 후 필수)**: voided·draft 약속 건이 이력 목록에 없고, 목록 broken 행 수와 이행률 분모가 일치하는 쿼리 테스트 — "promised 상태에서 void!한 청구" 시나리오 명시
2. **비교 배지 반올림 경계**: 반올림 전 실차이 ≥1일이어도 반올림 후 diff 0이면 미노출됨(재현 확인됨) — 기대 동작 확정·테스트 고정 권장. 이행률 80% 경계 색 전환(뷰 조건)도 병행
3. **연말·연초 6개월 창**: travel_to 2027-01-15에서 월 라벨·창 밖 버림·빈 달 nil(strftime 연 경계)
4. **this_week 약속의 시간 경과**: 접수 시점 pending → 약속일(금요일)+1일 travel 후 broken 전환(자정 경계 포함)
5. **시스템 테스트(JS)**: 발행 폼에서 거래처 선택 → 요약 조각 삽입·미선택 복귀 시 hidden 복원·fetch 실패 시 조용한 수렴 — 인앱 브라우저 전제(VIEW-1은 뷰어 대상이지만 폼 JS 동작은 U2 기기 다양성과 무관하지 않음)
6. **조기 입금(음수 지연)**: "N일 전" 표기·경향 막대 abs 정규화에서 음수 월 표기(문구·색 혼동 여부 육안 확인)

## 통과 커버리지 요약

- A절(컨트롤러 경유): 전 항목 통과 — show(마감·약속 있/없음·빈 상태)·scorecard(본인 200·타인 404·비인증 302·조작 파라미터)·발행 폼(거래처 select·fetch 타깃 정합·invoice-form 무손상)·U1 세션 격리
- B절(Q14): 전 경계 실측 통과 — ==·+1일·부분입금 MAX·재응답·kind 필터·this_week 실저장 경로
- C절(무결성): user 스코프 이중 방어·SQL 인젝션 없음(상수 조인 SQL·파라미터 바인딩)·이스케이프 기본(raw/html_safe 미사용)·N+1 없음(이력 2쿼리·closing 해시 선산출)·innerHTML 주입은 동일 출처·서버 이스케이프 응답으로 수용 가능
- D절(아키텍처·UI): §3.2·§4 준수·컨트롤러 10줄·뷰 쿼리 금지·tabular-nums·role/aria(경향 role="img" 라벨·막대 aria-hidden)·빈 상태·터치 타깃(min-h-11) — 단 W-1 상태색만 지적

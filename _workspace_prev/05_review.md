# 05_review.md — F-PAY 입금 처리(원클릭 마감·부분입금) Phase 5 리뷰

- **일자**: 2026-10-13 · **리뷰어**: PaymentReviewer
- **대상**: git 변경분 신규 4(migration·Payment·Payments::RecordService·App::PaymentsController) + 수정 7(invoice.rb·invoices/promises/dashboards 컨트롤러·뷰 2·routes) + schema 자동
- **입력**: 01_plan(결정 #1~#4)·02_prd_update(승인 해석)·03_implementation(§2 방어 지점 7곳·§4 회귀 2건)·PRD v0.18.7 §6.8/§6.4/§6.9 원문 대조·AGENTS.md UI 품질 기준
- **방법**: 원문 대조 + 코드 전수 + **리뷰어 독립 러너 실측 30항**(동시성 실스레드 S1~S3·가드·금액·회귀·집계·전이 매트릭스·0원 엣지) + `params.expect` 파라미터 경로 프로브(actionpack 8.1.4 실동작) + Brakeman 변경파일 0 경고 확인
- **참고**: 이전 산출물 `_workspace_prev/05_review.md`(F-PROMISE) — 이슈 #1~#3은 F-PAY 무관(미반복), #4(`mark_promised!` overdue 조건)는 F-REM 백로그로 여전히 개방(본 Phase `PAYABLE_STATUSES`에는 overdue 포함 확인)

## Status: APPROVED

- **BLOCKER 0 · CRITICAL 0 · WARNING 3** — 금전 마감의 멱등·동시성(최우선 검증 대상)은 방어 지점 7곳 전부 실측 통과. WARNING 3건은 UX·엣지·운영 참고 사항으로 Phase 6 커밋 진행 가능.
- RuboCop 0에러·zeitwerk·migrate·기존 테스트 323 runs 0실패는 Phase 4 보고를 전제로 재검하지 않음(Brakeman 변경파일 한정 0경고만 부가 확인).

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | PAY-1(UX 피드백) | `app/views/app/invoices/show.html.erb:356-358` | **부분입금 폼의 입금일 오류 문구 미표시**. `:paid_on` 에러(미래 날짜 제출) 시 필드는 적색 스타일(`form_input_classes`)을 받지만 안내 문구가 그 폭 아래에 없고 **원클릭 박스의 입금일 필드**(329-331)에만 렌더된다. 두 폼이 같은 `@payment` 객체를 공유해 발생 — 사용자는 자신이 제출한 폼이 아닌 위쪽 박스에서 원인을 찾아야 한다. DB 무손상·상태 무변화(422 재렌더). | 부분입금 폼 `paid_on` 필드 아래에도 원클릭 폼과 동일한 3줄 에러 표시(`errors.key?(:paid_on)` 분기) 추가. |
| 2 | WARNING | PAY-1(엣지·확인 요청) | `app/models/invoice_item.rb:19-23` · `app/services/payments/record_service.rb:33-37` | **0원 청구서 마감 불가**. `unit_price >= 0` 검증이라 단가 0원 품목만으로 total 0원 청구서 발행이 가능하다(실측: 발행 성공). 이후 원클릭은 `Payment amount=0` → 「1원 이상」 422, 부분입금 1원도 「잔액(0원)보다 큽니다」 422 — **어떤 경로로도 paid 전이 불가**, 무효 처리로만 정리 가능한 미마감 상태가 영구 잔존(실측 확인). 데이터 부정합은 없으나 PAY-1 「원클릭 마감」이 상태 공간상 불가능한 영역. | 제품 결정 필요: ① 발행 컨텍스트(:issue)에 `total_amount > 0` 검증 추가(INV 후속 정합) — 권장, 또는 ② 서비스에서 잔액 0 원클릭 시 Payment 없이 `mark_paid!` 분기. 현 구조 유지 시 무효 처리 안내 문구로 보완. |
| 3 | WARNING | P4(운영·확인 요청) | `app/models/payment.rb` 전체·라우트(create 단일) | **부분입금 오기록의 정정 경로 부재**. 잔액 이내라도 한번 기록된 Payment는 수정·삭제 불가(P4·미완성 상태에서 잘못 입력한 금액 포함). 잘못 기록 시 청구서 무효→재발행(INV-5/6 경로)로만 정리 가능해 원천징수 청구 등에서 실수 비용이 크다. PRD가 입금 정정 규칙을 요구하지 않아 **위반은 아님** — P4 해석상 수용 가능하나 운영 불편 예상. | 확인 요청: 후속 Phase에 Payments 수정·역기록(취소 Payment, 감사 이력 포함) 또는 무효 재발행 절차 안내 문구 등 제품 결정. 본 Phase 수정 불필요. |

## 멱등·동시성 검증표 (최우선 — 방어 지점 7곳 전수 + 리뷰어 실측)

방어 지점 번호는 03_implementation §2와 대응. 실측은 `RAILS_ENV=test bin/rails runner` 임시 스크립트(실행 후 삭제, 생성 데이터 전량 정리 확인) — 동시성 시나리오는 **실스레드 2개·커넥션 분리** 재현.

| # | 방어 지점 | 코드 확인 | 실측 결과 | 판정 |
|---|:---|:---|:---|:---|
| 1 | `with_lock`(청구서 행 직렬화·잠금 하 reload) — `record_service.rb:31` | `with_lock` → `lock!` → `reload(lock:)`로 잠금 획득 시점의 **최신 status·잔액**으로 재조회됨(active_record 소스 확인). | **S9**: 미마금 상태로 로드한 stale 객체로 마감 후 재시도 → stale in-memory status 무시·「이미 수금이 마감된」 422·Payment 1건 유지 | PASS |
| 2 | `guard_payable!`(잠금 하 최신 상태 가드) — `:49-54` | `unsettled?` 불통과 시 paid는 「이미 수금이 마감된」, draft·voided는 「기록할 수 없는 상태」로 메시지 분기. | **S1** 동시 이중 원클릭: 결과 페어 정확히 `1 ok + 1 invalid(이미 수금)`·Payment 1건(전액)·paid·잔액 0. **S4** draft/voided/paid 각 차단·미기록·이중 기록 0건 | PASS |
| 3 | 잠금 하 잔액 재검증(초과 차단) — `:33-34`, `guard_within_remain :59-66` | `remain = total − payments.sum`을 **잠금 후 재조회**해 직전 트랜잭션 등록 반영. 비교는 `to_i`(가드) + 원값을 `Payment.new`에 전달해 모델 검증이 최종 판정. | **S2** 동시 부분입금 4만+4만(총액 5만): 1건 기록·1건 「남은 잔액(10,000원)보다 큽니다」 422 — **문구의 잔액이 잠금 하 재계산값**과 일치. **S5** 초과 70,001/상한 10억+ 모두 422·미기록 | PASS |
| 4 | `mark_paid!`/`mark_partially_paid!` 조건부 원자 UPDATE — `invoice.rb:184-197` | `status IN (PAYABLE_STATUSES)` 단일 UPDATE — `mark_viewed!`/`mark_promised!` 동일 패턴. status는 INV-5 보호 컬럼 아님(무충돌). 반환값 미사용이나 가드+직렬화로 조건 항상 성립. | **S1**(→paid)·**S2**(→partially_paid)·**S3**(혼합 경합 최종 paid) 상태 전이 정확. CHECK 재검 S8 참조 | PASS |
| 5 | 전이 판정(생성 직후 합계 재조회) — `transition! :71-77` | `total − Σpayments ≤ 0 → paid`, `> 0 → partially_paid`. with_lock 직렬화로 동시 "도달" 판정 불가. | **S3** 원클릭(nil)+부분 8,000 동시(잔액 1만): 어느 순서든 최종 paid·**합계 = 총액 정확히 일치(초과 0원)** | PASS |
| 6 | 컨트롤러 소유권 격리 — `payments_controller.rb:24-26` | `Current.user.invoices.find(params[:invoice_id])` — 타인 청구서는 404 수렴(기존 승인 패턴과 동일·`params.expect(payment: [:amount, :paid_on])` 화이트리스트). | 코드 전수(러너 미경유 — 컨트롤러 경로) | PASS |
| 7 | 폼 객체 컬렉션 분리(§4 회귀 #1) — `invoices_controller.rb:130-133` 등 | `@invoice.payments.new`가 아니라 `Payment.new(invoice_id:)` — 부모 저장 시 자동 저장 대상 제외. 서비스 `rejected_payment`·컨트롤러 `@payment ||=`·promises `load_invoice_show` 3곳 동일 규격. | **S6**: 분리형 미완성 Payment 존재 하 `issue!` true→issued·`void!` true→voided·Payments 0건 — 「Payments is invalid」 회귀 폐쇄 | PASS |
| 8(부) | **원클릭 amount nil 파라미터 경로** | 폼은 `paid_on`만 제출 → `params.expect` 누락 키 허용 확인 필요(actionpack 8.1.4 `expect` 실동작 프로브: `payment[:amount]` → **nil**, ParameterMissing 없음) | 프로브: 원클릭 제출 → `nil` → 서버 잔액 기준값 채택 / 부분입금 빈 문자열 → `""` 유지(승격 없음) → 422「입금 금액을 입력해 주세요」 | PASS |
| 9(부) | **DB CHECK 이중 방어** — migration `payments_amount_positive` | `amount > 0` CHECK·`null: false`(amount·paid_on)·FK·인덱스 — schema.rb 반영 확인. | **S8**: 모델 검증 우회 원시 INSERT(amount=0) → `SQLite3::ConstraintException: CHECK constraint failed: payments_amount_positive` | PASS |

**러너 실측 총계: 30/30 PASS**(S1~S9 27항 + 전이 매트릭스 보강 3항 — 아래 표). 부수 확인: 검증 스크립트 셋업 중 Free 플랜 월 3건 발행 한도(PLAN-1)가 의도대로 발동해 `issue!`가 차단됨을 확인.

## 전이 매트릭스 (INV-4 — PAY 진입)

`PAYABLE_STATUSES = issued·viewed·overdue·promised·partially_paid`(invoice.rb:29) — `unsettled?` 모집단과 정확히 일치. `overdue` 포함 근거: 연체는 파생 판정(결정 #2)으로 미수 회수 경로에서 제외하면 안 됨 + F-REM 저장화 대비 enum 예약(03 §2-4).

| 현재 상태 | → paid(마감) | → partially_paid | 근거 |
|:---|:---|:---|:---|
| draft | 차단(422 「기록할 수 없는 상태」) | 차단 | 러너 S4 실측 — INV-4 상 전이 없는 상태 |
| issued | ✓(원클릭·합계 도달) | ✓(미달) | 러너 S1·S2 실측 |
| viewed | ✓ | ✓ | 러너 실측(보강 — 원클릭 paid·잔액 0·1건) |
| overdue(enum) | ✓ | ✓ | 러너 실측(보강 — 원클릭 paid)·개발 러너 #9 일치 |
| promised | ✓ | ✓ | 러너 실측(보강 — 원클릭 paid) — 약속 후 마감 회수 경로 |
| partially_paid | ✓(잔액 도달) | ✓(재기록, 조건 유지 true) | 러너 S3 실측 — 부분입금 반복 흡수 |
| paid | 차단(422 「이미 수금이 마감된」) | 차단 | 러너 S4 실측 — 이중 클릭 두 번째 흡수 지점 |
| voided | 차단(422 「기록할 수 없는 상태」) | 차단 | 러너 S4 실측 — INV-6 종결 상태 |

- 진입 경로 유일성: paid/partially_paid 진입은 `Payments::RecordService`→`mark_paid!`/`mark_partially_paid!`뿐(전 코드베이스 grep — 뷰어·RegisterService 경로 없음 → **PROMISE-7 구조 유지**). paid_report는 여전히 상태 불변.
- 역방향(paid→미수) 전이 코드 없음 — 마감 되돌림 불가(원클릭 turbo_confirm 문구와 정합).

## 잔액 계산 검증 (PAY-2·DASH-1)

| 항목 | 산식·코드 | 검증 | 판정 |
|:---|:---|:---|:---|
| 단건 잔액 | `remaining_amount = total_amount − payments.sum(:amount)`(invoice.rb:207-209) — 호출마다 최신 조회(캐시 없음) | S2·S5: 부분입금 4만/5만 후 잔액 1만/2만 재계산, 마감 후 0 | PASS |
| 음수 불가 | 초과 등록 차단(결정 #3) — `guard_within_remain` + CHECK | S2·S5·S8 — 잔액 음수 도달 경로 없음 | PASS |
| 집계(DASH-1) | `remaining_total(scope) = Σtotal − Σpayments(모집단 서브쿼리 한정)`(dashboards_controller.rb:25-27) | **S7**: 사용자 미수 = (8만−3만) + 2만 = 7만 실측 일치 — 부분입금 반영·paid·draft·voided 제외(지급액이 미포함 청구에서 차감되지 않는 비대칭 없음) | PASS |
| 연체 금액 | 동일 산식을 `overdue` 스코프에 적용 | S7: 만기 경과 없음 0·Integer 타입 확인. 파생 판정 scope 재사용 | PASS |
| DASH-2 소멸 | 마감 대기 = `unsettled ∩ paid_report` — paid 전환 시 unsettled 제외로 소멸 | 코드 확인(`load_action_items`)·기존 테스트 무수정 통과(03 §4) — partially_paid는 마감 대기 유지(PROMISE-7 합산 유도 정합) | PASS |
| 마감 Payment.paid_on | 원클릭 날짜 = 폼값(기본 오늘·과거 허용) | S5: 어제 지정 마감 → 마감 Payment paid_on=지정일·PRD PAY-1 「입금일 자동 기록」 이행 | PASS |

## 금액 무결성 검증 (03 §3·§4 재검)

| 입력 | 결과 | 비고 |
|:---|:---|:---|
| 빈 문자열 `""` | 422 「입금 금액을 입력해 주세요」·미기록 | **전액 승격 없음** — `nil?` 판별이라 `""`는 모델 검증행(presence). 프로브+S5 실측 |
| 0 / 음수 / 소수("1.5") / 쉼표("10,000") | 422 「1원 이상 10억 이하」·미기록 | `only_integer`(raw 문자열 검증) — 캐스트 왜곡("10,000"→10) 없이 차단. S5 |
| 잔액 초과 | 422 「남은 잔액(N원)보다 큽니다」·미기록 | 잔액 안내문 동반. S2·S5 |
| 상한 초과(10억+) | 422 | MAX_AMOUNT. S5 |
| 미래 입금일 | 422 「오늘 또는 그 이전」·미기록 | `paid_on <= Date.current`(KST — TIME-1). S5 |
| 원시 INSERT amount=0 | DB CHECK 위반 | 모델 우회 이중 방어. S8 |
| 회귀 #2(answer 422 재렌더) | `load_invoice_show`에 입금 변수 포함 확인 | 코드 전수 — `Passed nil to :model` 재발 소지 없음 |

## Rule ID 준수 매핑

| Rule ID | 구현 확인 | 판정 |
|:---|:---|:---|
| **PAY-1** 원클릭 마감·입금일 자동 기록 | 「입금 확인하고 마감」 버튼(turbo_confirm 「되돌릴 수 없습니다」)·날짜 기본 오늘 → `amount nil` → **서버가 잔액 기준값 계산**(프론트 금액 신뢰 없음)·마감 Payment.paid_on 기록. 프로브·S1·S5 실측 | ✓ |
| **PAY-2** 부분입금·잔액 자동 재계산 | 부분입금 폼 → `mark_partially_paid!` + `remaining_amount` 재계산·notice에 잔액 안내. 「시퀀스 잔액 기준 계속」은 REM 부재로 데이터 축적만 — 플랜 A-2 명시 범위 | ✓(범위 한정) |
| **INV-4** | 전이 매트릭스 참조 — PAYABLE 5상태 → paid/partially_paid만, 조건부 원자 UPDATE | ✓ |
| **DASH-1** | 미수 총액·연체 금액 잔액 기준 재계산 + 카드 보조문구 갱신(「남은 잔액 합계」). S7 실측 | ✓ |
| **DASH-2** | 마감 대기 소멸 — unsettled 스코프로 구조 보장(paid 제외). 03 §4 무수정 통과 재확인 | ✓ |
| **PROMISE-7** | 마감 경로는 표면 ② U1 전용 — 뷰어(③)·Viewer/Promise 컨트롤러 무변경(git diff 확인), paid_report→마감 호출 경로 부재 | ✓ |
| **DESIGN-2/3/6** | paid 「수금이 완료되었습니다」 녹색 배너 + 헤더 「수금 완료」 녹색 뱃지(badge spec — paid는 연체 표기 우선 분기에서 제외 확인)·금액 전 칸 tabular-nums+won()·버튼 min-h-11·focus-visible 링·원클릭 turbo_confirm | ✓ |
| **P4** | Payment 사용자 삭제·수정 경로 없음(create 단일 라우트)·`dependent: :destroy`는 발행 계열 삭제 불가(초안만 destroy)라 실효 발동 없음·마감 되돌림 없음 | ✓ (정정 여지 — 이슈 #3) |
| **TIME-1** | 기본값·미래 판정 모두 `Date.current`(앱 TZ Seoul) | ✓ |
| **SEC(마감 멱등)** | 검증표 1~9 참조 — with_lock·재검증·원자 전이·CHECK | ✓ |
| **PLAN-1** | 결제 도메인 자체가 플랜 게이트 대상 아님(발행 한도는 기존 issue! 담당 — 러너 부수 확인) | N/A(정당) |
| **PAY-5** | 계좌조회 자동화 코드 없음 — 미구현이 규칙 준수 | ✓ |
| **후속 제외** | PAY-4 알림·PAY-6 PDF·PROMISE-5 미구현·뷰어 무변경 — 플랜·02 문서와 일치 | ✓ |

**아키텍처(ARCHITECTURE_CONVENTION)**: Service `#call`+키워드 생성자(Current/params 무의존) ✓, with_lock 1트랜잭션(기록+전이 원자) ✓, 명시적 예외 `InvalidPayment`(실패 레코드 동반)·조용한 rescue 없음 ✓, 컨트롤러 `params.expect`·303/422 규약·422 재렌더 @변수 완비(3개 컨트롤러 동일 구성) ✓, 라우트 중첩 `resources :payments, only: :create`(SURF-1 ② 내) ✓, 마이그레이션 명시적 제약(CHECK·null:false·FK) ✓. 마이너 관찰(비이슈): 상세 뷰에서 `remaining_amount`/`payments_total` 호출로 SUM 쿼리 4회 — 단일 청구서 인덱스 조회라 비용 미미, 구조는 모델 공개 API 경유로 정상.

**범위 준수**: git 변경분 = 신규 4+수정 7(코드)+schema+문서 — 플랜 범위 외 파일 미변경, 기존 테스트 파일 무수정(git status 확인), PRD는 버전 인상만(02 문서).

## Tester에게 제안하는 중점 테스트 영역

1. **컨트롤러 HTTP 경로 원클릭(PAY-1)**: 리뷰어 프로브는 서비스·파라미터 계층 — 요청 스펙에서 원클릭 폼 제출(금액 필드 없음)이 303·paid·Payment 1건(잔액 전액)인지, 빈 금액 문자열 제출이 422(전액 승격 아님)인지. 이중 클릭(연속 POST 2회) → 두 번째 422 「이미 수금이 마감된」·flash 표시.
2. **동시성 통합 재현**: 시스템 스펙 또는 컨트롤러 스펙에서 2세션 병렬 POST — 결론은 러너 S1~S3와 동일(1건만 확정)이지만 HTTP 계층에서 세션·와이어까지 확인.
3. **부분입금 시나리오(금액 무결성 표 그대로)**: 0·음수·소수·쉼표·잔액+1원·미래 날짜 → 422 + 미기록 + 상태·잔액 불변; 유효 부분입금 → 잔액 재계산 안내 notice·부분입금 배지; 잔액 도달 최종 등록 → paid·확정 배너·폼 미노출.
4. **상태별 마감(전이 매트릭스)**: issued·viewed·promised·partially_paid(+(F-REM 후) overdue) 각각 원클릭 → paid; draft·voided·paid → 422 문구 검증.
5. **DASH 재계산(DASH-1)**: 부분입금 보유 사용자 대시보드 — 미수 총액·연체 금액이 잔액 합계; paid 전환 후 미수·마감 대기 카드에서 소멸(DASH-2)·연체 건수 감소; voided+입금 이력 건이 집계에 불포함(차감 비대칭 없음).
6. **이슈 #1 회귀 방지**: 부분입금 폼에 미래 날짜 제출 → 해당 폼 위치에서 오류 안내 확인(수정 후). 이슈 #2: 0원 청구서 발행→마감 시도 동작(제품 결정 후 기대치 확정).
7. **소유권**: 타인 청구서 `invoice_id`로 POST → 404·미기록; 미인증 POST → 로그인 리다이렉트.
8. **회귀 #1·#2 재확인**: 발행·무효·재발급 422 경로에서 입금 섹션 정상 렌더, promise answer 422 재렌더에 `Passed nil` 없음(기존 323 스위트 유지).

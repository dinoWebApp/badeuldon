# 05_review.md — F-INV 청구서 발행 + 대시보드 실데이터 전환 (Phase 5 리뷰)

- **일자**: 2026-10-12
- **리뷰어**: InvoiceReviewer (badeuldon-review-checklist 준거)
- **대상**: `_workspace/03_implementation.md` 변경분 — 신규 13(`Invoice`·`InvoiceItem`·마이그레이션·`App::InvoicesController`·헬퍼·뷰 8종·JS 컨트롤러) + 수정 8(user·dashboards·base_helper·routes·en.yml·schema·대시보드 뷰)
- **검증 방법**: 전 코드 정독 + `bin/rails runner` 재실측(외부 트랜잭션 `joinable: false` 롤백 — DB 비오염 확인: 종료 시 invoices 0건) + JS-서버 산식 퍼지 대조(node, 0~200,000 × 부가세 2모드 × 원천 2모드 = 0 불일치)

## Status: CHANGES_REQUESTED

**BLOCKER·CRITICAL 없음** — 금액 산식·상태 전이·소유권·토큰·한도의 핵심 정합성은 전부 실측 통과. 그러나 (a) 사용자 표시 오류 1건(#1)과 (b) 위조 파라미터 500(#4)은 코드 수정이 필요하고, (c) PLAN-1 무효 포함·INV-3 프리필 기준 해석 2건(#2·#3)은 Phase 2 승인 해석 목록(`02_prd_update.md`)에 누락되어 승인 보강이 필요하다. 수정 규모는 경미(재리뷰 최소 범위)이며 #5~#7은 권고(후속 Phase 반영 가능).

---

## 1. 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | INV-6 | `app/views/app/invoices/show.html.erb:17-23` | 무효 건 상세 부제 분기 오류 — 발행계열→무효 건은 `issued_at`이 항상 존재해 첫 분기("…에 발행했습니다.")만 실행되고 `elsif voided_at`("…에 무효 처리했습니다.")은 **도달 불가한 데드 브랜치**. 무효 날짜가 사용자에게 안내되지 않는다(뱃지·하단 안내 문구는 정상). | 조건 순서 변경: `if @invoice.voided_at.present? … elsif @invoice.issued_at.present? … else 초안` |
| 2 | WARNING | INV-3 | `app/controllers/app/invoices_controller.rb:18` | 만기일 프리필이 **초안 작성일+30일** — PRD INV-3 원문은 **"발행일 + 30일"**. 장기 보관 초안을 이후 발행하면 규칙보다 이른 만기일(발행 시점에 이미 만료 경과분)로 발행될 수 있어 채무자 지급 기간 단축(P1 영향 가능). 폼에서 사용자가 확인·수정 가능하고 당일 발행 플로우는 정합하나, 이탈 해석이 `02_prd_update.md` 승인 목록에 없음(03 기술 노트 4에만 기록). | ① 해석 승인 목록에 기록 후 현행 유지, 또는 ② `issue!`에서 due_on이 프리필 원값(미수정)이면 `issued_at.to_date + 30`으로 재계산 — 오케스트레이터 결정 |
| 3 | WARNING | PLAN-1 | `app/models/invoice.rb:148-154` | 월 3건 한도가 **무효 처리된 발행도 포함**(`issued_at` 기준 전수 카운트). "월 청구 3건"의 양립 해석(무효 제외 시 실질 무제한 발행-무효 순환 여지) 중 엄격 쪽 채택은 타당하나, 이 해석이 `02_prd_update.md` 승인 해석 목록에 없음(03 보고에만 "문서화된 해석"으로 기재). 오발행→무효 사용자가 당월 실질 2건만 남는 UX 영향도 함께 승인 필요. | 해석을 Phase 2 문서(PRD 해석 기록)에 정식 추가하거나, 무효 제외로 변경 — 현행 유지 권장(P4 발행 기록 정합·악용 방지) + 문서화 |
| 4 | WARNING | 무결성 | `app/models/invoice.rb:27` + `app/controllers/app/invoices_controller.rb:103-109` | 위조 `items_attributes: [{id: <타인 청구서 품목 id>, _destroy: 1}]` 전송 시 `assign_nested_attributes_for...`에서 `ActiveRecord::RecordNotFound`가 발생해 **422가 아닌 500** 반환 (실측: "Couldn't find InvoiceItem with ID=2 for Invoice with ID=1"). 데이터 침범은 없음(연관 스코프로 격리됨) — 강인성 문제. | 컨트롤러에서 항목 id를 해당 초안 items 스코프로 사전 필터(불일치 id 제거)하거나 `rescue ActiveRecord::RecordNotFound` → 422 |
| 5 | WARNING | INV-5 | `app/models/invoice.rb` (전이 가드 위치) | INV-5 가드가 **컨트롤러 draft 스코프에만** 존재 — 모델 `update!`로는 발행본 수정 가능함을 실측 확인. 현재 HTTP 경로 전부 격리라 사용자 도달 경로는 없으나, 향후 REM/PAY Job·콘솔·서비스에서 우회 가능(실측: 발행본 `update!` 성공). | `before_update` 가드 추가 권장: 초안이 아닌 경우 허용 변경 컬럼을 `status/token/token_expires_at/voided_at` 화이트리스트로 제한(상태 전이는 통과) |
| 6 | WARNING | INV-1 | `app/models/invoice_item.rb` / `invoice_form_controller.js:23-28` | **품목 행 수 상한 없음** — 행당 ≤1e13이지만 행 수가 무제한이라 (a) 합계 ≥ 2^53(≈901행)에서 JS 실시간 요약 정밀도 손실 가능(서버값 기준 안내문은 있음 — 실측에서 901행 우연 일치, 비정렬 값에서 손실), (b) 과도한 폼 페이로드. | `MAX_ITEMS`(예: 100) 검증 추가 + JS `addRow` 상한 — 상수는 산식·상한 상수와 같은 단일 지점 관리 |
| 7 | WARNING | 이식성 | `db/migrate/20261012000004_create_invoices.rb:29-33` | 금액 5종 컬럼이 `t.integer`(SQLite에선 8바이트라 무해). **PostgreSQL 이식 시 int4(±21.4억원)**가 되어 단가 상한 조합(행당 1e13)에서 저장 시점 오버플로. 구현 보고의 "64bit 정수 범위 내" 주장은 SQLite 전제에서만 성립. | 금액 컬럼에 `limit: 8`(bigint) 명시 — PG 배포 가능성이 없다면 기록 후 현행 유지 |

### 확인 요청(이슈 번호 없음 — 오케스트레이터/Tester 참고)

- **7일 내 만기 범위**(`dashboards_controller.rb:15`): `Date.current..Date.current+7` = 오늘 포함 8력일. "7일 내" 통용 해석 범위내 — 테스트에서 경계(오늘·+7·+8)를 고정 권장.
- **0원 청구서**: 전 행 단가 0 허용(산식 0원 정상 동작 실측). PRD 미금지 — 정책 확인만.
- **초안-only 사용자 대시보드**: `@has_invoices`(전체 존재) 기준 분기라 초안만 있는 사용자는 카드에 0원/0건 표시 — 값은 정확(미수 0원)하며 "거짓 0원 금지" 취지(빈 상태)와 충돌 없음(0건 사용자는 빈 상태 유지 확인).
- **편집 화면 라이브러리 select**: 기존 저장 행과 선택값 미연동(항상 "라이브러리에서 선택") — 기능 영향 없음(cosmetic).

### 무이슈 확인(전수 점검 항목)

- **소유권 격리**: 전 액션 `Current.user.invoices` 스코프 + `client_must_be_owned` 모델 검증(타인 거래처 지정 422 차단 실측). `client_id` 위조·`status` 파라미터 주입 불가(화이트리스트 미포함).
- **토큰**: `SecureRandom.urlsafe_base64(32)` ≈256bit(43자 실측), 고유 인덱스, 초안 NULL, **뷰 어디에도 미노출**(결정 #1 준수 — show·index 전수 확인), 로그 경로 없음(파라미터·리다이렉트 미포함). 무효 시 즉시 폐기(nil) 실측.
- **noindex(SURF-3)**: `/app` prefix 정책으로 신규 라우트 자동 커버 확인.
- **XSS**: 신규 파일 `raw`/`html_safe` 부재 확인.
- **반올림·오버플로**: §2 검증표 참조 — 전수 대조 통과.
- **`flash.now`+`render` 422**, 파괴적 버튼 `button_to`+`turbo_confirm`, `params.expect` 중첩 문서형 배열 — 규약 준수.
- **액션 10줄 이내·뷰 쿼리 부재·집계의 컨트롤러 배치·Stimulus UI 보조 단일** — 아키텍처 준수(§4 위반 없음, zeitwerk·RuboCop Phase 4 통과 전제).

---

## 2. 금액 계산 검증표 (재실측 — 러너 롤백, 전 항목 PASS)

단일 지점 `Invoice.compute_amounts` (모델 주석·구현 보고와 일치):

| 케이스 | 산식 | 기대 | 실측 | |
|:--|:--|:--|:--|:--|
| 0원 행(별도) | subtotal=0, total=0 | 0/0 | 0/0 | PASS |
| 1원·별도+원천 | 부가세 (1+5)/10=0·원천 33/1000=0·실수령 1 | 0/0/1 | 0/0/1 | PASS |
| 부가세 사사오입 104 | (104+5)/10 | 10 | 10 | PASS |
| 부가세 사사오입 105 | (105+5)/10 | 11 | 11 | PASS |
| 사사오입 정확반 15 | (15+5)/10 | 2 | 2 | PASS |
| 포함 역분해 1,100,000 | (11000000+5)/11 | 공급 1,000,000·부가세 100,000·총액 보존 | 동일 | PASS |
| 포함 역분해 109 | (1090+5)/11 | 공급 99·부가세 10 | 동일 | PASS |
| 포함 극소 11 / 1 | (110+5)/11 / (10+5)/11 | 10 / 1(부가세 0) | 동일 | PASS |
| **포함+원천 110,000** | 공급 100,000·부가세 10,000·원천 3,300·실수령 106,700 | 동일 | 동일 | PASS |
| 원천 내림 경계 | 101→3·10,000→330·33→1·1→0·1,000→33·100→3 | 동일 | 동일 전부 | PASS |
| 복수 행(3행) 130,456 | 부가세 (130456+5)/10=13,046 | 동일 | 동일 | PASS |
| 50행(Σ1,275,000) | 원천 내림 42,075 | 동일 | 동일 | PASS |
| 최대행 별도 1e13(1e4×1e9) | 부가세 1e12·총액 1.1e13 | 동일 | 동일 | PASS |
| 최대행 포함+원천 | 공급 9,090,909,090,909·부가세 909,090,909,091·원천 내림 299,999,999,999 | 동일 | 동일 | PASS |
| **전수 대조 0~300,000** | 별도 부가세 = Rational 사사오입 기준·포함 공급가 = (10n/11) 사사오입 기준과 전수 비교 | 0 불일치 | 0 불일치 | PASS |

- **수학적 등식 확인**: `(10n+5)/11` 정수 나눗셈은 `round_half_up(10n/11)`와 정확히 동치(10n mod 11 ≠ 5.5이므로 정확반 케이스가 존재하지 않음 — 즉 포함 역분해의 사사오입은 모호성 없음). 별도 `(s+5)/10`은 s mod 10 = 5에서 반올림(사사오입) 정합.
- **JS 미러 패리티**: node 퍼지 0~200,000 × {별도,포함} × {원천 on,off} — **0 불일치**. JS 산식(`Math.floor((s+5)/10)`·`Math.floor((n*10+5)/11)`·`Math.floor(s*33/1000)`)은 서버 정수 나눗셈과 동일. 요약 하단 "최종 금액은 서버 계산 기준" 안내 병기 확인.
- **영속 재산정**: `before_validation :recalculate_amounts` — 저장값 = 산식값(포함+원천 저장 실측), `_destroy` 표시 행 제외 재산정 확인, 발행 후 본문 불가로 금액 동결(채무자 표시 금액 불변 구조).

## 3. 상태 전이 매트릭스 검증 (INV-4)

| 전이 | 구현 | 실측 | 판정 |
|:--|:--|:--|:--|
| 초안 → 발행 | `issue!` (채번·토큰·유효기간·issued_at·PLAN-1 검증 `on: :issue`) | 성공·채번 `BD-20261012-001`·토큰 43자·만기=(due_on+60).end_of_day | ✅ |
| 발행 계열 → 무효 | `void!` (voidable 스코프 + `voidable?` 재확인·토큰 nil·voided_at) | 성공·토큰 폐기·채번 유지 | ✅ |
| 초안 → 무효 | 불가(초안은 삭제) — `set_voidable_invoice` 스코프 404 | 모델 `void!` false | ✅ |
| 수금완료/무효 → 무효 | `VOIDABLE_STATUSES` 제외 | 재무효 false 실측 | ✅ |
| 발행 → 재발행 | `issue!` 진입 `draft?` 재확인 | false 실측 | ✅ |
| 발행본 수정/삭제 (INV-5) | `edit/update/destroy/issue` draft 스코프 → 404 (구현 보고 실측) + 모델 가드 부재는 이슈 #5 | 콘트롤러 경로 차단 확인 | ✅(권고 #5) |
| 연체 (파생) | `overdue?` = 미수 && due_on < 오늘 — scope SQL 실측 `status NOT IN (0,6,7) AND due_on < '2026-10-12'` | 정합 | ✅ |
| viewed/promised/partially_paid/paid 진입 | enum 예약 — 후속 SHARE/PROMISE/PAY 도메인 | 해당 없음 | ✅ 범위 준수 |

**PLAN-1 월 3건**: 3건 발행 후 4건째 `issue!` false + 문구 "Free 플랜은 매월 3건까지 발행할 수 있습니다. Plus로 무제한 이용할 수 있습니다" 정확 일치 실측. 초안 무제한(결정 #3). 현재 전 사용자 Free(F-PLAN 부재 — Client `FREE_CLIENT_LIMIT` 동일 패턴).

## 4. Rule ID 준수 매핑

| Rule ID | 구현 지점 | 리뷰 판정 |
|:--|:--|:--|
| INV-1 | 채번 `BD-YYYYMMDD-NNN`(전역 일별 순차·고유 인덱스·경합 재시도 5회), 품목 복수 행, tax_mode, 계좌·표시명 스냅샷, `issuer_display_name` 서버 설정 | ✅ (행 수 상한 #6) |
| INV-2 | 원천 33/1000 내림(결정 #4), 프리랜저 기본 체크, 상세·요약 3종 분해 표기 | ✅ |
| INV-3 | `DEFAULT_DUE_IN_DAYS=30` 프리필 | ⚠️ #2 (발행일 기준과의 이탈 — 해석 승인 필요) |
| INV-4 | enum 8종 + `issue!`/`void!` 가드 + 연체 파생 판정 | ✅ |
| INV-5 | draft 스코프 가드(edit/update/destroy/issue) | ✅ (모델 가드 권고 #5) |
| INV-6 | voidable 스코프·토큰 즉시 폐기·voided_at | ✅ (시퀀스 중단 REM 부재 N/A — 보고 명시) |
| SHARE-1 | urlsafe_base64(32)≈256bit·고유 인덱스·초안 NULL·UI 미노출(결정 #1) | ✅ 전수 확인 |
| SHARE-2 | `token_expires_at = (due_on+60).end_of_day` KST | ✅ 실측 |
| PLAN-1 | `FREE_MONTHLY_INVOICE_LIMIT=3` 발행 시점 검사 | ⚠️ #3 (무효 포함 해석 승인 필요) |
| DASH-1 | 미수 총액(`unsettled` sum)·연체 건수·금액·7일 내 만기 — 컨트롤러 집계 | ✅ (7일 범위 확인 요청) |
| DASH-4 | `sorted_by_due`(만기 asc ≡ 연체일 desc) 상위 5건 + index 동일 정렬 | ✅ |
| ONB-1 | 0건→`new` 실링크 / 보유→목록 링크 전환 | ✅ (기존 테스트 2건 실패는 명세 이행분 — Phase 7 갱신) |
| CLIENT-2 | 라이브러리 select → Stimulus 프리필(전송값 없는 보조 UI) | ✅ |
| DESIGN-2/3/5/6 | 상태색 3종 뱃지(연체 주황·완료 녹색·초안·무효·대기 중립)·연체일 주황 강조·금액 tabular-nums·큰 숫자 카드·터치 타깃 min-h-11·focus-visible | ✅ |
| TIME-1 | 전부 `Time.current`/`Date.current`, TZ=Seoul 확인(채번 일자·issued_at·한도 월 경계·연체 판정) | ✅ |
| SURF-1/3 | `/app/invoices` REST+member 2종·noindex prefix 자동 커버 | ✅ |
| P4 | `issued_at`·`voided_at` 기록·발행 건 삭제 불가(삭제는 초안만) | ✅ |

## 5. Tester에게 제안하는 중점 테스트 영역

1. **금액 산식 경계(모델)**: §2 표 케이스를 그대로 픽스처화 — 특히 104/105 사사오입, 포함 109·1·11 극소 역분해, **포함+원천 조합(110,000→실수령 106,700)**, 원천 내림(101→3·1→0), 0원 행. JS 요약 문구("서버 계산 기준")로 브라우저 E2E 1건(폼 표시=저장값).
2. **상태 전이 가드(컨트롤러 통합)**: 발행본 `PATCH edit/update/destroy/issue` → 404, 초안 `PATCH void` → 404, 4번째 발행 → 422+한도 문구, 발행→무효→재무효·재발행 false. **발행 후 금액 동결**(무효 후에도 total 불변).
3. **PLAN-1 경계**: (a) 월 경계(KST — 10/31 23:59 vs 11/1 00:00 발행), (b) **무효 건 포함 카운트**(3건 발행→1건 무효→4번째 차단 여부 — 해석 #3 확정에 따라 기대치 확정), (c) 초안은 무제한.
4. **소유권 격리**: 타 사용자 client_id·invoice id·위조 `items_attributes id`(이슈 #4 — 422 반환으로 수정 시) 통합 테스트.
5. **INV-3**: 장기 보관 초안 발행 시 만기일(해석 #2 확정 후 기대치 고정), 만기일 과거 값 허용 시 토큰 만료가 과거가 되는 경계(정책 확인).
6. **대시보드 집계**: 0건 빈 상태 유지(기존 gamma 어설션)·초안만 보유(카드 0원)·연체/7일 내 만기 경계일(오늘·+7·+8)·DASH-4 정렬(연체일 desc)·상위 5건 limit.
7. **기존 실패 2건 갱신**: `dashboards_controller_test.rb:55`(ONB-1 CTA 실링크)·`:75`(사이드바 청구서 실링크) — 명세 이행분 갱신 방향.
8. **무효 상세 부제(#1 수정 후)**: 무효 건 상세에서 무효 일자 안내 문구 렌더.

## 6. 종합 의견

금액 계산·전이·토큰·한도 등 핵심 비즈니스 로직은 **순수 산식 전수 대조(0~30만)·통합 실측·JS 패리티 퍼지까지 이상 무**로 구현 품질이 높다. 산식의 단일 지점(모델)·JS 미러·문구 안내 구조도 명확하다. 수정 요청 7건 중 코드 수정은 #1(1줄)·#4(작음)이고 #2·#3은 해석 승인 기록, #5~#7은 권고 — 경미 수준이므로 Developer 신규 스폰 1회로 처리 가능하다.

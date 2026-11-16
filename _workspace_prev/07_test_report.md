# 07_test_report — F-LEGAL/REF 런 (Phase 7 · Tester)

날짜: 2026-11-11 · Tester(GLM-5.3-Flash) · 대상: F-LEGAL/REF 병렬 배치(T-F1 LEGAL·T-F2 REF + 3-S 결선) — 검증·보강·전체 게이트
선결 조건: Phase 5 재리뷰 APPROVED(`05_review.md`)·Phase 6 수정 완료(`03_implementation.md` §7)

## Status: 통과 — 코드 버그 0건

전체 스위트 + 보강 테스트 통과(아래 최종 결과). 실패 이력은 Tester 자작 테스트 오류 1건(§2.3) — 수정 후 재실행 통과. 프로덕션 코드 수정 0건.

---

## 1. 리뷰 제안 5건 처리 결과

| # | 제안 | 처리 |
|---|---|---|
| ① | PDF 시스템 테스트 1건 | **신설·통과** — `test/system/app_legal_document_pdf_test.rb`: U1 실로그인 → legal_documents show → 미결제 "워터마크 미리보기 PDF 내려받기" 링크 → same-origin fetch로 %PDF 수령·attachment 헤더 단정 → FulfillPassService(프로덕션 확정점) paid 전환 → "내용증명 PDF 내려받기" 링크 → 정식 PDF %PDF·10,000바이트 초과(Pretendard 임베드)·**미결제 바이트 ≠ paid 바이트**(C-1 브라우저 레벨 비교). 웹훅 체인은 컨트롤러 테스트(B-1 회귀)가 담당하고 시스템 테스트는 프로덕션 확정점 서비스 재사용(시스템 세션에서 Integration post 불가 — 설계 주석 기록). 외부 API 실호출 0 |
| ② | referrals 정식 테스트 활성화 | **확인** — `referrals_controller_test` 6건 전부 실행(0 skip 실측): D+31/30/29 경계·unsettled 한정(paid·voided·draft 제외)·gamma 소유권 격리·P5·REF 고지 문구 5종 본문 검증. skip 해제 후 `assigns` 교체(본문 기반)가 실제로 통과함을 확인 |
| ③ | LEGAL 주문 결제 체인·격리·이중 주문 | **기존 커버 + 보강** — 컨트롤러 테스트가 create(5,000원·metadata.invoice_id)→웹훅 확정→정식 PDF 체인·C-2 재주문 차단·failed 재주문 허용을 이미 커버. 격리는 show 404만 있어 **download 404 격리 1건 신설**(PDF 유출 방지 — 소유권은 set_order `Current.user.orders.legal_docs` 단일 출처) |
| ④ | REF-3 전달 경로 부재 | **코드 grep 판정: 테스트 불요** — `app/controllers/app/referrals_controller.rb`는 index 1액션만 존재(조회·렌더뿐). referrals 도메인 전체(app/)에 Solapi·HTTP 전송·Job 호출 0건(grep 실측), 뷰 링크는 /app 내부 경로만(app_invoices_path·app_invoice_path). 외부로 나가는 경로가 코드상 없으므로 테스트로 부재를 증명할 대상이 없다 — REF-3(외부 전송 경로 0)은 구조로 담보됨 |
| ⑤ | D+30 경계 배너+목록 | **신설·통과** — `test/controllers/app/invoices_legal_referral_banner_test.rb` 3건: D+31 배너 2종 노출(내용증명·추심 안내/장기 미수금 안내 + 결선 헬퍼 링크·LEGAL-4 우체국 문구)·D+30 당일/29일 미노출(초과 경계)·paid·draft 미노출(unsettled 한정). 목록 경계는 ② referrals 테스트가 동일 판정식(due_on+30 < today)으로 커버 |

## 2. 보강 신설 테스트 (총 6건 · 46 assertions)

| 파일 | 건수 | 내용 |
|---|---|---|
| `test/system/app_legal_document_pdf_test.rb` | 1 | ①의 시스템 테스트 — 미리보기/paid 정식 2단계 fetch 비교 |
| `test/controllers/app/invoices_legal_referral_banner_test.rb` | 3 | ⑤의 배너 경계 — LEGAL-1·REF-1 판정식(@legal_banner·@referral_banner)을 임시 통합 테스트(삭제됨)에서 정식 테스트로 고정 |
| `test/controllers/app/legal_documents_controller_test.rb` | +1 | ③의 download 404 격리 |
| `test/controllers/app/referrals_controller_test.rb` | 0(수정 없음) | ② 활성화 확인만 |

### 2.3 테스트 오류 1건 (자체 수정 — 코드 버그 아님)

- 증상: 시스템 테스트에서 로그인 flash("로그인되었습니다.")는 뜨나 직후 모든 방문이 /session/new로 되돌아감(2026-10-12 기준일).
- 원인: `Authentication::SESSION_COOKIE_MAX_AGE = 30.days` — 세션 쿠키 `expires`는 **실제 시계**로 평가된다. 2026-10-12 + 30일 = 2026-11-11(오늘)이라 Chrome이 쿠키를 만료 처리. travel_to 기준일 + 30 > 오늘이어야 브라우저 세션이 유지된다(기존 시스템 테스트가 우연히 이 조건을 만족하는 날짜 사용).
- 수정: 기준일을 2026-11-20으로 이동(delta_overdue는 여전히 D+80 초과 unsettled — 시나리오 유효). 테스트 파일 주석에 경위 기록.

## 3. 전체 게이트 (7-S)

- `bin/rails test` 전체 1회: **1,103 runs, 6,329 assertions, 0 failures, 0 errors, 0 skips** — 1,088건 기준 회귀 0 + 보강 6건 포함
- `bin/rubocop`(보강 4파일) — no offenses
- 외부 API 실호출 0 — 포트원은 FakePortOneClient·with_portone_client stub, 솔라피는 본 배치 테스트에서 호출 경로 없음(reminders 기존 테스트는 FakeSolapiClient 유지)
- test DB 잔존 없음 — 트랜잭션 롤백 표준 구조, AS 첨부 생성 없음(본 배치 테스트는 Active Storage 미사용)

## 4. 코드 버그 절

없음. Phase 6 수정(B-1 병합·C-1 워터마크·C-2 가드·download 미결제 가드)은 보강 테스트 6건 전부로 부정하지 못했다.

## 5. Rule ID 커버 요약 (보강 기여분)

| Rule | 보강 |
|---|---|
| LEGAL-1 | 배너 경계(D+31 노출·30/29 미노출·paid/draft 미노출) 정식화 |
| LEGAL-2 | 브라우저 레벨 미리보기 vs 정식 PDF 바이트 비교·paid 버튼 전환 |
| LEGAL-3·4 | 배너·PDF 시스템 테스트에서 "우체국"·LEGAL_NOTICE 렌더 확인 |
| REF-1~4 | referrals 6건 활성 실행·고지 5종 본문 단정 |
| REF-3 | 코드 grep 판정 — 전송 경로 구조적 부재(테스트 불요) 문서화 |
| 소유권(SEC) | legal_doc 주문 show+download 404 쌍방 격리 |

## 6. 결론

리뷰 Tester 제안 5건 전부 처리(①~⑤). 전체 스위트 회귀 0. 코드 버그 0 — F-LEGAL/REF 배치는 게이트 통과.

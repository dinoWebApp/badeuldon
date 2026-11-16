# 05_review — F-LEGAL/REF 병렬 배치(T-F1 LEGAL·T-F2 REF + 3-S 결선) Phase 5 + 재리뷰

날짜: 2026-11-11 · Reviewer(GLM-5.3) · 대상: git 미커밋 T-F1/T-F2/3-S + Phase 6 수정
재현 방식: 컨트롤러 경유 Integration HTTP 재현(U1 실로그인·비인증·FakePortOneClient stub·pdftotext) — 임시 테스트는 실행 후 삭제, 레코드는 트랜잭션 롤백 무잔존

## Status: APPROVED  (재리뷰 루프 1/2 — 2026-11-11)

최초 리뷰: CHANGES_REQUESTED(B-1 BLOCKER 1 · C-1·C-2 CRITICAL 2 · W-1~W-5 WARNING 5)
Phase 6 수정 후 재리뷰: **7건 전부 해소 확인 — 신규 BLOCKER·CRITICAL 0** → APPROVED

---

## 1차 리뷰 이슈 목록 (Phase 6 수정 후 재검증 결과)

| # | Severity | Rule ID | File | 1차 판정 | 재리뷰 검증 결과 |
|---|----------|---------|------|----------|------------------|
| B-1 | BLOCKER | LEGAL-2·PLAN-5 | fulfill_pass_service:19·purchase_service:99,113 | metadata 덮어쓰기로 paid 후 download 영구 파탄(HTTP 재현) | **해소** — 3쓰기 지점 전부 병합 전환(`merged_metadata`·keep_pending·record_failure). 독립 재현 3경로 전부 통과: ① create→웹훅 확정→`metadata["invoice_id"]` 보존→download %PDF 200·패스 미발급 ② 콜백(즉시승인 recheck) 경로 동일 ③ **모호 실패→웹훅 회복** 경로(회복 대기 시점과 확정 시점 모두 invoice_id 보존 + `pending_recovery` 병합). 개발자 서비스 회귀 3건 + 컨트롤러 전 체인 테스트 신설 확인 |
| C-1 | CRITICAL | LEGAL-2(PRD v0.38) | legal_documents_controller download·content_proof_pdf_service | 워터마크 미리보기 미구현 — PRD "미결제는 워터마크 미리보기만" 불일치 | **해소(구현으로 정합화)** — `watermark:` 옵션(stamp·rotate 38°·transparent 0.22 "미리보기 — 미결제" 전 페이지). 독립 실측: 미결제 download 바이트 == `watermark: true` 서비스 출력 ≠ `watermark: false` 정식 출력, pdftotext에 회전 글리프 파편 실렌더 확인 + LEGAL-3 고지 유지. paid download 바이트 == 정식 PDF(watermark 무영향 실측). show(대기) 미리보기 링크 추가 확인 |
| C-2 | CRITICAL | LEGAL-2 | legal_documents_controller:100-110 | paid 주문 존재 시 재주문 허용(이중 결제 경로) — 주석·문서·동작 불일치 | **해소** — `find_paid_legal_order` 가드(paid → pending 재사용 → 신규 순). 독립 재현: paid 후 create → `assert_no_difference` + 기존 주문 show 303 + notice "이미 결제가 완료되었습니다" 실측. **pending 연타 멱등은 유지**·**failed 주문 존재 시 재주문은 정상 허용**(신규 생성 실측) 확인. 주석이 실제 동작과 일치하도록 정정됨 |
| W-1 | WARNING | LEGAL-1 | legal_documents_controller:15,22 | @legal_targets N+1(client.name) | **해소** — index·new `includes(:client)` 확인 |
| W-2 | WARNING | INV-1·표기 | legal index view:35 | 대상 목록 금액이 net_amount(표기 불일치) | **해소** — `total_amount` 통일 확인 |
| W-3 | WARNING | LEGAL-2(정책) | download | 마감 후 대가 지급 완료 문서 재다운로드 차단 | **해소(정책 확정: 허용)** — `enforce_target: !@order.paid?`. 독립 재현: 청구 마감 후 paid 주문 재다운로드 200 %PDF 실측. 반대 경계도 가드 유지: 미결제 주문 + 마감 청구 → LegalDocNotAvailable 리다이렉트 + 마감 청구 create 차단 실측 |
| W-4 | WARNING | P4 | download | 다운로드 행위 기록 없음(확인 요청) | **판정 동의(기록 불요)** — 아래 §3 참조. 주석·03 문서화 확인 |
| W-5 | WARNING | — | new·show | new @invoice 사코드·payment_failed 미소비 | **해소** — @invoice 제거·show에서 `flash.now` alert "결제가 승인되지 않았습니다" 소비 실측(콜백 실패 → `?payment_failed=1` 착지 → flash 노출) |

## Phase 6 재리뷰 재현 커버리지 (독립 재현 10건 81 assertions — 전부 통과 · 임시 파일 삭제 완료)

1. **B-1 웹훅 경로 전 체인**: create → Transaction.Paid 확정 → invoice_id 보존 → download %PDF 200 → pdftotext에 청구번호·LEGAL-3 고지 + **정식 PDF에 워터마크 문구 부재** + PaymentPass 미발급 ✓
2. **B-1 콜백 경로**(즉시승인 recheck PAID): invoice_id 보존 → %PDF 200 ✓
3. **B-1 모호 실패→회복**: TIMEOUT → pending + invoice_id·pending_recovery 병합 보존 → 웹훅 확정 → invoice_id 보존 → %PDF 200 ✓
4. **C-1 워터마크 3중 실측**: 미결제 download == `watermark: true` 출력 · ≠ 정식 출력 · pdftotext 글리프 파편("제결" — rotate 38° 파편화) + LEGAL-3 고지 포함 ✓
5. **C-2**: paid 후 재주문 차단(no_difference + notice)·pending 연타 멱등 유지 ✓
6. **failed 후 재주문 허용**: 새 pending 생성 ✓
7. **W-3**: 마감 후 paid 재다운로드 200 / 미결제+마감 청구는 가드 리다이렉트(양방향 경계) ✓
8. **pass 주문 회귀(병합 무영향)**: preset metadata(`source`) 보존 + `status` 병합 + `invoice_id` 부재 + 패스 10건 발급 ✓ — 부가 확인: `Subscriptions::UpgradeService`는 기존부터 병합 패턴 선례("덮어쓰기 아님 — P4" 주석·coupon_metadata 병합)로 병합 전환은 기존 컨벤션과 일치. pass 주문 metadata의 소비자는 없어 병합 유입 무영향 — 관련 스위트(purchase_service 14·concurrency·webhook 10) 0 fail로 뒷받침
9. **격리 재확인**: 타인 legal_doc 주문 show·download 404 ✓
10. **W-5**: 콜백 실패 착지 → show에서 안내 flash 노출 ✓

기존 관련 스위트 재실행: legal_documents_controller 8·purchase_service+concurrency·webhooks 10·content_proof 7·order_item_type 6·referrals 6·orders_controller·invoices_controller 37·invoice model = **141 runs, 825 assertions, 0 failures**. (오케스트레이터 확인치 Phase 6 게이트 — rubocop 0 offenses·zeitwerk OK 수용)

## §3 W-4 판정 — "다운로드 기록 불요"에 대한 Reviewer 판단

**동의.** P4("모든 발신은 기록")의 기록 대상은 채무자·U1에게 나가는 발신(알림톡/SMS → message_logs 등)이며, PDF 다운로드는 발신이 아니다. 발급·결제 이력은 orders 레코드 자체가 담보한다(item_type·amount·paid_at·pg_payment_id·metadata.invoice_id — ADMIN orders/show에서 metadata inspect 노출까지 확인). 유료 문서 배포 증빙이 향후 필요해지면 그때 download 로그 보강을 검토하면 충분 — 현재 시점 기록 추가는 과잉 계측이다.

## 기타 관찰 (이슈 아님 — 기록 목적)

- 미리보기·정식 PDF의 파일명이 동일(`내용증명_{청구번호}.pdf`) — 사용자 다운로드 폴더에서 구분 불가. 미세 UX 포인트로 후속 여지(예: `_미리보기` 접미사). 차단 사유 아님
- FulfillPassService라는 서비스명이 legal_doc(paid 전환만) 확정도 담당하게 됐으나, SEC-5 공유 확정점 설계상 자연스러운 귀결 — 리네임은 이익 대비 리플 비용이 커서 유지 타당

## Rule ID 준수 매핑 (최종)

| Rule | 판정 | 근거 |
|---|---|---|
| LEGAL-1 | ✓ | legal_target?(unsettled+D+30 초과 단일 출처)·청구 내역·발송 이력(REM-6·10건)·약속(Q14)·부분입금·Prawn+Pretendard TTF |
| LEGAL-2 | ✓ | 5,000원 서버 원값·item_type 마이그레이션·**미결제 워터마크 미리보기(PRD v0.38 문언 준수)**·paid 정식 PDF·이중 결제 차단(C-2 가드)·metadata invoice_id 보존(B-1 병합) |
| LEGAL-3 | ✓ | LEGAL_NOTICE — new·show·배너·PDF(미리보기 포함) |
| LEGAL-4 | ✓ | DIRECT_SEND_NOTICE — index/new/show/배너/PDF |
| REF-1~4 | ✓ | 배너+버튼→소개 화면·P5 고지·자료 범위·계약 따름 고지·외부 전송 경로 0 |
| PLAN-5 | ✓ | 포트원 단건 플로우 재사용·webhook settle_paid legal_doc 차단·병합 전환은 구독 UpgradeService 선례와 동일 패턴 |
| INV-4·REM-6·Q14·TIME-1 | ✓ | unsettled 스코프·message_logs 인용·약속 2상태 판정·KST |
| TAX·Q13 | ✓ | 런 분리 유지·본 배치 범위 외 |
| SURF-3·P4 | ✓ | /app noindex·주문 레코드가 발급 기록(download 행위 기록 불요 — §3 판정) |

## Tester에게 제안하는 중점 테스트 영역

1. **E2E 수금 루프+LEGAL**: 발행→열람→리마인더→(D+31)내용증명 미리보기→결제→정식 PDF→(입금 마감)→재다운로드까지 시스템 테스트 1본
2. **B-1 삼중 경로 회귀 유지**: 웹훅·콜백·모호실패+회복 — metadata.invoice_id 보존 어서션가 병목 시 알림
3. **C-2 경계**: paid 차단·pending 재사용·failed 재주문 허용 3분기
4. **D+30 경계 + unsettled 전이**: +30 거부/+31 허용·발급 후 청구 paid 전환 시 신규 발급 차단·미결제 주문+마감 청구 가드
5. **실기기(in앱 브라우저) 워터마크 시각 확인**: rotate 38°·opacity 0.22가 인쇄·스크린샷에서 실제로 방해되는지 VIEW-1 QA에 포함

## 결론

1차 지적 7건(B-1·C-1·C-2·W-1~W-5)이 전부 실제 동작 수준에서 해소됐고, 수정으로 유입된 회귀(metadata 병합의 기존 pass·구독 결제 무영향, 워터마크 옵션의 정식 PDF 무영향)도 실측으로 부정하지 못했다. 신규 이슈 없음.

**Status: APPROVED**

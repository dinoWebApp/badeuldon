# 01_plan.md — F-PAY 입금 처리 (MVP 마지막 조각)

- **일자**: 2026-10-13
- **pipelineType**: Full — 신규 엔티티(Payment)·마감 플로우·DASH 재계산
- **도메인**: F-PAY (§6.8) + INV-4(paid/partially_paid 전이) + DASH-1 재계산·DASH-2 소멸

## A. 구현 범위

### A-1. Payment 모델·마이그레이션
- `Payment`: invoice_id(FK·인덱스), amount(integer 원 >0), paid_on(date — 기본 오늘, 과거 허용·미래 차단), created_at
- Invoice has_many :payments (dependent: :destroy — 연쇄 순서 주의)
- 검증: amount > 0·상한(총액 잔액 초과 등록 **차단** — 결정 #3), paid_on 미래 차단·당일/과거 허용

### A-2. 마감·부분입금 로직 (Service — 다중 쓰기·전이)
- `Payments::RecordService`: Payment 생성(트랜잭션) + 합계에 따른 전이
  - 합계 ≥ 총액 → **`mark_paid!`(원자 전이)** — PAY-1 원클릭 마감(잔액 0)·입금일 = 마감 Payment.paid_on 자동 기록
  - 합계 < 총액 → `mark_partially_paid!`(미수 계열 → partially_paid) — PAY-2 잔액 자동 재계산
- 원클릭 전액 마감(PAY-1): 상세 화면 「입금 확인하고 마감」 버튼 — 잔액 전액 Payment 1건으로 마감(날짜 기본 오늘)
- 전이 가드: voided·draft·이미 paid 마감 불가(422) — INV-4 준수. overdue는 파생 판정이라 부분입금 경로 포함
- **잔액 계산**: total_amount - Σ payments — DASH-1 미수 총액·연체 금액도 **잔액 기준 재계산**

### A-3. 화면 (표면 ② — 청구서 상세)
- 입금 섹션: 입금 이력 목록(금액·날짜)·잔액 표시(tabular)·
  - 「입금 확인하고 마감」 버튼(turbo_confirm — PAY-1)
  - 「부분입금 기록」 폼(금액·날짔 — PAY-2)
- paid 상태: 「수금 완료」 배지(녹색 DESIGN-2)·입금 이력 확정 표시·추가 기록 차단
- **DASH-2 마감 대기 소멸**: paid_report 있던 청구서 마감 시 「마감 대기」 카드에서 제거
- 뷰어(③): 변경 없음 (마감 권한은 U1만 — PROMISE-7 구조 유지)

### 후속 제외 (명시)
- **PAY-4 감사 알림 발송** — 채널(알림톡·핵클) 미계약, SHARE-4/PROMISE-4 선례 연기 (결정 #1)
- PAY-6 수금 완료 증빙 PDF — VIEW-4 PDF와 함께 후속
- PROMISE-5 이행/미이행 거래처 카드 기록 — CLIENT-3/4와 함께 (이행 판정 데이터는 이번부터 축적)
- PAY-5 계좌조회 자동화 — **구현하지 않음이 규칙 준수** (미구현 확정)

## B. 관련 Rule ID
PAY-1/2(+3 뷰어 기존·5 부구현), INV-4(paid·partially_paid), DASH-1(잔액 재계산)·DASH-2(마감 대기 소멸), PROMISE-7(마감은 U1만), DESIGN-2(완료 녹색), TIME-1, SEC(마감 멱등 — 이중 클릭 방지)

## C. 결정 사항 (제안)
1. **PAY-4 감사 알림 연기** — 채널 계약 시 옵션(기본 켬)과 함께 추가
2. **PAY-6 PDF 후속**
3. **부분입금 한도**: 잔액 초과 등록 **차단**(422) — 초과 입금은 기록 불가, 정확한 마감만 허용
4. **마감 입금일**: 마감 시점 등록 값(기본 오늘, 과거 지정 가능)

## D. 리스크
- 이중 클릭/동시 마감 — 원자 전이+잔액 재검증으로 멱등 보장(리뷰·테스트 집중)
- 부분입금 반복 한계(잔액 0 도달) — 합계 전이 정확성
- DASH-1 집계 변경으로 기존 카드 테스트 갱신 다수 (Phase 7)

# 01_plan.md — F-INV 청구서 발행 (핵심 엔티티)

- **일자**: 2026-10-12
- **pipelineType**: Full — 신규 도메인(Invoice·InvoiceItem)·마이그레이션·대시보드 전환 (최대 규모 파이프라인)
- **도메인**: F-INV (§6.4) + SHARE-1/2(토큰 데이터 최소) + DASH-1/4 실데이터 전환 + PLAN-1(월 3건)

## A. 구현 범위

### A-1. 모델·마이그레이션
- `Invoice`: user_id·client_id(FK), issue_number(**INV-1** 자동 채번 `BD-YYYYMMDD-NNN` 일별 순번·고유), status(**INV-4** enum: draft/issued/viewed/overdue/promised/partially_paid/paid/voided), due_on(**INV-3** 발행일+30일 기본), tax_mode(부가세 별도/포함 — INV-1), withholding_enabled(**INV-2** boolean — 프리랜저 기본 반영), 발행자 표시명 스냅샷, 입금 계좌 스냅샷(은행·계좌·예금주 — INV-1 "프로필 기본값 또는 건별 변경"), 총액·공급가액·부가세·원천징수액·실수령액(계산 컬럼), token·token_expires_at(**SHARE-1/2** — 발행 시 생성, 만기+60일), issued_at, voided_at
- `InvoiceItem`: invoice_id(FK), description·quantity·unit_price(원) — 복수 행
- 금액 계산: 합계 = Σ(수량×단가) → 부가세 별도 시 +10% / 포함 시 내역 분해. 원천징수 시 공급가액의 3.3% 차감·실수령액 표기(INV-2) — 정수 원 반올림 규칙 명시

### A-2. 상태 전이·비즈니스 규칙
- **INV-4 전이**: `draft → issued(발행)`, `issued → voided(무효)`. viewed/promised/partially_paid/paid는 enum 예약(이벤트 도메인 SHARE/PROMISE/PAY에서 진입) — **연체 표시는 만기일 비교 파생 판정**(scope, DASH-4 연체일 계산)으로 이번에 구현, enum 자동 전환은 REM 시점
- **INV-5 발행 후 본문 수정 불가**: 수정 액션 가드(draft만 허용)
- **INV-6 무효**: member `void` — 토큰 즉시 폐기·voided_at 기록 (시퀀스 중단은 REM 부재로 N/A)
- **PLAN-1 월 3건**: 발행(초안→issued) 시 당월 발행 수 ≥3 차단 + Plus 안내 (FREE_MONTHLY_INVOICE_LIMIT 상수 — 거래처 한도 패턴 재사용)

### A-3. 화면·플로우 (표면 ②)
- `/app/invoices` 목록(상태 뱃지·연체일·금액 — DASH-4 연체일 내림차순), 상세(금액 내역 INV-2 표기·무효 버튼), **초안 작성·수정 폼**: 거래처 select(CLIENT 연결)·품목 행 동적 편집(라이브러리 선택 CLIENT-2 + 직접 입력)·부가세 모드·원천징수(프리랜저 기본 반영)·만기일·계좌(프로필 기본 프리필)·금액 실시간 요약
- 발행 버튼 → issue 액션(채번·토큰 생성) → 상세. **링크 복사 UI는 F-VIEW에서 개봉**(뷰어 없는 링크 노출 금지 — 발행 상세에는 「링크는 뷰어 오픈 후 제공됩니다」 안내 없이 링크 미노출)
- **대시보드 전환**: DASH-1 카드 3종 실데이터(미수 총액·연체 건수·금액·7일 내 만기 — issued 계열·만기 미경과 등 Query 계산) / DASH-4 목록 = 청구서 목록(빈 상태 교체) / **ONB-1 CTA 활성화** → /app/invoices/new / DASH-2는 이벤트 부재로 빈 상태 유지(REM/PROMISE 의존)
- 사이드바 「청구서」 활성화

### 후속 제외 (명시)
SHARE-3/4(열람 추적·알림), 뷰어(표면 ③ F-VIEW), 발송(REM·핵클), 반복 청구(INV-7), PDF(VIEW-4), PAY 상태 전환, 만기일 설정 변경 UI(설정 도메인), 부분입금

## B. 관련 Rule ID
INV-1~6, SHARE-1/2(데이터), PLAN-1(월 3건), PLAN-3 아님, DASH-1/4, ONB-1, CLIENT-2(품목 선택), SURF-3, DESIGN-2(상태색 3종 뱃지)·5, TIME-1(KST)

## C. 결정 사항 (제안)
1. **링크/토큰**: 발행 시 생성(데이터)하되 UI 노출은 F-VIEW 시점 — 뷰어 없는 링크 노출 금지
2. **연체 표시**: 파생 판정(만기일 비교) — enum 자동 전환은 F-REM에서 스케줄러와 함께
3. **월 3건 한도**: 발행 시점 적용(초안 무제한) — FREE_MONTHLY_INVOICE_LIMIT 상수
4. **금액 반올림**: 원천징수 3.3%는 공급가액 기준 내림(정수 원) — 표기 시 원 단위

## D. 리스크
- 최대 규모 구현(폼 복수 행·계산·전이) — Developer 스폰 1회, 리뷰 집중 필요(특히 금액 계산 경계: 0원 행·대량·부가세 포함+원천징수 조합)
- 대시보드 기존 빈 상태 테스트 갱신 다수 발생 (Phase 7)
- 부가세 포함 모드의 역산(합계→공급가액 분해) 반올림 경계

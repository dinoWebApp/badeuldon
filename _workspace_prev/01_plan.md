# 01_plan.md — F-PROMISE 응답(약속) 수집

- **일자**: 2026-10-13
- **pipelineType**: Full — 신규 엔티티(Promise)·뷰어 액션 UI·DASH-2 첫 실데이터
- **도메인**: F-PROMISE (§6.7) + F-VIEW 확장(VIEW-4) + F-DASH 일부(DASH-2)

## A. 구현 범위

### A-1. Promise 모델·마이그레이션
- `Promise`: invoice_id(FK·인덱스), kind enum(**PROMISE-1 4종**: `this_week` 이번 주 내 / `date_selected` 예정일 지정 / `paid_report` 이미 입금 / `inquiry` 문의·이의), promised_on(date — this_week는 결정 #1에 따라 산정, date_selected는 채무자 지정, 나머지 null), memo(text — inquiry 전용), answer(text — U1 답변, PROMISE-6), answered_at, created_at=접수시각
- 검증: inquiry는 memo 필수(길이 상한 2,000), date_selected는 promised_on 필수(과거 날짜 허용? — 당일 가능, 어제 이전 차단), answer는 U1만 기록 가능(컨트롤러 가드)

### A-2. 채무자 응답 플로우 (뷰어 ③ — VIEW-4 개봉·PROMISE-2)
- 뷰어에 **액션 버튼 4종**(PROMISE-1 원문 문구): 「이번 주 내에 입금할게요」 / 「입금 예정일 지정」(native date input — 인앱 호환) / 「이미 입금했어요」 / 「문의·이의 있어요」(textarea)
- **비가입·무입력**(PROMISE-2): 버튼 누르면 즉시 기록 — 개인정보·가입 요구 전무. 토큰 보유=응답 권한
- 응답 후 완료 화면(문구는 P1 톤 — 「감사합니다. 발행인에게 전달했습니다」), 문의는 답변 등록 시 뷰어에서 확인(PROMISE-6 — 서비스 경유, 연락처 노출 없음 P2)
- rate_limit(스팸 응답 방지 — 토큰당), noindex 유지
- 상태 전이: this_week/date_selected 등록 시 invoice **issued/viewed→promised**(INV-4) · paid_report·inquiry는 상태 불변(PROMISE-7 — 마감은 U1만)

### A-3. U1 측 (표면 ②)
- 청구서 상세: 약속 이력 타임라인(종류·약속일·접수시각) + 문의 답변 폼(PROMISE-6 — 답변 등록 303)
- **DASH-2 오늘의 액션 첫 실데이터**: 「마감 대기」(paid_report 접수·미처리) + 「답변 대기」(inquiry 무답변) 카드 — 기존 빈 상태에서 조건부 표시

### A-4. PROMISE-7 처리
- 「이미 입금했어요」 접수: Promise(paid_report) 기록 → DASH-2 마감 대기 표시 → U1이 청구서 상세에서 확인. **수금 마감은 PAY에서 U1 확인으로만** — 이번엔 회신 기록+표시까지만

### 후속 제외 (명시)
- PROMISE-3 시퀀스 재스케줄(D-1/D+1 리마인드) — REM·핵클 계약 후
- PROMISE-4/7 U1 알림 발송 — 채널(알림톡) 미계약, SHARE-4와 동일 연기 (DASH-2 표시로 인지)
- PROMISE-5 이행/미이행 거래처 카드 기록(CLIENT-3/4) — PAY 마감 데이터 필요
- PDF, 반복 요청 스레드(1문의 1답변 구조)

## B. 관련 Rule ID
PROMISE-1/2/6/7, PROMISE-3(상태·약속일 저장까지만), VIEW-4/8(액션 추가 — 화이트리스트 내), INV-4(promised 전이), DASH-2(마감·답변 대기), P1(문구 톤)·P2·P3, TIME-1

## C. 결정 사항 (제안)
1. **「이번 주」 약속일 산정**: 접수일 기준 **이번 주 금요일**(주말 지나면 다음 주 금요일) — REM-3 평일 기준과 정합
2. **알림 발송(PROMISE-4/7) 연기**: SHARE-4 선례와 동일 — DASH-2 표시로 인지, 계약 시 연결
3. **date_selected 과거 날짜**: 어제 이전 차단(당일 가능) — 유효 약속만
4. **문의 답변**: 1문의 1답변(추가 문의는 새 버튼) — 단순 구조, 스레드는 필요 시 확장

## D. 리스크
- 비인증 기록 경로의 스팸/오남용 — rate_limit + 토큰 엔트로피 방어, 리뷰 집중
- promised 전이 후 재응답(약속 변경) — 최신 약속으로 갱신? 이력 보존? → 이력 보존+최신 반영(promised_on은 최신 약속 기준) — 리뷰 확인
- 인앱 date input 동작 — 전 브라우저 허용 정책으로 네이티브 UI 위임

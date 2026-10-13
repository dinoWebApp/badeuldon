# 01_plan.md — F-SHARE 열람 추적 + F-VIEW 채무자 뷰어 (표면 ③ 개봉)

- **일자**: 2026-10-12
- **pipelineType**: Full — 신규 엔티티(ViewEvent)·신규 표면(③)·링크 UI 개봉
- **도메인**: F-SHARE (§6.5) + F-VIEW (§6.11) + SURF-2/3/4

## A. 구현 범위

### A-1. 열람 추적 (SHARE-3) + 상태 전이 (INV-4)
- `ViewEvent` 마이그레이션·모델: invoice_id, first?(boolean — 최초/재열람), device(mobile/pc — User-Agent 대략 판별), viewed_at, ip(기록만)
- `GET /b/:token` (비인증, 토큰 상수시간 비교 `secure_compare`):
  - 유효 토큰·미만료·미폐기 → 뷰어 렌더 + **트랜잭션 내** ViewEvent 기록 + **최초 열람 시 invoice issued→viewed 전이**(INV-4)
  - 토큰 조회는 `Invoice.find_by(token:)` — 엔트로피 256bit로 열거 무의미, 타이밍 보강(secure_compare 또는 동등 처리)
- **SHARE-4 U1 알림**: 이번 파이프라인은 **연기** (결정 #1) — 발송 채널이 NOTI-1 알림톡(핵클 미계약)이라 실발송 불가. ViewEvent·viewed 전이로 근거 데이터는 완비, 대시보드 청구서 뱃지 「열람」으로 U1 인지 가능. 채널 계약 시 REM/NOTI 파이프라인에서 연결

### A-2. 링크 UI 개봉 (SHARE-1/2/6 — 표면 ②)
- 발행 상세(issued 계열): 링크 URL 표시 + **복사 버튼**(Stimulus — navigator.clipboard) + **재발급 버튼**(SHARE-2 수동 폐기·재발급 — 기존 링크 즉시 무효·신규 토큰·만기 유지, turbo_confirm)
- 링크 만료 임박/만료 상태 표시(만기+60일 경과 시 「링크 만료」 + 재발급 안내)
- SHARE-6 발송 방식: **링크 복사만 제공** (서비스 명의 알림톡 옵션은 REM·핵클 계약 후 — 결정 #2)
- voided·만료·재발급 이전 링크 접근 → VIEW-6 안내 화면

### A-3. 뷰어 화면 (표면 ③ — VIEW-1/2/3/5/6/8)
- **전용 레이아웃** `layouts/viewer.html.erb`: 앱 내비·푸터 없음(마케팅 무결성 VIEW-8·SURF-2), 흰 배경 문서형(DESIGN-4 — 문서 무결성, 색 최소), noindex(SURF-3 — /b/* robots 차단 포함)
- **VIEW-2 상단**: 「받을돈을 통해 **[발행인 표시명]**님이 보낸 청구서입니다」
- **VIEW-3 구성**: 청구번호·발행일·만기일·품목 표(설명·수량·단가·금액)·총액(부가세 포함/별도·원천징수 내역 — INV-2 분해 표기)·**입금 계좌 클릭 복사**(토스 송금 UX 벤치마크 — 큰 영역·복사 피드백)·**입금자명 안내**(PAY-3 「입금 시 입금자명을 '거래처명'으로」)
- **VIEW-5 하단 고지**: 「본 청구서는 발행인이 직접 발행했습니다. 본 서비스는 채권 추심 업무를 수행하지 않습니다.」 (P5)
- **VIEW-6 만료·폐기 화면**: 안내 문구 + 「발행인에게 연락해 주세요」 (③→① 링크 금지 SURF-4 — 링크 없음)
- 모바일 우선(기본 글자 크기 상향 DESIGN-6, 터치 타깃)

### 후속 제외 (명시)
SHARE-4 알림 발송(채널 계약 후), SHARE-5 문구 분기(REM), VIEW-4 응답 버튼(F-PROMISE)·PDF, VIEW-7 수신 거부(REM), INV-7

## B. 관련 Rule ID
SHARE-1/2/3(+4 연기), VIEW-1/2/3/5/6/8, INV-4(viewed 전이), PAY-3(입금자명 안내), SURF-2/3/4, DESIGN-4/6, P3/P5, TIME-1

## C. 결정 사항 (제안)
1. **SHARE-4 알림 발송 연기** — 채널(NOTI-1 알림톡·핵클) 미계약. viewed 전이+대시보드 뱃지로 인지 확보, ViewEvent로 발송 근거 데이터 완비
2. **SHARE-6**: 링크 복사만 제공 (서비스 발송은 REM 시점)
3. **시스템 테스트 도입**: 뷰어 여정(랜딩 아님 — 발행→링크→뷰어 렌더·복사·열람 전이) capybara 첫 적용 (VIEW-1 QA의 자동화 가능분)
4. **IP 기록**: ViewEvent에 ip 저장(알림·분석 근거) — 개인정보 최소 수집 원칙(SURF/SEC-3)과 정합 여부 확인 필요시 익명화

## D. 리스크
- 토큰 타이밍 공격 — secure_compare 적용하나 find_by(token:) 자체가 DB 색인 조회라 실익 제한적(256bit) — 리뷰 검증
- 클립보드 복사는 비보안 컨텍스트(localhost http) 제약 — fallback(수동 선택) 제공
- 인앱 브라우저 실기 QA는 수동(VIEW-1) — 자동화는 시스템 테스트로 한계 커버

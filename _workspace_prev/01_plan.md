# 01_plan.md — F-CLIENT 거래처·품목 관리

- **일자**: 2026-10-12
- **pipelineType**: Full (Phase 0→1→✋→2→3→4→5→7→8→9) — 신규 도메인 2엔티티·마이그레이션
- **도메인**: F-CLIENT (PRD §6.3) + PLAN-1 연계

## 범위 (PRD 원문 기준)

| Rule | 내용 | 이번 구현 |
|:---|:---|:---|
| **CLIENT-1** | 거래처 등록/수정/삭제 — 거래처명, 담당자명, 알림 수신 휴대폰 번호, 이메일(선택), 사업자번호(선택), 메모 | ✅ CRUD 전체 |
| **CLIENT-2** | 품목 라이브러리 — 품목명·단가 저장, 청구서 작성 시 선택 | ✅ CRUD (선택 UI 연동은 F-INV) |
| CLIENT-3 | 거래처 카드 — 누적 청구액·진행 건수·약속 이력 | ❌ F-INV/F-PROMISE 후속 (데이터 없음) |
| CLIENT-4 | 지급 성적표 | ❌ PAY 완료 후속 |
| **PLAN-1** | Free 거래처 한도 5개 | ✅ 적용 (아래 결정 #1) |

## 구현 설계

### 모델·마이그레이션
- `Client`: user_id(FK), name(필수), contact_name(필수), phone(필수 — 휴대폰 형식 느슨 검증), email(선택), business_number(선택), memo(선택). `dependent: :destroy` 없음(참조 없음 — F-INV 시 정책 확정 시까지), 소유권 스코프
- `Item`: user_id(FK), name(필수), unit_price(정수 원, 필수 ≥0). 품목명·단가만 (PRD 명시 필드 외 추가 금지)

### 컨트롤러·화면 (표면 ②, App::BaseController 가드 상속)
- `/app/clients` — 7종 표준 CRUD. 목록(카드/테이블) + 등록·수정 폼(모달 Frame 또는 페이지 — §3.3 표준), 삭제 turbo_confirm
- `/app/items` — 품목 라이브러리 CRUD (단순 목록+폼)
- Turbo: 성공 303/실패 422, 생성·삭제 후 목록 갱신 Stream(§7.3) 또는 redirect — 컨벤션 따름
- 사이드바: 「거래처」 활성화(준비 중 해제) + 「품목」 메뉴 신규(결정 #2)

### PLAN-1 한도 (결정 #1)
- `Client` 등록 시 `user.clients.count >= 5`면 차단 + 「Free 플랜은 거래처 5개까지입니다. Plus로 무제한 이용할 수 있습니다」 안내 (PLAN-2 승격 유도 문구)
- 구현: 모델 검증 or 컨트롤러 가드 — 상수 `FREE_CLIENT_LIMIT = 5` (F-PLAN에서 구독 체크로 교체)

## 후속 제외
CLIENT-3/4(데이터 의존), 품목 선택 UI(F-INV), 청구서 연동, 삭제 시 진행 중 청구 정책(F-INV 시 INV 규칙과 함께)

## 관련 Rule ID
CLIENT-1, CLIENT-2, PLAN-1(한도), SURF-3(/app noindex — 상속), DESIGN-4/5/6(UI 기준), LP-12(한도 안내 문구)

## 결정 사항 (제안)
1. **Free 거래처 5개 한도**: 지금 적용(전 사용자 Free 취급, 상수) — F-PLAN에서 구독 체크로 전환. 근거: PLAN-1이 현행 규칙
2. **품목 진입점**: 사이드바 「품목」 메뉴 신규 추가 (거래처와 별도 리소스 — 청구서 발행 시 선택은 F-INV)
3. **거래처 삭제**: 참조(청구서)가 없는 현재 즉시 삭제 — F-INV에서 INV-6 연계 정책 확정

## 리스크
- phone 형식 검증 과잉 시 등록 마찰 — 느슨한 패턴(숫자·하이픈 허용) + 표준화는 발송 도메인(REM)에서
- 한도 상수가 F-PLAN에서 이중 로직 될 가능성 — 상수 단일 지점 유지

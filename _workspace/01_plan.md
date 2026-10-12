# 01_plan.md — /app 대시보드 뼈대 (표면 ② 셸)

- **일자**: 2026-10-12
- **pipelineType**: Full (Phase 0→1→✋→2→3→4→5→7→8→9) — 마이그레이션 없음
- **도메인**: F-DASH(§6.9) + F-SURF(표면 ②) + F-ONB(첫 발행 훅)
- **요청**: /app 대시보드 뼈대 — F-CLIENT·F-INV 데이터가 없으므로 **셸+빈 상태** 중심

## A. 구현 범위 (Phase 3 Developer)

### A-1. 레이아웃 분리 (기술 부채 해소 — ② 구축 시점 도래, SURF-6)

- `layouts/landing.html.erb` — 표면 ① 전용: 푸터(LP-10) 포함, 앱 내비 미포함
- `layouts/app.html.erb` — 표면 ② 전용: 사이드바 내비 + 헤더(사용자 표시명·로그아웃)
- `layouts/application.html.erb` — 공통 기반(Pretendard·flash·CSS)만
- 인증 화면(로그인/가입/재설정)은 application 공통 유지
- 랜딩의 앱 자원 의존 제거로 SURF-6 예산 분리 실질화

### A-2. /app 대시보드 셸 (`/app` → DASH 컨트롤러)

- **사이드바 내비**(shadcn dashboard-01 레퍼런스 — DESIGN-5): 대시보드(활성) · 청구서 · 거래처 (준비 중 표시) · 설정(프로필 수정 링크 — 실제 연결)
- **DASH-1 요약 카드 3종 empty-state**: 미수 총액·연체 건수·7일 내 만기 — 「0원」이 아니라 「청구서를 발행하면 표시됩니다」 안내 (데이터 없는 상태에서 거짓 숫자 금지)
- **DASH-2 오늘의 액션 empty-state**: 「오늘 할 일이 없습니다 — 첫 청구서를 발행해 보세요」
- **ONB-1 훅**: 중앙 「첫 청구서 발행하기」 CTA (F-INV 미구현 — 준비 중 상태 표시, 활성화는 F-INV 시점)
- **DASH-4 기반 목록 영역**: 청구서 목록 empty-state (연체일 내림차순 안내 문구 — 정렬 구현은 F-INV)
- noindex(SURF-3), `require_authentication` + 프로필 미완료 리다이렉트 유지

### A-3. 플로우 정리 (welcome 소멸)

- 프로필 저장 완료 → **`/app`** (welcome 화면·라우트 제거 — /app가 그 역할 대체)
- 로그인(프로필 완료) → `/app` (기존 root → 변경)
- 관련 기존 테스트 갱신 발생 (Phase 7 Tester)

### 후속 제외
DASH 실데이터(요약 수치·액션 목록·리포트 DASH-5/6 — F-INV/F-CLIENT 후), 청구서·거래처 화면 본체, 알림

## B. 관련 Rule ID

DASH-1/2(empty 구현), DASH-4(목록 영역·안내), SURF-3/4/6, DESIGN-4/5/6, ONB-1(CTA 훅), AUTH-1.3(프로필 연계), LP-12(문구 준칙 — 빈 상태 문구)

## C. 결정 사항 (제안)

1. **welcome 화면 제거**: 프로필 완료·로그인 모두 `/app` 직행 (welcome 라우트·뷰 삭제, 리다이렉트 갱신)
2. **준비 중 메뉴**: 사이드바에 청구서·거래처 메뉴를 **disabled(준비 중 배지)로 노출** — 서비스 구조 안내(랜딩 LP-3 정합)
3. **첫 발행 CTA**: F-INV 전까지 disabled 「준비 중」 — 활성화는 F-INV 시점

## D. 리스크

- welcome 제거로 기존 테스트 4~5건 갱신 (예상 범위 — Phase 7)
- 사이드바 모바일 반응형: 데스크톱 사이드바 + 모바일 상단 해시버거/하단 내비 — Tailwind 반응형으로 처리

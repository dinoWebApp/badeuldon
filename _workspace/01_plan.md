# 01_plan.md — 로그인 사용자 UX 개선 (랜딩→서비스 원클릭 복귀)

- **일자**: 2026-10-14 · **승인 완료**(사용자 "네 진행해주세요")
- **pipelineType**: Standard (3-4 파일)

## 수정 3건

1. **랜딩 헤더** (`layouts/landing.html.erb`): 세션 있으면 「대시보드로 가기 → /app」 표시(「무료로 시작하기」·「로그인」 대체)
2. **가입 화면 리다이렉트** (`RegistrationsController`): `allow_unauthenticated_access`가 이미 로그인 상태면 `/app` 302
3. **로그인 화면 리다이렉트** (`SessionsController#new`): 동일 — 로그인 상태면 `/app` 302

랜딩 자체는 로그인 여부 무관 항상 접근 가능(변경 없음).

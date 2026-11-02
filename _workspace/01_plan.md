# 01_plan — 표면 ①②③ 퍼블리싱 리뉴얼 + 랜딩 콘텐츠 재작성 (2026-11-02)

## 요구사항

1. **랜딩 콘텐츠 재작성**: 현재 랜딩은 4단계 시퀀스(LP-5)만 소개. 약속 재스케줄(PROMISE-3)·열람 분기(REM-4)·부분입금(PAY-2)·입금 회신 정지(PROMISE-7)·발송 전 사전 통보·취소(REM-11) 등 "다양한 상황 커버"를 benefit-first로 어필하도록 재작성.
2. **퍼블리싱 재구성**: 표면 ①랜딩 ②/app ③뷰어 전체. 현재 단조로운 단일 컬럼 나열식 구성을 uibowl 레퍼런스 기반의 위계·깊이 있는 구성으로 교체. **DESIGN-2 팔레트(크림·아이보리 + 딥 그린) 유지 — 구성 강화 방식**.
3. 기능 변화 없음(퍼블리싱·콘텐츠만). 라우트·모델·마이그레이션 변경 없음.

## uibowl 레퍼런스 관찰 (2026-11-02 실측 — 구현 방향 근거)

- [알파스퀘어 랜딩](https://uibowl.io/website/%EC%95%8C%ED%8C%8C%EC%8A%A4%ED%80%98%EC%96%B4?patterns=%EB%9E%9C%EB%94%A9%ED%8E%98%EC%9D%B4%EC%A7%80&patternName=%EC%A0%9C%ED%9C%B4%20%EB%A7%88%EC%BC%80%ED%8C%85)(PC·금융): 좌측 설명 텍스트 + 우측 실제 프로덕트 차트 목업의 비대칭 분할, 상단 강한 CTA — **실제 제품 화면을 목업에 담는 신뢰 장치** → 히어로에 뷰어 목업 적용
- [코빗 랜딩/리서치-구독](https://uibowl.io/website/%EC%BD%94%EB%B9%97?patterns=%EB%9E%9C%EB%94%A9%ED%8E%98%EC%9D%B4%EC%A7%80&patternName=%EB%A6%AC%EC%84%9C%EC%B9%98-%EA%B5%AC%EB%8F%85)(PC·금융): 대형 2줄 헤드라인 타이포 + 하단 3열 카드 그리드 — **타이포 위계 중심의 절제된 B2B 구성** → 시나리오 커버 섹션 카드 그리드로 적용
- [세이브(SAVE) 온보딩](https://uibowl.io/name/%EC%84%B8%EC%9D%B4%EB%B8%8C%20(SAVE)?patterns=%EC%98%A8%EB%B3%B4%EB%94%A9)(모바일·금융): 실제 화면 목업 위 코치마크·툴팁으로 기능 설명 + 하단 닷 인디케이터 → 상황별 시나리오 섹션의 미니 목업+캡션 구조로 적용
- [하나원큐 온보딩](https://uibowl.io/name/%ED%95%98%EB%82%98%EC%9B%90%ED%81%90?patterns=%EC%98%A8%EB%B3%B4%EB%94%A9)(모바일·금융): 기능 1개당 목업 1개 + 페이저(1/5) → 4단계 시퀀스 샘플(LP-5)에 스텝 페이저 적용
- uibowl은 읽기 전용 레퍼런스 DB — 참고 관찰만 반영하고 자체 DESIGN-1~7 시스템 내에서 구현

## 작업 범위

### A. 랜딩(표면①) — 콘텐츠 + 퍼블리싱 (Developer 3a)
대상: `app/views/landing/`(index·_hero·_pain·_how_it_works·_features·_message_samples·_positioning·_pricing·_faq·_closing) + `layouts/landing.html.erb` + 관련 헬퍼
- 히어로: 비대칭 분할(대형 타이포 + 실제 뷰어 목업), CTA 위계 강화
- **신규 섹션 "모든 상황, 자동으로"**: 약속 등록→재조정 / 열람 분기 문구 / 부분입금 잔액 / 입금 회신→자동 정지 4종 시나리오 카드 + 미니 메시지 목업(LP-4 benefit-first, LP-12 준수)
- **신규/강화 섹션 "자동이되, 통제는 사용자"**: REM-11 사전 통보·원클릭 취소/보류, REM-12 5통 상한·자동 종결, P4 발송 이력 — 오발송 불안 해소가 전환 포인트
- 메시지 샘플(LP-5): 4단계 유지 + 스텝 페이저·인터랙션 강화
- 섹션 간 배경 톤 변주(cream/ivory/white 리듬), 카드 섀도·hover·focus 링 등 DESIGN-6 디테일

### B. /app 대시보드(표면②) — 퍼블리싱만 (Developer 3b)
대상: `app/views/app/**` (대시보드·사이드바·공통 UI)
- DASH-1 요약 카드 3종 위계 강화(미수 총액 강조 타이포), DASH-2 오늘의 액션 리스트 아이콘·상태색 체계(연체 주황/대기 중립/완료 녹색) 적용
- 사이드바·헤더 여백 리듬·활성 상태 디테일, 빈 상태(empty state) 스타일
- 기능 추가 금지(DASH-5/6은 F-DASH 예정 항목 — 스코프 아웃)

### C. 뷰어(표면③) — 화이트리스트 내 퍼블리싱 (Developer 3c)
대상: `app/views/viewer/**` + `layouts/viewer.html.erb`
- 타이포 위계·여백·테이블 디테일, 계좌 복사 인터랙션, 응답 버튼 4종(PROMISE-1) 시각 강화
- **VIEW-8 준수 필수**: 청구 내용·응답 액션·PDF·고지문 외 요소 추가 금지, 내비·마케팅 금지, 전용 레이아웃 유지
- 인앱 브라우저 실기 QA(VIEW-1)는 이번 파이프라인 밖(기술 부채 유지) — 시스템 테스트로 커버 가능한 범위만

## 관련 Rule ID
LP-4·LP-5·LP-12, DESIGN-1~7, SURF-2·SURF-4, VIEW-1·VIEW-8, DASH-1·DASH-2·DASH-4, PROMISE-3·PROMISE-7(소구 문구 정합성), REM-11·REM-12(동일), P1~P5

## Phase 진행 (Full 파이프라인, 절약 모드)
0✅ → 1✅ → ✋승인게이트 → 2(PRD 갱신: LP·DESIGN 리뉴얼 기록, 버전 up) → 3(Developer-lite 3회 순차 위임: 3a 랜딩 → 3b /app → 3c 뷰어, 각 스폰 직후 위임 실측 기록) → 4(rubocop·zeitwerk 직접 검증) → 5(Reviewer-lite) → 6(수정, 필요 시) → 7(Tester-lite — 기존 회귀 + 시나리오 문구 검증) → 8(bin/dev 부트 + /·/app·뷰어 응답 확인) → 9(완료 보고·AGENTS.md 갱신)

## 리스크·모호점
- 뷰어(③)는 마케팅 무결성 제약(VIEW-8·SURF-2)이 커서 리뷰 BLOCKER 가능성 최대 — Reviewer 지시에 집중 항목으로 명시
- 신규 창작 문구(시나리오 섹션 카피)는 LP-12·P5 필터 대상 — Reviewer 집중 검증(AGENTS.md 문구 원칙)
- 알림톡 문구 자체는 스코프 아님(ALIMTALK_TEMPLATES.md 별도 진행 중)
- 미커밋 `config/credentials.yml.enc`(사용자가 등록한 솔라피 template_ids)는 본 파이프라인에서 미접촉 — 커밋은 별도 요청으로 처리
- 대시보드·뷰어 파일 수가 많아 3b·3c 지시서는 Developer가 현행 구조를 먼저 파악하도록 지시

## 이전 산출물
F-PLAN 산출물은 `_workspace_prev_fplan/`으로 보존함(2026-11-02, git mv).

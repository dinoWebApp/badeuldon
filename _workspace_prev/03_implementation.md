# 03_implementation.md — 랜딩 4건 수정 구현 보고 [v2]

- **일자**: 2026-10-14
- **담당**: Developer (LandingFixDeveloper)
- **기준**: `_workspace/01_plan.md` v2 · PRD v0.19 (LP-1/2/4/5/10·Q6)

## 변경 파일 요약

| 파일 | 건 | 변경 |
|:---|:---|:---|
| `app/views/landing/_hero.html.erb` | 1 | h1 헤드라인 교체 |
| `app/views/landing/_closing.html.erb` | 1 | 최종 CTA h2 헤드라인 교체(LP-10 반복 구조 유지) |
| `app/views/landing/index.html.erb` | 1 | `content_for :title`·`:description` 갱신 |
| `app/views/landing/_pain.html.erb` | 3 | 오타 「보넸는데」→「보냈는데」 |
| `app/views/landing/_features.html.erb` | 3 | 오타 「보넸는지」→「보냈는지」 |
| `app/views/layouts/landing.html.erb` | 2 | 푸터 사업자 정보 4종 추가(LP-10) |
| `app/views/landing/_message_samples.html.erb` | 4 | 카톡 버블형 UI 재구성(LP-5) |

기존 테스트 파일 수정 없음(Phase 7 Tester 원칙). 신규 파일·마이그레이션 없음.

## 1. 헤드라인 교체 (LP-1·Q6 번복)

- `_hero.html.erb` h1: 「말하기 어려운 '돈 다오', 받을돈이 대신합니다」→ **「독촉하기 어려울 때,<br>받을돈이 대신합니다」**
- `_closing.html.erb` h2: 동일 신규 문구로 갱신 — 히어로 메시지 반복 구조(LP-10)·CTA 링크(`new_registration_path` 2개) 유지
- `index.html.erb`: `content_for :title` → 「받을돈 — 독촉하기 어려울 때, 받을돈이 대신합니다」. 메타 description 선두 문장도 구 헤드라인 어순(「말하기 어려운 독촉」)을 담고 있어 동일 신규 문구로 일관 갱신(후속 검증용 description 매칭 `/수금 루프/`는 유지)
- `landing_controller.rb`·`layouts/_head.html.erb` 폴백 타이틀에는 구 문구 없음 — 확인 후 미변경

## 2. 푸터 사업자 정보 (LP-10)

`app/views/layouts/landing.html.erb` 푸터(랜딩 전용 레이아웃 — LP-10 하단 고정 크롬):

- 법정 필수 4종만 표기: **상호: 벨로루프 | 대표: 김건준 | 사업자등록번호: 539-14-03399 | 주소: 경기도 김포시 김포한강8로 158, 6층 604-n112호(마산동)**
- 생년월일·개업일 미노출(지시 준수)
- 레이아웃: 브랜드+문의 채널 행과 사업자 정보 행을 `border-t`(구분선)로 분리, `text-xs text-stone-500` 작은 글씨, 항목 구분은 `text-stone-300` 파이프(장식 — `aria-hidden`)
- 기존 문의 채널(카카오톡 채널 ‘받을돈’)·© 2026 받을돈 유지 — 기존 LP-10 테스트 단정 호환

## 3. 오타 수정 (LP-2·LP-4)

- `_pain.html.erb`: 「청구서를 **보넸는데**」→「**보냈는데**」(LP-2 공감 인용 ①)
- `_features.html.erb`: 「**보넸는지**, 언제 봤는지 알립니다」→「**보냈는지**」(LP-4 이점 문장 ①)
- 랜딩 파셜 10종 전수 확인(`보넸` grep: 상기 2건이 전부). 기타 오타·어색한 표현 추가 발견 없음
- LP-2 인용의 「열어는 봤는지」는 PRD 지정 원문·테스트 단정 대상이라 원문 유지

## 4. LP-5 발신 문구 버블형 UI 구조화

`_message_samples.html.erb` 재작성:

- **발신자**: 좌측 텍스트 원형 프로필 아이콘(「받」, `rounded-full bg-emerald-800`) + 발신자명 「받을돈」(REM-1 서비스 명의)
- **버블**: 카톡 노란색 `bg-[#FEE500]` + `rounded-2xl` 라운딩 + 좌측 꼬리(`before` 회전 사각형 의사요소)
- **버블 내부 개행 구분 3블록**: ① 인사말 「안녕하세요. 받을돈입니다.」 → ② 본문(청구 내역·안내 — 단계별 REM-2 톤 유지, `[ ]` 자리표기 존치) → ③ 링크 표시 `badeuldon.kr/b/[청구서 토큰]`
- **수신 시간**: 버블 우측 하단 `text-[10px] text-stone-400` (오전 9:00~오후 2:00 — REM-3 발송 창 09~18시 내 예시값)
- **배치**: 4단계 각각 별도 카드, sm 2열 그리드에서 D-1 → D+1 → D+7 → D+14 순 유지
- **규칙 준수**: D+14 「이번 안내로 정기 리마인더를 마칩니다」 유지(Q2 법적 조치·내용증명 언급 없음, 「마지막 알림」 표현 없음), 링크는 표시 전용 텍스트(앵커 아님 — SURF-4 ① 표면 단일 진입 유지)

## §4 실패 예상 테스트(구 헤드라인·구 문구 단정 — Tester 갱신 대상)

`bin/rails test` 실측: **363 runs, 2208 assertions, 4 failures, 0 errors, 0 skips** — 실패 전부 아래 4건이며 예상 목록과 정확히 일치:

| # | 테스트 (test/controllers/landing_controller_test.rb) | 단정 위치 | 원인 |
|:---|:---|:---|:---|
| 1 | `h1 헤드라인이 Q6 확정 문구와 일치한다 (LP-1)` | :17 | 구 문구 정규식 `/말하기 어려운 '돈 다오',\s*받을돈이 대신합니다/` → 실제 신규 문구 |
| 2 | `표면 ①은 noindex 없이 content_for :title을 렌더한다 (SURF-3)` | :60 | 구 타이틀 정규식 → 실제 「받을돈 — 독촉하기 어려울 때, 받을돈이 대신합니다」 |
| 3 | `LP-2 공감 인용 3종이 PRD 원문으로 노출된다 (LP-2)` | :82 | `/청구서를 보넸는데…/` → 실제 「보냈는데」 |
| 4 | `LP-4 이점 문장 3종이 PRD 원문으로 노출된다 (LP-4)` | :97 | `/보넸는지, 언제 봤는지 알립니다/` → 실제 「보냈는지」 |

※ PRD v0.19에서 해당 단정 대상 문구(LP-1 타이틀·LP-2·LP-4)가 이미 번복·수정되었으므로 테스트 기대값 갱신이 정합. LP-5 버블 구조·LP-10 사업자 정보 관련 신규 실패 없음(기존 단정 모두 통과).

## 자체 점검 결과

| 항목 | 결과 |
|:---|:---|
| `bin/rubocop` | **101 files inspected, no offenses** (0 에러) |
| `bin/rails zeitwerk:check` | **all is good** 통과 |
| `bin/rails test` | 363 runs / 4 failures(위 §4 4건뿐) / 0 errors / 0 skips |
| 마이그레이션 | 없음 — `db:migrate`·schema 불필요 |
| 뷰어(③)·규칙 영향 | 없음 — 랜딩(①) 마크업만 변경, 마케팅 문구의 SURF-4 단일 진입·LP-12 금지어(보장/100%)·Q2 제약 회귀 테스트 전부 통과 |
| 서버 기동·테스트 작성 | 지시대로 수행하지 않음 |

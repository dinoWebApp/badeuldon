# 01_plan — 기술 부채 병렬 배치 (2026-11-09, §6.14 parallel · 절약 모드)

## 배치 목표

AGENTS.md 기술 부채 중 **파일 소유권이 분리된 독립 소규모 4건**을 병렬 fan-out으로 처리.
§6.14 병렬 안전 3조건 판정 결과와 소유권 표는 아래와 같다.

## 태스크 분해 (병렬 안전 판정 포함)

### T1 · Pretendard 셀프호스팅 — DESIGN-1 · PERF-2
- 내용: CDN(`<link>` jsdelivr 등) 의존 제거 → `public/fonts/` woff2 셀프호스팅 + @font-face 선언(Weight 400/500/700 가변 또는 정적). 뷰어 인앱·오프라인 안정성(PERF-2 2초 예산과 정합)
- 소유 파일: `app/views/layouts/**`, `app/assets/stylesheets/**`, `public/fonts/**`(신규), 해당 테스트
- 판정: ✓ 3조건 통과 (T2와 layouts/application.rb 비겹침 — T1은 views/layouts만)

### T2 · ko locale — 전 표면 문구·TIME-1 보조
- 내용: `config.i18n.default_locale = :ko` + available_locales 확장, 앱 전용 `config/locales/ko.yml`, **rails-i18n gem 추가(한국어 번역 사전)**
- 소유 파일: `Gemfile`·`Gemfile.lock`(**T2 독점 — 타 태스크 bundle 금지**), `config/application.rb`, `config/locales/**`(신규), 해당 테스트
- 판정: ✓ 3조건 통과. 리스크: default_locale 전환 회귀는 7-S 전체 테스트에서 흡수

### T3 · ViewEvent 강화 (봇 UA 필터 + 하드닝) — SHARE-3·4 · SEC
- 내용: 크롤러·봇 UA의 열람을 ViewEvent 기록·최초열람 전이·SHARE-4 알림 대상에서 **제외**(권고 — 오열람 알림 방지), UA/IP 길이·형식 검증 강화
- ※ 봇 UA 필터와 ViewEvent 하드닝은 동일 파일을 건드리므로 하나로 병합(병렬 불가 조건 해소)
- 소유 파일: `app/services/view_events/**`, `app/models/view_event.rb`, `app/controllers/viewer_controller.rb`, `test/services/view_events/**`, `test/system/viewer_*.rb`(회귀 최소 수정)
- 판정: ✓ 3조건 통과. 설계 결정: "기록 제외" 권고(마킹 기록 대안 대비 SHARE-3 집계 오염 방지)

### T4 · 거래처 삭제 시 발송 이력 보존 (P4 점검) — CLIENT-1 · P4 · REM-6
- 내용: 현재 client 삭제 → invoice → message_logs 연쇄 삭제가 P4(발신 기록 임의 삭제 불가)와 충돌. **권고안 (a): 미수·발행 계열 청구가 존재하는 거래처는 삭제 차단 + 안내 문구**(초안만 있는 거래처는 기존대로 삭제). 이력 스냅샷 해석(b안 client_id nullify)은 규모가 커서 제외
- 소유 파일: `db/migrate/`(신규 독립 1건 — **마이그레이션 "체인" 수정 아닌 추가라 허용, 3-S에서 전체 migrate 1회**), `app/models/client.rb`, `app/models/message_log.rb`(필요시), 해당 테스트
- 판정: ✓ 3조건 통과(타 태스크와 파일 겹침 0). PRD CLIENT-1 해석 갱신은 Phase 2에서 반영

## 파일 소유권 표 (§6.14 필수)

| 파일/영역 | T1 | T2 | T3 | T4 | 비고 |
|---|---|---|---|---|---|
| `app/views/layouts/**` | **소유** | | | | |
| `app/assets/stylesheets/**`·`public/fonts/**` | **소유** | | | | |
| `Gemfile`·`Gemfile.lock` | | **소유** | | | 타 태스크 bundle 실행 금지 |
| `config/application.rb`·`config/locales/**` | | **소유** | | | |
| `app/services/view_events/**`·`view_event.rb`·`viewer_controller.rb` | | | **소유** | | |
| `db/migrate/`(신규 1건)·`client.rb`·`message_log.rb` | | | | **소유** | |
| `config/routes.rb`·PRD·AGENTS·`progress.json` | ✗ | ✗ | ✗ | ✗ | 공유 비수정(오케스트레이터만) |

## 파이프라인 (§6.14)

0✅ → 1-P✅ → ✋**배치 승인 게이트(태스크 선택 포함)** → 2(문서 현행화 직렬 1회) → 3-P(병렬 구현 fan-out, **동시성 상한 3** — T1·T2·T3 동시 → T4 2차 웨이브) → 3-S(통합: 전체 migrate·결선 확인) → 4(rubocop·zeitwerk·migrate) → 5(Reviewer-lite 직렬 1회·전체 대상) → 6?(필요시) → 7-P(병렬 테스트 작성·태스크별) → 7-S(전체 테스트 1회 게이트) → 8 → 9

프로필(절약): `badeuldon-developer-lite`(GLM-5.3-Flash/low) · `badeuldon-reviewer-lite`(Flash/high) · `badeuldon-tester-lite`(Flash/low)

## 제외 항목 (이번 배치 밖 — 사유)

- 이메일 서비스 선정·연동: **서비스 선정 = 사용자 결정** 대기
- NOTI-2(솔라피 템플릿 등록 필요)·partial_paid 재발송 해석·REM-3 세부 지정 UI: 설계 결정·외부 등록 필요
- dunning·포트원 웹훅 실측·인앱 실기 QA·약관·후기·Stimulus 분리: 기능 규모 또는 실기/운영 작업

## 리스크

- T2 default_locale 전환의 앱 전반 문구 회귀 — 7-S 전체 게이트에서 흡수, 개별 태스크 자체검증은 자기 스코프만
- T4 마이그레이션 — 신규 단건 추가이며 3-S에서 일괄 적용 (병렬 중 repo-wide migrate 금지 지시)
- fan-out 제약 준수: 각 지시서에 소유권 화이트리스트·자기 스코프 검증·문서 수정 금지 명시

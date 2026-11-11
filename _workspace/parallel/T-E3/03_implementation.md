# T-E3 — LP-11 허브 통합 구현 문서 (2026-11-11, 절약 모드)

## 변경 목록

| 파일 | 변경 |
|---|---|
| `app/views/blog/index.html.erb` | 허브화 — 헤더 타이틀 "프리랜서 수금 콘텐츠"·5클러스터 카테고리 카드 grid(`blog_path(category: key)` 재사용)·도구 카드 파셜 렌더·가입 CTA 섹션. 기존 필터 pill·게시글 목록·페이지네이션은 그대로 유지 |
| `app/helpers/blog_helper.rb` | `CATEGORY_DESCRIPTIONS`(5클러스터 1줄 설명) 상수 + `category_description` 헬퍼 추가(쿼리 없는 인자 기반 — 기존 패턴 동일) |
| `app/views/blog/_tool_cards.html.erb` | **신규** — 무료 도구 3종 카드(인라인 svg 아이콘·도구명·설명·"바로 사용" 링크) |
| `test/controllers/blog_controller_test.rb` | 허브 레이어 검증 테스트 1건 추가(헤더 문구·카테고리 카드 5·도구 경로 3·CTA) |

## 허브 구조 (index.html.erb 순서)

1. 허브 헤더(타이틀·부제)
2. 5클러스터 카테고리 카드 grid — 클릭 시 기존 카테고리 필터 경로로 이동(라우트 하드코딩 없음, `blog_path` 헬퍼)
3. 도구 카드 파셜
4. 가입 CTA(LP-11 허브 버전 — 한 문단 안내 + 1버튼, LP-12·VIEW-8 정신 준용, `new_registration_path` 기존 헬퍼)
5. 이하 기존 목록(필터 pill·카드 grid·페이지네이션 — T-E1 구현 미변경)

## 도구 경로 하드코딩 인계 (3-S 결선)

- 위치: `app/views/blog/_tool_cards.html.erb` 3~5행 — 경로 배열 `/tools/reminder-generator`·`/tools/tax-calculator`·`/tools/invoice-template`
- 계약: T-E2가 동일 경로의 컨트롤러 제공. 3-S 결선 시 `url_for`/명명 헬퍼로 교체(파셜 내 주석 명시)

## 검증 결과

- `bin/rails test test/controllers/blog_controller_test.rb` — 9건(신규 포함) 전부 통과(107 assertions). 기존 목록 기능(필터·페이지네이션·published만) 회귀 없음
- `bin/rubocop` — 소유 rb 2파일(blog_helper·blog_controller_test) offense 0(ERB는 프로젝트 전반 rubocop 대상 아님 — 기존 뷰도 동일 baseline)
- `bin/rails zeitwerk:check` — 통과
- 렌더 검증은 컨트롤러 경유 Integration(IntegrationTest)으로 재현 — HTTP 200·카드/도구/CTA 전부 어설션. 테스트 트랜잭션 롤백으로 임시 레코드 자동 정리

## 미수행 (소유권 외 — 결선 태스크 인계)

- routes(/tools 결선)·blog_controller·models·tools(T-E2)·PRD/AGENTS·Gemfile·전체 테스트·nav — 미접촉 확인

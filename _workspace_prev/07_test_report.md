# 07_test_report — LP-11·BLOG 병렬 배치 (T-E1~E4 + 3-S, 2026-11-11, Tester 절약 모드)

## 게이트 결과 (Phase 7)

| 스위트 | 결과 |
|---|---|
| `bin/rails test` (기본 — 시스템 테스트 미포함 러너 구조, 이전 런 실측 재확인) | **1069 runs, 6121 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails test:system` (별도 러너) | **12 runs, 102 assertions, 0 failures, 0 errors, 0 skips** — 연속 2회 그린 + 신규 E2E 단독 3회 반복 그린 |
| `bin/rubocop` (306파일) | **0 offenses** |
| 합계 | **1081 runs · 0 실패 · 코드 버그 0건** (기준 1,064건 대비 +15: 컨트롤러/쿼리 등 개발자·Phase 6 보강분 + 신규 시스템 테스트 1건) |

- 솔라피·포트원 실호출 0건(기존 stub 체계 그대로 — 본 런 테스트는 외부 API 미접촉).
- test DB 잔존 없음(트랜잭션 롤백·fixtures). **test AS 디스크 잔존 1,549 blob 정리 완료**(`tmp/storage` — test storage.yml root, git 무시·`.keep` 보존).

## 리뷰 인계·제안 처리

| # | 항목 | 처리 |
|---|---|---|
| ② | **실브라우저 첨부 발행 E2E(인계 필수)** | **신규 작성** — `test/system/admin_blog_publish_test.rb`. 관리자 2FA 실로그인(1단계 자격증명 → TOTP) → 신규 폼에서 제목·한글 마크다운 본문·메타 2종·`fixture_file` 2종(썸네일·OG) 첨부 → 저장(enctype multipart 실전송) → edit "첨부됨: sample.png" 표시(B-1) → index에서 발행(member PATCH, 필수 충족) → published 전이·published_at 기록 → **공개 /blog/:slug 실렌더**(한글 본문·og:title=메타제목·og:image 첨부 URL) → **/blog 목록 썸네일 img 렌더**(BLOG-3 — 상세 화면엔 img가 없어 목록에서 검증). 안정화를 위해 **3회 반복 실행 전부 통과** |
| ① | PRD BLOG-3 "커서 기반"→"오프셋" 문구 정정(C-3) | **오케스트레이터 완료 확인** — PRD.md:356 "페이지당 12건·오프셋 방식 — 2026-11-11 구현 확정 문구 정정" 실측. 코드(offset/limit)와 명세 일치 → **종결** |
| — | blog index 허브 렌더 커버 | **기존 테스트 존재 확인·보강 불요** — `test/controllers/blog_controller_test.rb:62` "index는 LP-11 허브 레이어를 렌더한다 — 카테고리 카드 5·도구 카드 3·가입 CTA" + `:19` published만 노출. T-E3 보강분과 중복 없음 |
| W-6 잔존 | `admin/blog_posts/index.html.erb`의 `BlogPost.statuses.map` 1건 | **해소** — `BlogHelper::STATUS_KEYS` 상수 추가(BlogHelper) + 뷰 select_tag 치환. CATEGORY_KEYS와 동일 패턴, 프로덕션 변경은 헬퍼+뷰 2파일 최소. grep으로 `BlogPost.statuses` 뷰 호출 0건 확인(컨트롤러 filter의 `params[:status].in?(BlogPost.statuses.keys)`는 컨트롤러라 규정 대상 아님) |

## 신규 테스트 작성 중 발견·자체 수정한 테스트 오류 (코드 버그 아님)

1. **`querySelector('form')` 네이티브 제출이 로그아웃을 날린다(실측)** — admin 레이아웃의 "로그아웃" button_to 폼(`layouts/admin.html.erb:29`)이 콘텐츠 폼보다 DOM 앞에 있어, 페이지 첫 form을 제출하면 DELETE /admin/session이 날아가 세션 파기·로그인 화면 복귀가 재현됐다(TOTP 검증 성공 직후 이탈로 오인됐던 간헐 실패의 정체). `submit_form_of(url)` — action 일치 폼 특정 네이티브 제출로 결정화. chromedriver 합성 클릭 드롭 실측(ApplicationSystemTestCase §7)이 dom_click에서도 간헐 재현된 것이 조사 계기.
2. **썸네일 img는 /blog 상세에 없다** — BLOG-3 목록 항목이라 상세 렌더에 img 미포함(코드 의도). 목록 페이지 카드의 `img[alt=제목]` + src 첨부 파일명 매칭으로 검증 위치 정정.
3. **og:title 메타 2개 렌더**(og_tags 파셜 + 별도) — `all(...).first`로 단정해 Capybara Ambiguous 회피.
4. **AppInvoicePdfTest 간헐 1회 실패 관찰** — U1 UI 로그인 플레이크(솔로 실행·전체 시스템 재실행 2회 모두 그린). 미수정 — 본 런 변경과 무관, 관찰 기록만.

## 코드 버그

없음. 기존 스위트 충돌 없음(블로그 마이그레이션·kramdown gem·tools 도메인·PublishScheduledJob recurring 등록 — 전체 게이트 통과로 확인).

## 잔존 비고

- "due_today" 테스트명 잔존: 이전 런에서 이미 정정 완료 — 본 런 접촉 파일 없어 스킵(지시 4항).
- dev DB에 `AdminSession id=34 (admin=t@t.com, 2026-11-10)` 1건 선존 — 이전 런(2026-11-10) 재산으로 본 런이 생성한 것이 아니어서 삭제하지 않음. 오케스트레이터 판단 바람.
- 리뷰 재현 스크립트 /tmp: 본 런 임시 디버그 테스트 파일은 즉시 삭제 완료.

# T-E1 블로그 코어 — 구현 문서 (2026-11-11)

## 변경 파일 목록 (소유권 화이트리스트 내)

| 파일 | 내용 |
|---|---|
| `Gemfile` + `Gemfile.lock` | `gem "kramdown"` 추가(bundle 완료 — 2.5.2) |
| `db/migrate/20261111100001_create_blog_posts.rb` | blog_posts + blog_slug_redirects 2테이블(단일 마이그레이션) |
| `db/schema.rb` | 위 마이그레이션 반영(migrate 실행으로 자동 갱신 — AGENTS "커밋 필수" 준수) |
| `app/models/blog_post.rb` | BlogPost(신규) |
| `app/models/blog_slug_redirect.rb` | BlogSlugRedirect(신규) |
| `app/services/blog_posts/render_service.rb` | 렌더 파이프라인(신규) |
| `app/controllers/admin/blog_posts_controller.rb` | ADMIN-10 콘텐츠 CRUD(신규) |
| `app/views/admin/blog_posts/{index,new,edit,_form}.html.erb` | 신규 |
| `app/controllers/blog_controller.rb` | 공개 /blog(신규) |
| `app/controllers/sitemaps_controller.rb` | /sitemap.xml(신규 — 지시 §5·화이트리스트 누락 항목이나 지시 본문 명시로 생성) |
| `app/views/blog/{index,show,_og_tags}.html.erb` + `app/views/layouts/blog.html.erb` | 신규 |
| `app/helpers/blog_helper.rb` | 카테고리/상태 라벨(신규) |
| `config/routes.rb` | blog 블록만 추가(GET /blog·/blog/:slug·/sitemap.xml + admin blog_posts resources) |
| `test/models/blog_post_test.rb` · `test/services/blog_posts/render_service_test.rb` · `test/controllers/blog_controller_test.rb` · `test/controllers/admin/blog_posts_controller_test.rb` | 신규 4종 |

## Rule ID 매핑

- **BLOG-1**: slug 형식 검증(`\A[a-z0-9]+(-[a-z0-9]+)*\z`)·고유 인덱스·변경 시 `blog_slug_redirects` 기록(before_update)·`BlogController#redirect_moved_slug` 301(대상 비공개·미발행이면 404)
- **BLOG-2**: 메타 title/description(content_for)·OG 태그(`_og_tags`)·canonical·Article JSON-LD(show 뷰)·`/sitemap.xml`(게시글 lastmod=updated_at·카테고리 5경로)·색인 허용 — NOINDEX_PATH_PREFIXES(`/app,/b/,/admin`)에 /blog 미포함이라 **무수정**(ApplicationHelper 확인)
- **BLOG-3**: `published_now` scope(status published && publish_at nil|≤now)·목록 최신순·카테고리 필터(enum key 검증 — 무효값 무시)·페이지당 12건 offset/limit 페이저
- **BLOG-4**: 목차(h2/h3 앵커 `toc-{slug}-{n}` — RenderService)·관련 글(동일 카테고리 3건 자기 제외)·SURF-6 fragment 캐시(`cache @post` — updated_at 키 자동 만료)
- **BLOG-5**: draft/scheduled/published/hidden 상태 전이(publish!·schedule!·unpublish!)·발행 필수 검증(썸네일·OG·meta_title·meta_description — `publishable?`)·AS 첨부 2장(기존 AS 테이블 재사용 — 신규 마이그레이션 불요)·마크다운 원문+렌더 HTML 별도 저장(before_save 재렌더)
- **ADMIN-10**: Admin::BlogPostsController CRUD + member publish/schedule/unpublish·컨트롤러 경유 HTTP 테스트(비인증·U1 세션 차단 포함)

## sanitize allowlist (Q18·02 확정 해석 2)

- 태그: p·h1~h6·ul·ol·li·a·strong·em·code·pre·blockquote·img·table·thead·tbody·tr·th·td·hr·br·figure·figcaption·span·del
- 속성: class·id·href·target·rel·src·alt·title·datetime
- **실측 지식**: rails-html-sanitizer(Rails 8.1 번들)의 HTML5 sanitizer는 태그별 속성 해시를 무시하고 flat 배열만 인정 — `ALLOWED_ATTRIBUTES`는 flat 배열로 구현. 렌더 후 h2/h3에 부여하는 `id` 앵커가 출력 시점 이중 sanitize에서 유실되지 않도록 `id`를 allowlist에 포함.
- **이중 sanitize**: 저장 시(RenderService) + 출력 시(show 뷰 `sanitize body_html` — 멱등) — brakeman XSS 경고 0 유지 + 심층 방어. `raw` 사용처는 JSON-LD `to_json`(신뢰된 서버 조립값·script 내부 엔티티 디코딩 없음) 1건뿐.

## 3-Q / 3-S 인계 사항

1. **tools 경로**: show 뷰 CTA가 `/tools` 리터럴(`<a href="/tools">`) — tools 헬퍼가 아직 없어 하드코딩(지시 허용안). **T-E2가 `tools_path` 헬퍼 확보 시 교체 권장**. 현재 /tools는 404.
2. **admin nav 미추가**: "콘텐츠" 메뉴는 3-S 결선 대상 — `admin_blog_posts_path` 진입만 routes로 확보됨(nav는 layouts/admin.html.erb 미수정).
3. **마이그레이션 버전**: `20261111100001_create_blog_posts`(초기 지정 20261111040001은 기존 recurring_invoices와 충돌 실측 → 변경). **신규 마이그레이션은 이 1건뿐** — T-E4의 예약 발행 Job은 마이그레이션 불요.
4. **예약 발행 Job 미생성**: 지시서 화이트리스트에 잡 파일·recurring.yml 없음(금지 목록에 recurring 명시) — Q20 매분 스캔(`* * * * *` Asia/Seoul)은 **T-E4가 등록**. 대상: `status: scheduled && publish_at <= now` → `status: published` 전환. 상태 전환 전에도 `published_now`는 scheduled를 노출하지 않으므로 잡 지연 시 노출 유예(의도된 이원화 — 모델 주석 기재).
5. **공유 JS**: app/javascript 소유권 밖이라 show 뷰 하단 인라인 script(카카오톡 스킴·X intent·clipboard 복사) — 3-S 결선 시 Stimulus 분리 검토(기술 부채 항목과 동일 선상).
6. **enum 값명 치환**: 지시어 `private: 3`은 Active Record enum 클래스 메서드 충돌(실측 ArgumentError)로 **`hidden: 3`**(DB 정수 동일). 뷰·테스트·헬퍼 라벨 전부 hidden 통일.

## 자기 스코프 검증 결과

- **테스트**: 자기 4종 32건 전부 통과(모델 11·서비스 6·공개 컨트롤러 10·admin 컨트롤러 5 — runs 32/assertions 230, failures 0 errors 0). 전체 스위트 실행은 3-S 이후 Phase 7 예정대로 미실행.
- **rubocop**: 자기 12파일 0 offense. **zeitwerk**: 통과. **brakeman**: Security Warnings 0(본 태스크 추가 경고 없음).
- **마이그레이션**: dev DB migrate 완료·schema.rb 갱신 확인.
- **실측 트러블슈팅 기록**(동일 패턴 재발 방지): ① `%()` 리터럴이 내부 보간의 `)`에서 조기 종료 — gsub 치환문은 이중따옴표 사용 ② enum 예약어 충돌 ③ rails-html-sanitizer 해시 속성 무시 ④ 레일즈 신규 테스트 파일에 `require "test_helper"` 누락 시 fixture accessor 전무 오류.

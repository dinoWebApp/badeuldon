# 3-S 결선 통합 — 구현 문서 (2026-11-11, 절약 모드 병렬 배치)

T-E1(블로그 코어)·T-E2(도구 3종)·T-E3(허브)·T-E4(예약 발행 Job) fan-out 완료 후의 공유 파일 결선·마이그레이션 재확인·스모크·컨트롤러 최초 HTTP 검증 결과.

## 변경 파일 목록

| 파일 | 내용 |
|---|---|
| `config/routes.rb` | tools scope 신설(5경로 — 계약 4 + invoice-template.pdf) + `/blog` 블록 앞 배치. admin blog_posts는 T-E1이 이미 결선 완료(재확인만). 기존 blog routes 무변경 |
| `app/views/layouts/admin.html.erb` | nav에 "공지"(admin_notices_path)·"콘텐츠"(admin_blog_posts_path) 추가 — ADMIN-10 콘텐츠 통합, 기존 active 문법 준용 |
| `app/views/layouts/landing.html.erb` | 헤더 좌측에 "블로그"(blog_path) 텍스트 링크 추가 — LP-11 유입·히어로 CTA 단일 유지(SURF-4 영향 없음 — 랜딩→블로그) |
| `app/views/layouts/blog.html.erb` | 헤더에 블로그 자체 네비 신설 — 홈(blog_path) + 도구 3종(결선 헬퍼) |
| `app/views/tools/index.html.erb` | `<a href="/tools/...">` 리터럴 3건 → `{reminder_generator,tax_calculator,invoice_template}_tool_path` 교체 + NOTE 주소 |
| `app/views/tools/reminder_generator.html.erb` | form_with url 리터럴 → `reminder_generator_tool_path` |
| `app/views/tools/tax_calculator.html.erb` | form_with url 리터럴 → `tax_calculator_tool_path` |
| `app/views/tools/invoice_template.html.erb` | form_with url 리터럴 → `invoice_template_pdf_tool_path` |
| `app/views/layouts/tools.html.erb` | `link_to "/tools"` → `tools_path` |
| `app/views/blog/_tool_cards.html.erb` | 도구 경로 배열 리터럴 3건 → 결선 헬퍼 교체(T-E3 인계 해소) |
| `app/views/blog/show.html.erb` | `<a href="/tools">` CTA → `tools_path`(T-E1 인계 해소) |

T-E4 산출(`app/jobs/blog_posts/publish_scheduled_job.rb` + `config/recurring.yml`)은 fan-out에서 완료 — 결선 추가 없음.

## 라우트 최종 (bin/rails routes 확인)

```
tools                      GET  /tools                              tools#index
reminder_generator_tool    GET  /tools/reminder-generator           tools#reminder_generator
tax_calculator_tool        GET  /tools/tax-calculator               tools#tax_calculator
invoice_template_pdf_tool  GET  /tools/invoice-template.pdf         tools#invoice_template_pdf
invoice_template_tool      GET  /tools/invoice-template             tools#invoice_template
blog                       GET  /blog                               blog#index
blog_post                  GET  /blog/:slug                         blog#show
sitemap                    GET  /sitemap.xml                        sitemaps#show
admin_blog_posts           7+3  /admin/blog_posts(+publish/schedule/unpublish)  [T-E1 결선 확인]
```

**실측 트러블슈팅 — .pdf 라우트 순서**: `get "invoice-template.pdf"`를 일반 `invoice-template` 뒤에 두면 Rails가 `.pdf`를 format 파싱해 일반 라우트(format=pdf)로 흡수되고 `ToolsController#invoice_template`이 `ActionController::UnknownFormat`(406)으로 떨어짐. **.pdf 라우트를 먼저 선언**해 정적 리터럴("invoice-template.pdf(.:format)") 매칭으로 해결(라우트 주석 기재).

## /tools 리터럴 전수 확인

`grep -rn "/tools" app/views app/helpers app/controllers` 결과 — 잔존 리터럴 0건(주석의 "3-S 결선" 기술 문구만 잔존). 전부 명명 헬퍼화:
- tools_path · reminder_generator_tool_path · tax_calculator_tool_path · invoice_template_tool_path · invoice_template_pdf_tool_path (5종)

## 마이그레이션

- `bin/rails db:migrate` — 신규 적용 0건(T-E1 `20261111100001_create_blog_posts` 이미 적용 확인)·schema.rb 불변.

## 스모크(부트 3002·pid 분리, curl 비인증)

| URL | 결과 |
|---|---|
| /blog | 200 |
| /blog/category/docs | **404** — 카테고리 필터는 구현 계약상 쿼리 파라미터(`/blog?category=docs` = 200 확인·T-E1/E3 `blog_path(category: key)` 구조). "category"는 슬러그 조회로 404가 올바른 동작 |
| /sitemap.xml | 200 |
| /tools | 200 |
| /tools/reminder-generator | 200 |
| /tools/tax-calculator | 200 |
| /tools/invoice-template | 200 |
| /tools/invoice-template.pdf | 200 (application/pdf — 라우트 수정 후) |
| /app/recurring_invoices | **302 → /session/new** — 인증 가드 리다이렉트(기존 앱 표준 동작·기능 회귀 없음) |
| /up | 200 |

## 컨트롤러 최초 HTTP 검증 (IntegrationTest, /tmp 작성→실행 후 삭제)

**1 runs, 43 assertions, 0 failures, 0 errors.** 케이스:

1. **admin blog_posts**: admin 2FA 로그인 → index 200(nav에 "콘텐츠" 노출 확인) → new 200 → create 303(게시글 생성·자동 슬러그) → publish 303(썸네일/OG 첨부 + meta_title/description 충족 케이스 → status published)
2. **blog show**: /blog 목록에 발행 글 노출 + blog layout 도구 nav 렌더 → show 200·한글 본문 렌더·CTA(tools_path) → 미존재 슬러그 404 → slug 변경 후 old_slug 접근 **301**
3. **tools**: 4페이지 200 + GET params 결과 — 독촉 문구(1,000,000원 치환)·계산기(967,000원 — 3.3% 차감 실수령액)·양식 PDF 200(application/pdf)
4. **sitemap.xml**: 발행 게시글 URL(final-check-post-2) 포함
5. **회귀**: /admin/audit_logs 200(이전 배치 B-1 수정 유지)·랜딩 헤더에 blog_path 링크 노출

## 게이트

- `bin/rails zeitwerk:check` — 통과("all is good")
- `bin/rubocop config/routes.rb` — 0 offense(수정 .rb 파일이 라우트 1건뿐·ERB는 rubocop 대상 아님 — 기존 baseline)
- 단일 파일 테스트(T-C3 선례 한도): `test/controllers/blog_controller_test.rb` — 9 runs, 107 assertions, 0 failures(T-E3 허브 포함 회귀 없음)

## 발견 이슈 (오케스트레이터 보고용)

1. **지시 스모크 URL 해석 차이**: 지시의 `/blog/category/docs` 200은 path형 필터 전제 — 실제 구현(T-E1/E3)은 쿼리 파라미터형(`/blog?category=docs`). 기능 동작은 정상·path 접근은 404(올바른 슬러그 조회 결과). 신규 라우트 추가는 지시 범위 밖이라 미수정.
2. **/app 미인증 리다이렉트 303 예상 → 실측 302**: GET 인증 가드 리다이렉트는 앱 전반 기존 동작(303은 폼 POST 성공 규약 대상). 회귀 아님.
3. **계산기 실수령액 표기**: 부가세 포함 입력이 아닌 경우 공급가액 1,000,000원 → 실수령액 967,000원(3.3%만 차감·부가세 10%는 별도 표기) — T-E2 산식이 의도된 INV-2 기준. 검증 어설션을 구현 산식에 맞춰 확인.
4. 문서(PRD/AGENTS)는 지시에 따라 미수정 — PRD v0.37 반영은 별도 단계 대상.

## 수선 (2026-11-11 SURF-4 테스트 허용 목록 갱신 — 절약 모드)
- `test/controllers/landing_controller_test.rb` SURF-4 허용 목록에 `blog_path` 추가(주석 갱신: 법적 고지 3종 + 블로그 LP-11) — 31 runs 0 failures, rubocop 0 offense

---

# Phase 6 — 리뷰 수정(05_review CHANGES_REQUESTED 반영, 2026-11-11)

BLOCKER 1·CRITICAL 4·WARNING 6 전건 수정. 상세는 `_workspace/05_review.md` 이슈 번호 대응.

## 수정 내역 (이슈별)

| 이슈 | 수정 파일 | 내용 |
|---|---|---|
| **B-1** | `app/views/admin/blog_posts/_form.html.erb` | FormBuilder 전환(`do \|f\|` + `f.text_field`·`f.select`·`f.text_area`·`f.file_field`·`f.submit`) — `f.file_field`가 폼에 `enctype="multipart/form-data"` 자동 부여. 렌더 HTML enctype 실측 확인(아래 재현) |
| **C-1** | 동일 `_form.html.erb` | 본 폼 밖(중첩 폼 방지)에 예약 발행 서브폼 신설 — `form_with url: schedule_admin_blog_post_path` + `sf.datetime_local_field :publish_at` + "예약 발행" 버튼. draft·scheduled·hidden(비published)에서만 노출 |
| **C-2** | `config/routes.rb`·`app/views/blog/index.html.erb`(카드·pill)·`app/controllers/sitemaps_controller.rb` | `get "/blog/category/:category" => blog#index, as: :blog_category` 신설(/blog/:slug보다 선행 선언)·허브 카드·필터 pill·sitemap 전부 path형(`blog_category_path/url`) 전환. 쿼리형(`blog?category=`)은 레거시 호환으로 유지(양좁) — page 파라미터 결합은 쿼리형 유지 |
| **C-3** | (문서) | 코드는 offset/limit 유지(검토 합리적 개정안). **PRD v0.37 BLOG-3 문구 "커서 기반" → "페이지당 12건 오프셋 페이저" 정정은 오케스트레이터 몫 — 이 기록으로 인계 완료** |
| **C-4** | `app/controllers/admin/blog_posts_controller.rb` | publish 성공 시 본문에 `/tools\|/blog/` 내부 링크 부재면 notice에 경고 문구 덧붙임(강제 아님 — 303 유지). 링크 있으면 경고 없음 |
| **W-1** | `config/recurring.yml` | development 블록 `subscription_trial_expiry` 중복 키(빈 값 줄) 제거. YAML 재로드 실측 dup-free=true(production 8·development 7 tasks) |
| **W-2** | `app/models/blog_post.rb` | `schedule!` — `Time.zone.parse` 결과 nil이면 `errors.add(:publish_at, :invalid)` + false(좀비 예약 방지). blank는 기존대로 :blank. 과거 시각은 즉시 노출 의도로 허용 유지(주석 명시) |
| **W-3** | `app/models/blog_post.rb`·`config/recurring.yml`·`app/views/blog/show.html.erb` | published_now 주석을 실동작대로 정정(scheduled는 Job 전환 후 노출·최대 1분 유예)·recurring.yml 주석 동일 정정·show 주석 "이중 sanitize 통과 출력"으로 정정 |
| **W-4** | `app/views/blog/index.html.erb`·`_tool_cards.html.erb` | "부가세 3.3% 원천징수 후" → "원천징수 3.3%를 반영한" 정정 |
| **W-5** | `app/controllers/blog_controller.rb` | index @posts·show @related에 `includes(:thumbnail_attachment)` 추가(썸네일 N+1 제거) |
| **W-6** | `app/helpers/blog_helper.rb` + 뷰 4파일 | `CATEGORY_KEYS = BlogPost.categories.keys.freeze` 헬퍼 상수 신설 — blog index 2곳·admin form·admin index의 `BlogPost.categories` 직접 호출 제거(views grep 0건) |

## 테스트 보강 (정식 편입)

- `test/controllers/admin/blog_posts_controller_test.rb` +4: ① new 렌더 enctype + edit의 예약 발행 트리거(B-1·C-1 렌더 HTML 어설션) ② `fixture_file_upload`(test/fixtures/files/sample.png 신설) multipart create → 실첨부 → publish 303(B-1 Integration 실측) ③ schedule 무효 문자열 거부(W-2) ④ publish 내부 링크 경고 유/무(C-4)
- `test/controllers/blog_controller_test.rb` +1: `/blog/category/docs` 200·필터 동작·무효 키 전체 목록(C-2)
- 블로그 연관 5종 파일 테스트: **42 runs, 308 assertions, 0 failures**. fixture `test/fixtures/files/sample.png`(1×1 PNG, Python zlib 생성) 신설

## 컨트롤러·Integration 재현 (재리뷰 대상 B-1·C-1 포함 — /tmp 실행 후 삭제)

**1 runs, 36 assertions, 0 failures, 0 errors.** 순서대로 실측:

1. **B-1**: `GET new` 렌더 HTML에 `enctype="multipart/form-data"` 실측 → multipart params(fixture PNG 파일 업로드)로 create 303 → `thumbnail.attached?`·`og_image.attached?` 실측 true → publish 303 published 전환
2. **C-4**: 내부 링크 없는 게시글 publish → notice에 "내부 링크가 없습니다" 포함(발행 자체는 성공) / 내부 링크 있는 게시글 → 경고 부재
3. **C-1**: edit 렌더에 `schedule_admin_blog_post_path` 트리거 실측 → 무효 시각 PATCH schedule → 303 alert + draft 유지(W-2) → 유효 시각 → scheduled 전환 → **Q20 `PublishScheduledJob.perform_now`(2시간 travel) → published 전환 → /blog/:slug 노출 200** 전 체인 실측
4. **C-2**: `/blog/category/docs` 200(필터 동작) → sitemap.xml에 `/blog/category/docs` path형 포함·쿼리형 인코딩 URL 부재 → 쿼리형 레거시도 200

## 게이트

- `bin/rubocop`(수정 .rb 8파일) — 0 offenses · `bin/rails zeitwerk:check` — 통과
- recurring.yml YAML 파싱 실측 — production 8·development 7 tasks·중복 키 0
- 전체 테스트 미실행(Phase 7 금지 준수)

## 인계/유의

- published_now는 status published && publish_at ≤ now — 예약글이 Job 전환 직후에도 publish_at 미경과면 미노출(경계 안전). 재현 테스트는 travel 블록 내부에서 노출을 검증했다.
- 시스템 테스트(실브라우저 첨부 E2E)는 리뷰 권고대로 Phase 7 인계 — Integration multipart 업로드 재현은 위 1번으로 완료.

## CI 인계 (2026-11-11 — 테스트 헬퍼 pdftotext→pdf-reader 전환)
- 오케스트레이터: 커밋·푸시 후 CI 결과 확인 필요. `test/services/tools/template_pdf_service_test.rb`의 `extract_text`를 PDF::Reader(순수 Ruby) 기반으로 전환, `Gemfile` pdf-reader를 `group :test`로 이동 — poppler 환경 의존 제거, CI Linux 4건 실패 소멸 대상. 로컬 5 runs 0 failures 확인.

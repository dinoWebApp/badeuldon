# 05_review — LP-11·BLOG 병렬 배치(T-E1~E4 + 3-S) Phase 5 코드 리뷰

- **일자**: 2026-11-11 · **Reviewer**: badeuldon-reviewer(절약 모드) · **PRD 기준**: v0.37(BLOG-1~8·LP-11·ADMIN-10·Q18~Q20)
- **검증 방식**: 코드 정독 + **컨트롤러 경유 통합 재현(Run A~C 교훈 적용 — admin 2FA 실로그인·U1 세션·비인증 HTTP 요청 수준, /tmp 임시 테스트 22케이스 실행 후 삭제·레코드 트랜잭션 롤백 확인: dev BlogPost=0)** + sanitize 우회 주입 실측
- **범위**: T-E1 블로그 코어 · T-E2 도구 3종 · T-E3 허브 · T-E4 예약 발행 Job · 3-S 결선(routes·nav·헤더)

---

## 종판

```
status: CHANGES_REQUESTED   (BLOCKER 1 · CRITICAL 4 · WARNING 6)
```

BLOCKER 1건(B-1 관리 폼 multipart 누락 — 실브라우저 발행 플로우 불능)과 CRITICAL 1건(C-1 예약 발행 UI 진입점 부재 — Q20 Job 죽은 경로)은 **Run A~C의 "컨트롤러는 통과했지만 뷰-컨트롤러 계약 파탄" 전형 패턴**이다. 수정 후 **B-1·C-1 재리뷰(재현 스크립트 동일 실행)** 대상이며, 나머지는 수정 요청 반영 확인만 수행한다. 전체 게이트(테스트 1,064·rubocop 305 files 0 offenses)는 오케스트레이터 확인치를 전제하되, B-1이 보여주듯 HTML 계약은 기존 테스트가 볼 수 없는 영역이므로 수정 시 **렌더 HTML 어설션 테스트를 정식 테스트로 편입**할 것을 권고한다.

---

## 이슈 목록

### B-1 · BLOCKER · BLOG-5 — 관리 폼에 `enctype="multipart/form-data"` 누락 → 실브라우저 첨부·발행 불능

- **파일**: `app/views/admin/blog_posts/_form.html.erb:9`(form_with), `:63·:69`(file_field)
- **재현(실측)**: 렌더된 폼 태그가 `<form class="space-y-4" action="/admin/blog_posts" accept-charset="UTF-8" method="post">` — **enctype 없음**. 같은 페이지에 `<input type="file">` 2개(썸네일·OG) 존재.
- **파급**: 비-multipart 폼의 file 입력은 파일 본문 없이 파일명 문자열만 전송된다 → thumbnail·og_image가 **절대 첨부되지 않음** → `publishable?`이 상시 실패 → **관리 UI에서 발행이 영구 불가능**(BLOG-5 필수 필드 검증이 항상 막음). 통합 테스트는 모델에 직접 `attach`해서 이 결함을 볼 수 없었다(3-S 테스트도 동일 — Run A~C 교훈의 정확한 재현).
- **원인**: 폼이 `form_with ... do %>`로 **블록 변수 없이** top-level `file_field :blog_post, :thumbnail`을 사용. Rails의 multipart 자동 감지는 `FormBuilder#file_field`(=`f.file_field`)가 빌더에 `multipart=true`를 표시할 때만 동작(`actionview .../form_helper.rb:776 options[:multipart] ||= builder.multipart?`) — top-level 헬퍼는 빌더와 무관해 enctype이 세팅되지 않는다. 같은 저장소의 티켓 폼(`app/views/app/tickets/new.html.erb:39`)은 `f.file_field` 선례.
- **수정 권고**: `_form.html.erb`를 `<%= form_with model: blog_post, url: ..., do |f| %>` + `f.text_field`·`f.file_field` 계열로 전환(가장 깔끔 — 티켓 폼 선례 준용). 또는 폼에 `multipart: true` 명시만으로도 즉효. 수정 후 `assert_match 'enctype="multipart/form-data"'`를 admin 컨트롤러 테스트에 추가할 것.

### C-1 · CRITICAL · BLOG-5·Q20 — 예약 발행 UI 진입점 부재 → schedule member·PublishScheduledJob이 죽은 경로

- **파일**: `app/views/admin/blog_posts/index.html.erb:44-59`(버튼 분기), `app/controllers/admin/blog_posts_controller.rb:62`(schedule — 테스트에서만 호출)
- **재현(실측)**: admin index 렌더 본문에 "예약 발행" 트리거 부재(=false). `grep -rn schedule_admin_blog_post_path app/` → **뷰 0건**(테스트만 3건). draft 행 버튼은 "발행", scheduled 행은 "예약 취소·즉시 발행"뿐.
- **파급**: ① 상태를 scheduled로 만드는 유일한 경로가 `PATCH .../schedule`인데 UI가 그것을 호출하지 않는다 → Q20 매분 스캔 Job이 정상 운영에서 **영원히 대상 0건**(T-E4 전체가 도달 불가). ② BLOG-5의 4상태(초안/예약 발행/발행/비공개) 중 "예약 발행" 상태를 관리 화면에서 만들 방법이 없다. ③ 폼의 "발행 예정 시각" 필드와 "저장"만으로는 상태가 바뀌지 않아 관리자 혼란 유발. ④ 우회 경로(즉시 발행 + 미래 publish_at)로 노출 지연은 가능하지만 상태 배지는 "공개"로 표시되어 구현된 Q20 설계와 어긋난다.
- **수정 권고**: index 각 행(또는 edit 폼)에 "예약 발행" button_to(`patch schedule_admin_blog_post_path(post)`, `blog_post[publish_at]` 포함)를 추가해 폼의 publish_at 값을 전달하거나, edit 폼에 "예약 발행으로 저장" 서브밋을 둔다. UI 연결 후 T-E4 테스트가 실제로 도달 가능함을 컨트롤러 테스트로 유지.

### C-2 · CRITICAL · BLOG-1·BLOG-2 — 카테고리 경로형 `/blog/category/{카테고리}` 미구현(쿼리 파라미터로 대체) — sitemap에도 쿼리형 URL 노출

- **파일**: `config/routes.rb`(blog 블록 — category 라우트 없음), `app/views/blog/index.html.erb:16·42`, `app/controllers/sitemaps_controller.rb:11`
- **재현(실측)**: `GET /blog/category/docs` → **404**. `GET /blog?category=docs` → 200. sitemap.xml이 `blog?category=scripts` 형태의 5개 URL을 색인 요청에 광고.
- **명세 대조**: PRD v0.37 BLOG-1 원문 "**카테고리 `/blog/category/{카테고리}`**" — 경로형이 명시. 3-S 산출물은 이 차이를 "발견 이슈 1"로 기록했으나 "지시 범위 밖"이라며 미수정했고, 02_prd_update도 경로형 문언을 그대로 두어 **PRD-코드 불일치가 문서에 확정돼 있음**.
- **수정 권고**: (a) 경로형 라우트 추가 — `get "/blog/category/:category", to: "blog#index", as: :blog_category`(슬러그 조회와 라우트 우선순위 충돌 없음 — `/blog/:slug`보다 먼저 선언) + 허브 카드·필터 pill·sitemap을 헬퍼로 전환. 또는 (b) 쿼리형을 채택하기로 **PRD BLOG-1 문언을 개정**(3-S 발견 이슈를 결정 기록으로 승격). (a)가 SEO 클러스터링(LP-11 전략)에 유리 — 키워드 경로가 URL에 노출된다.

### C-3 · CRITICAL · BLOG-3 — 페이지네이션 "커서 기반" 명세 대신 offset/limit 구현 + PRD v0.37 갱신문이 사실과 다르게 "커서 기반 구현 확정" 기재

- **파일**: `app/controllers/blog_controller.rb:17-18`(offset/limit), `PRD.md §7.2 BLOG-3`, `_workspace/02_prd_update.md`(BLOG-3 "페이지당 12건 커서 기반" 주장)
- **재현(실측)**: 13건 페이지네이션 동작은 정상(R7b 2페이지 확인). 그러나 구현은 `offset((page-1)*12).limit(12)` — 커서 아님.
- **파급**: 기능은 동작하나 ① PRD 원문과 02 갱신문 모두 "커서 기반"을 명시 → 명세-코드 불일치가 문서로 확정 ② offset 페이저는 페이지 이동 중 신규 발행 시 중복/누락 가능(발행빈도가 낮은 블로그라 실위험 낮음).
- **수정 권고**: (a) offset/limit을 유지하려면 **PRD BLOG-3 문언을 개정**(12건·오프셋 페이저로) — 커서는 최신순 목록에 과한 설계라 개정이 합리적. (b) 커서를 지키려면 `published_at < cursor` 방식으로 전환.

### C-4 · CRITICAL · BLOG-6 — 발행 시 내부 링크 부재 경고 미구현 (PRD v0.37 "구현 확정" 문언과 코드 불일치)

- **파일**: `app/controllers/admin/blog_posts_controller.rb`(publish), `app/models/blog_post.rb`(publishable?), `app/views/admin/blog_posts/_form.html.erb` — 전부 경고 로직 없음(grep 확인)
- **명세 대조**: PRD v0.37 BLOG-6 "**발행 시 내부 링크 부재 → 경고 표시(강제 아님)**" + 02_prd_update "구현 확정" — 그러나 어떤 계층에도 구현이 없다. BLOG-6 본문 의무("관련 무료 도구 또는 관련 게시글 1개 연결")는 관련 글 자동 추천(BLOG-4)으로 부분 충족되지만, **발행 시 경고**는 전무.
- **수정 권고**: `publish` 액션에서 발행 성공 후 본문에 `/tools|/blog/` 내부 링크 부재 시 redirect alert에 경고 문구 덧붙이기(강제 아님 — 303 유지). 1~3줄 소요. 또는 PRD 문언 개정.

### W-1 · WARNING · T-E4 — recurring.yml development 블록 `subscription_trial_expiry` **중복 키**(편집 사고)

- **파일**: `config/recurring.yml:48-51` — 48행 `subscription_trial_expiry:`(값 nil) + 49행 동일 키(실값). T-E4 diff에서 `+`로 삽입됨.
- **실측**: Psych last-wins으로 로드되어 동작은 유지(값 확인 완료). 그러나 YAML 사양 위반이며 Psych 버전 상향 시 경고·파서 실패 위험. production 블록은 정상.
- **수정 권고**: 48행 삭제 1줄.

### W-2 · WARNING · BLOG-5 — schedule! 무효 publish_at 문자열 → status=scheduled + publish_at=nil "좀비 예약" (303 성공 응답)

- **파일**: `app/models/blog_post.rb:86-92(schedule!)`, 컨트롤러 `schedule`
- **재현(실측)**: `PATCH schedule`에 `publish_at: "not-a-date"` → 응답 303 성공, 결과 `status=scheduled publish_at=nil`. nil publish_at은 `publish_at: ...Time.current` 스캔에서 영원히 미달 → Job도 못 건지고 노출도 안 되는 상태. 관리자에게는 "예약 발행이 설정되었습니다" 안내.
- **수정 권고**: schedule!에서 `at = Time.zone.parse(at.to_s)` 후 `at.nil?면 errors.add(:publish_at, :invalid); return false` — 컨트롤러 alert가 이미 실패 분기를 갖고 있어 즉시 수렴.

### W-3 · WARNING · BLOG-3·Q20 — 주석이 실제 동작과 반대 (유지보수 오판 위험)

- **파일**: `app/models/blog_post.rb:52-54`(published_now 주석 "상태 전환 지연과 무관하게 시각 경과 시점부터 노출"), `config/recurring.yml:41-42`("예약 노출은 published_now scope로 즉시 반영"), `app/views/blog/show.html.erb:3`("raw 출력" — 실제는 48행 이중 sanitize)
- **실측**: published_now는 `status: published`를 필수로 하므로 **scheduled 상태 게시글은 잡 전환 전까지 노출되지 않는다**(최대 1분 유예 — 안전 방향이므로 동작 자체는 문제없음). 주석만이 없는 동작을 서술.
- **수정 권고**: 주석 3곳을 실제 동작("예약 노출은 잡 전환 후·최대 1분 지연")으로 수정. show.html.erb:3은 "sanitize 이중 통과 출력"으로.

### W-4 · WARNING · LP-11 — 허브 도구 카드 문구 세금 용어 오기: "부가세 3.3% 원천징수"

- **파일**: `app/views/blog/_tool_cards.html.erb:10` — "부가세 3.3% 원천징수 후 실수령액을 계산해 보세요"
- **파급**: 3.3%는 부가세가 아니라 **원천징수**(사업소득 주민세 포함). 프리랜서 세금 클러스터(LP-11 ④) 진입 문구의 사실 오류는 서비스 신뢰도를 직격 — 같은 배치의 tools 페이지 문구("원천징수 빼고 얼마 받는지")와 계산기 결과 라벨("원천징수 (3.3%)")은 정확하다.
- **수정 권고**: "원천징수 3.3%를 반영한 실수령액을 계산해 보세요"로 수정.

### W-5 · WARNING · SURF-6 — blog index·related 썸네일 N+1 (12건 × attached? 쿼리)

- **파일**: `app/controllers/blog_controller.rb` index/show(@related), `app/views/blog/index.html.erb:51`
- **실측**: `post.thumbnail.attached?`가 게시글마다 attachment 1쿼리(페이지당 최대 12+3). SQLite 로컬에서 치명적이진 않으나 SURF-6 2초 예산·트래픽 증가 시 직접 영향.
- **수정 권고**: scope에 `includes(:thumbnail_attachment)` 추가(og_image는 목록 미사용이라 불요).

### W-6 · WARNING · 아키텍처(AGENTS 코딩 컨벤션) — 뷰에서 모델 클래스 메서드 호출 (`BlogPost.categories.keys`)

- **파일**: `app/views/blog/index.html.erb:15·41`, `app/views/admin/blog_posts/_form.html.erb:24`, `app/views/admin/blog_posts/index.html.erb:14`
- **대조**: AGENTS "뷰에서 DB 쿼리/모델 클래스 메서드 호출 금지". enum accessor이라 쿼리는 아니지만 문자 규정 위반이며 기존 뷰에는 선례가 없다(본 배치가 최초 도입).
- **수정 권고**: `BlogHelper`에 `CATEGORY_KEYS = BlogPost.categories.keys.freeze` 상수 두고 뷰는 헬퍼 상수만 참조(헬퍼는 모델 참조 가능 — 기존 CATEGORY_LABELS 패턴 준용).

---

## 통과 커버리지 (실측 재현으로 확인)

| 영역 | 검증 결과 |
|---|---|
| **C-1 sanitize·XSS(최우선)** | `<script>`·`<img onerror>`·`javascript:` href·`<iframe>`·inline style·onclick·data-* 주입 → 저장 body_html과 published 상세 렌더 **전부 제거 실측**(텍스트 본문은 보존). **DB 저장값을 직접 오염(update_column)해도 출력 시점 sanitize 2층이 script·onerror·javascript:·iframe 전부 차단** — 이중 sanitize 실증. raw는 JSON-LD `to_json` 1건뿐(Activesupport escape 내장 — 안전) |
| **slug 파라미터 주입** | `%2e%2e%2fapp`·대문자·`<script>`·300자 — 전부 404 안전 처리 |
| **BLOG-1 301** | 슬러그 A→B→C 이중 변경 후 old slug 접근 시 **최신 C로 단일 홉 직행 301**(체인 왕복 없음 — SEO상 바람직)·존재 없는 슬러그 404·리다이렉트 대상 비공개 404·무한 루프 소지 없음(A·B 모두 현재 slug로 수렴) |
| **BLOG-3 공개 범위** | draft/scheduled/hidden 비인증 노출 없음(404·목록 미노출) — PROMISE-7류 마감 우회 구조와 무관, published만 |
| **BLOG-2 SEO** | 메타 기본값·og:title·og:image·canonical 자사(BLOG-8)·Article JSON-LD·sitemap 게시글 반영·**noindex 미출력(색인 허용 — NOINDEX_PATH_PREFIXES 미포함 실측)** |
| **Q20 Job** | 도과 다수 scheduled 전수 전환·검증 실패 1건 skip 격리·재실행 멱등(스캔 배제+publish! nop 이중) |
| **LP-11 도구 3종** | 4경로 200·톤 4종 기본 정중·거래처명 `<b>` 주입 **HTML 이스케이프 실측**·10KB 문자열·배열 파라미터 200(방어)·계산기 무효/음수 거부·부가세 포함 환산·967,000원 산식·PDF `%PDF` 헤더 + **pdftotext 한글 추출 정상(가나디자인·웹디자인 — B2 OTF 회귀 없음)**·샘플 폴백 |
| **P3** | /tools·계산기 응답 **Set-Cookie nil 실측** — 세션·쿠키 저장 없음 |
| **격리·권한** | admin blog CRUD 비인증 → 관리자 로그인 리다이렉트·**U1 세션 publish PATCH 차단**·slug status 대량할당 없음(blog_params에 status 미허용)·slug 중복 422 |
| **ADMIN-10·3-S** | admin nav "공지·콘텐츠" 노출·랜딩 헤더 블로그 링크(SURF-4 허용 갱신)·`/tools`·`/blog` 리터럴 href 잔존 0건(grep)·`.pdf` 라우트 선행 선언 실측 정상 |
| **아키텍처** | 컨트롤러 액션 10줄 이내·Service 순수 함수·Job 인자 없음·member PATCH 정당화·의존 방향 위반 없음 |

## Rule ID 준수 매핑

| Rule | 판정 | 비고 |
|---|---|---|
| BLOG-1 | **부분** | 슬러그·301·형식 통과. **카테고리 경로형 미구현 → C-2** |
| BLOG-2 | **부분** | 메타·JSON-LD·sitemap·색인 허용 통과. title 기본값이 "제목+사이트명"이 아닌 제목 단독(경미 — C-2 수정 시 병행 권고) |
| BLOG-3 | **부분** | published만·12건 통과. **커서→offset 편차 → C-3** |
| BLOG-4 | 통과 | 목차·관련 글 3·CTA 2종(도구 aside+헤더 가입)·fragment 캐시 |
| BLOG-5 | **부분** | 모델·검증·렌더 저장 통과. **multipart 폼(B-1)·예약 UI(C-1)로 관리 플로우 단절** |
| BLOG-6 | **미구현** | 내부 링크 경고 없음 → C-4 |
| BLOG-7 | 통과 | 댓글 없음·공유 3종(카카오톡 스킴·X·복사) |
| BLOG-8 | 통과 | canonical 자사 실측 |
| LP-11 | 통과(W-4 문구) | 도구 3종 무가입·CTA 각 페이지 배치·5클러스터 허브 |
| ADMIN-10 | 통과 | 콘텐츠 메뉴 통합(nav 실측) |
| Q18 | 통과 | kramdown+allowlist·이중 sanitize 실증 |
| Q19 | 통과 | 5클러스터 고정 enum·태그 자유 |
| Q20 | 통과(도달성 C-1) | 매분 스캔·멱등·부분 실패 격리 실측 |
| SURF-3/4 | 통과 | blog·tools 색인 허용·랜딩→블로그 허용 갱신 |
| DESIGN | 통과 | 크림·딥 그린·min-h-11 터치 타깃·탭 없음·위계 유지(표면 퍼블리싱 선례 톤 준용) |

## Tester 중점 테스트 제안 (수정 후)

1. **실브라우저 발행 E2E(최우선)**: 시스템 테스트로 관리 폼에서 실제 파일 첨부 → 저장 → 첨부됨 표시 → 발행 성공까지(enctype 수정 회귀 방지). IntegrationTest의 직접 attach로는 B-1을 못 본다.
2. **예약 발행 전 경로 UI→Job→노출**: 폼/버튼에서 publish_at 지정 → scheduled 확인 → Job perform → /blog 노출 시점(C-1 수정 검증).
3. **경로형 카테고리**(C-2 채택 시): `/blog/category/{key}` 200·sitemap URL 형식·허브 카드 링크 경로.
4. **수동 회귀**: 독촉 문구 이스케이프(`<b>` 거래처명)·계산기 공유 URL 재현·PDF 한글 pdftotext·`/blog?category=` → 404 아님 확인.

## 교차 확인

- 전체 테스트 1,064건·rubocop 305 files 0 offenses는 오케스트레이터 확인치 — 재실행하지 않았다. 단 B-1·C-1이 증명하듯 기존 게이트는 HTML 폼 계약을 커버하지 못하므로, 위 1번 시스템 테스트 편입을 Phase 7 수정 분에 포함할 것.
- 리뷰 재현 스크립트는 /tmp에서 실행 후 삭제 완료·dev DB 잔존 레코드 0건 확인(BlogPost=0·BlogSlugRedirect=0). 코드 수정은 일절 하지 않았다(읽기 전용 준수).

---

# 재리뷰 (루프 1/2) — Phase 6 수정 검증 (2026-11-11)

- **검증 방식**: 원 이슈 11건 전건 독립 재현(/tmp Integration — admin 2FA 실로그인·multipart fixture 업로드·순차 travel_to 시간 제어, 실행 후 삭제·dev 잔존 레코드 0건) + 수정 파일 정독 + 회귀 재점화
- **정식 테스트 재실행 확인**: 블로그 연관 5종 파일 **42 runs, 308 assertions, 0 failures**(개발자 보고치와 일치)

## 이슈별 해소 판정

| 이슈 | 판정 | 재현 근거 |
|---|---|---|
| **B-1** multipart 누락 | **해소** | new 렌더에 `enctype="multipart/form-data"` 실측 + FormBuilder 전환 후 11개 필드 `name=` 전부 유지 + **fixture PNG(1×1) multipart create 303 → thumbnail·og_image 실첨부(content_type image/png) → publish 303 → published** E2E. 정식 테스트 편입(`fixture_file_upload` — enctype 회귀 방어) 확인 |
| **C-1** 예약 UI 부재 | **해소** | edit 렌더에 `schedule_admin_blog_post_path` 트리거 + 서브폼 `name="blog_post[publish_at]"`(컨트롤러 blog_params 계약 일치) 실측 → schedule(13:30) → scheduled → 예약 시각 전 /blog 404 → **Job perform(13:31) → published → /blog/:slug 200 노출** 전 체인. published 상태에선 서브폼 미노출(상태 중복 전이 방지) |
| **C-2** 카테고리 경로형 | **해소** | `/blog/category/tax` 200·필터 동작·`/blog/category/:category`가 `/blog/:slug`보다 선행 선언 확인·허브 카드+pill href 5종 전부 path형(뷰 쿼리형 잔존 0)·sitemap path형 URL·쿼리형 레거시 호환 200·**`/blog/category`(단일 세그먼트)는 slug 조회로 흡수되어 404 — 라우트 충돌 없음** 실측 |
| **C-3** 커서 명세 | **인계 완료** | 코드 유지(offset/limit)+PRD 문구 정정 인계 기록 — Phase 7 오케스트레이터가 PRD BLOG-3 "커서 기반"→"오프셋 페이저" 정정하면 종결 |
| **C-4** 내부 링크 경고 | **해소** | 링크 없음 → notice에 "내부 링크가 없습니다"(발행 자체는 303 성공)·`/blog/…`·`/tools` 링크 있음 → 경고 부재 실측. 정규식 경계 관찰: leading slash 없는 상대 링크(`blog/slug`)는 미일치로 경고 표시되나 강제가 아닌 참고 문구라 실害 없음(관찰 기록) |
| **W-1** YAML 중복 키 | **해소** | development 7·production 8 tasks, 중복 키 0(파싱 실측) |
| **W-2** 좀비 예약 | **해소** | `publish_at: "not-a-date"` → 303 alert + **draft 유지·publish_at nil**(좀비 없음)·blank도 거부. `Time.zone.parse` nil 가드 확인 |
| **W-3** 주석 불일치 | **해소** | published_now 주석(잡 전환 후 노출·최대 1분 유예)·recurring.yml 주석·show.html.erb "이중 sanitize 통과 출력" 정정 확인 |
| **W-4** 세금 용어 오기 | **해소** | "원천징수 3.3%를 반영한" 정정 확인 |
| **W-5** N+1 | **해소** | index·@related `includes(:thumbnail_attachment)` — 재현 렌더 정상(index 6쿼리·show 6쿼리 관찰) |
| **W-6** 뷰 모델 호출 | **해소(잔존 1건)** | `BlogHelper::CATEGORY_KEYS` 상수로 전환 — 뷰의 `BlogPost.categories` grep 0건. **잔존 관찰**: `admin/blog_posts/index.html.erb:11`의 `BlogPost.statuses.map` 1건은 동일 규정 클래스로 남아 있음(카테고리와 동일 패턴의 STATUS_KEYS 상수화 권고 — 다음 터치 시 반영, 게이트 영향 없음) |

## 수정으로 유입된 회귀 검증 (지시 2·3항)

- **FormBuilder 전환 회귀**: 없음 — 필드 name 11종 유지·multipart create·update·schedule 서브폼 파라미터 전달·select 값(enum key) 전부 실측 통과.
- **path형 라우트 충돌**: 없음 — `/blog/category/tax` 200·`/blog/category` 단일 세그먼트는 slug 조회(404 무해)·`blog_post_path` 생성 정상.
- **W-5 includes 후 렌더**: 정상 — index·상세·관련 글 전부 200.
- **C-4 거짓 경고**: 최소 케이스(상대 경로 링크 무선택 slash)만 존재 — 참고 문구이며 강제 없어 파급 없음. 절대 URL(`badeuldon.kr/tools`)·마크다운 표준 상대경로(`(/blog/x)`)는 정상 일치.
- **이전 라운드 통과 영역 재점화**: sanitize 이중 방어(DB 오염 주입 재실측 차단)·301 단일 홉 체인·도구 P3(Set-Cookie nil)·PDF %PDF — 회귀 없음.

## 신규 이슈

- **없음** (BLOCKER 0 · CRITICAL 0 · WARNING 0 — 위 잔존 관찰 1건은 W-6 스코프의 미완 슬라이버로 기록)

## 재리뷰 종판

```
status: APPROVED   (원 이슈 11건 중 10건 해소·1건(C-3) 문서 정정 인계 완료 — BLOCKER 0+CRITICAL 0)
```

- Phase 7 진행 조건: ① PRD v0.37 BLOG-3 문구 "커서 기반"→"페이지당 12건 오프셋 페이저" 정정(C-3 인계) ② `admin/blog_posts/index.html.erb`의 `BlogPost.statuses.map` → BlogHelper 상수화(잔존 관찰 — 다음 런에서 해소 권고, 게이트 아님) ③ 시스템 테스트(실브라우저 첨부 E2E)는 Phase 7 인계 대로.
- 리뷰 재현 스크립트 /tmp 삭제 완료·코드 수정 일절 없음(읽기 전용 준수)·dev DB 잔존 레코드 0건.

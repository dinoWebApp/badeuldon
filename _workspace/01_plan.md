# 01_plan — LP-11 콘텐츠 허브·블로그 + ADMIN-10 통합 (2026-11-11, §6.14 병렬 재판정 · 절약 모드)

## §6.14 병렬 재판정 (BLOG/LP-11 전체 명세 확인 후)

**결론: 2단계 혼합 구조 — 코어는 단독 선행, 잔여는 fan-out.**

전체를 한 번에 fan-out하려 했으나 의존 사슬이 확인됨: 허브·도구·ADMIN-10 모두 **블로그 코어(posts 모델·admin CRUD)를 선행 참조**. 반면 코어 완료 후에는 소유권이 분리되어 병렬 가능(§6.14 "완료된 선행 산출 참조는 허용").

| 단계 | 태스크 | 구성 | 판정 |
|---|---|---|---|
| **3-P (선행 단독)** | **T-E1 블로그 코어** | posts 모델·admin 콘텐츠 CRUD(ADMIN-10·BLOG-5)·`/blog` 목록·상세·카테고리(BLOG-1/3/4)·SEO(BLOG-2)·사이트맵 | 단독 — 코어가 전체의 선행 |
| **3-Q (fan-out·선행 완료 후)** | **T-E2 무료 도구 3종**(LP-11) | 독촉 문구 생성기·3.3% 계산기·청구서 양식 다운로드 — 가입 없이·각각 독립 컨트롤러/뷰 | 소유권 분리 ✓ |
| | **T-E3 LP-11 허브 통합** | /blog를 허브로(5클러스터 카테고리·CTA·내부 링크 BLOG-6·공유 BLOG-7) | 블로그 코어 참조 — 선행 완료 후 병렬 ✓ |
| | **T-E4 ADMIN-10 완성** | 콘텐츠 메뉴 통합(공지+블로그)·예약 발행 Job | 소유권 분리 ✓ |
| **3-S** | 결선 | routes·nav(랜딩 헤더 블로그 링크)·migrate·스모크 | |

fan-out 위임 제약 준수(소유권 화이트리스트·runner 자기검증·전체 테스트 금지·문서 금지).

## 구현 범위

### T-E1 블로그 코어 (선행 단독)
- `blog_posts` 마이그레이션: title·slug(고유·indexed)·body(마크다운 원문)·rendered_html(서버 렌더 후 저장)·category enum(LP-11 5클러스터: rem Scripts→알림·수금 시나리오 / recovery→미수금·내용증명 / docs→청구서·양식 / tax→프리랜서 세금 / stories→수금 사례)·tags(string 배열)·status enum(draft:0/scheduled:1/published:2/private:3 — BLOG-5)·publish_at(예약)·meta_title·meta_description·og_image(AS 첨부)·thumbnail(AS 첨부)·views counter(캐시 컬럼·표시용)·timestamps
- slug: 발행 시 지정(BLOG-1)·변경 시 301 리다이렉트 테이블(`blog_slug_redirects` old_slug→post_id — BLOG-1 요건)
- Admin 콘텐츠 CRUD: `Admin::BlogPostsController`(ADMIN-10·BLOG-5 — 목록·상태 전이·예약 발행·필수 필드 검증: 제목/슬러그/본문/썸네일/카테고리/태그/메타 2종/OG 이미지)
- AS 첨부: thumbnail 1장·og_image 1장(Run C의 AS 재사용)
- 공개 표면: `BlogController`(공개·비로그인·**색인 허용** — SURF-3 예외: /blog는 indexable) — 목록(최신순·카테고리 필터·페이지네이션·썸네일·요약·발행일·카테고리 — BLOG-3)·상세(본문 렌더·목차·관련 글·CTA 2종·공유 버튼 — BLOG-4/7)·slug 301 리다이렉트
- SEO: 메타 태그·OG 태그·Article JSON-LD(BLOG-2)·`sitemap.xml`(게시글 자동 반영)
- 렌더: **kramdown**(마크다운→HTML·Gemfile 추가)+`Rails::HTML` sanitize(Reminder 금지 표현과 별개 — XSS 방어 목적)·렌더 결과는 DB 저장(요청 시 재렌더 방지·수정 시 재렌더)
- 목차: h2/h3에서 파생(렌더 시 생성·앵커 부여)
- 예약 발행: `BlogPosts::PublishScheduledJob`(매분 스캔·publish_at ≤ now && scheduled → published 전환)·recurring.yml 등록
- 표기: SURF-3 예외 명시(/blog는 색인 허용 — BLOG-2 "SURF-3을 따른다"의 해석: 블로그는 공개 콘텐츠이므로 NOINDEX_PATH_PREFIXES에서 제외)

### T-E2 무료 도구 3종 (LP-11 — 가입 없이)
- `ToolsController`(공개·비로그인) + 3 도구:
  1. **독촉 문구 생성기** — 4단계 톤 선택(REM-2: 부드러움/정중/사실적/강경)·상황 입력(거래처명·금액·만기일) → 문구 3종 생성(서버 템플릿 조합·LLM 없음 — P5 안전) → 복사 버튼·주 CTA(가입 유도)
  2. **3.3% 계산기** — 공급가액 입력 → 원천징수 3.3%·실수령액·부가세 계산(클라이언트 JS or 서버) → 복사·CTA
  3. **청구서 양식 다운로드** — 간단 입력(거래처·품목·금액) → **PDF 양식 생성**(T-D2 Prawn+TTF 재사용 — Invoices::TemplatePdfService) → 다운로드·CTA
- 각 도구: 개별 경로(`/tools/reminder-generator` 등)·도구 결과 화면에 주 CTA 배치(L P-11 문언)·noindex 아님(색인 허용 — LP 유입 목적)
- 폼 제출 없이 즉시 결과(가입 없이 요건)·세션·쿠키 저장 없음(P3·프라이버시)
- 소유: `app/controllers/tools/`·`app/views/tools/**`·`app/services/tools/`(문구 생성 로직)·테스트

### T-E3 LP-11 허브 통합
- `/blog` 목록을 허브로: 5클러스터 카테고리 네비게이션·**무료 도구 3종 진입 카드**(T-E2 링크)·CTA 배치
- 랜딩(/) 헤더에 "블로그" 링크 추가·푸터 링크
- 내부 링크 검증: 게시글에 도구/관련 글 링크 존재 검증은 발행 시 경고(강제 아님·BLOG-6 "의무" — admin 검증 경고)

### T-E4 ADMIN-10 완성
- admin nav "콘텐츠" 메뉴 — 공지(T-C Run C)·블로그(T-E1) 통합 진입
- 예약 발행 Job 등록·감사 기록(발행/비공개 전환)

### 3-S 결선
- routes 결선(blog·tools·admin blog_posts)·nav·LP-11 허브 페이지 통합(도구 카드+최신 글)·migrate·스모크·**컨트롤러 최초 HTTP 검증**(블로그 목록·상세·도구 3종·admin CRUD — U1/admin 실세션)

## 대상 파일 요약

T-E1: 마이그레이션 2(posts·slug_redirects)·모델 2~3·admin 컨트롤러+뷰·BlogController+뷰·kramdown gem·사이트맵 / T-E2: tools 컨트롤러·서비스·뷰 / T-E3: 허브 뷰·nav / 3-S: routes·nav

## 관련 Rule ID

BLOG-1~8·LP-11·ADMIN-10·ADMIN-6(공지와 콘텐츠 메뉴 통합)·SURF-3(블로그 색인 허용 예외)·SURF-6(성능 예산)·REM-2(문구 생성기 톤)·PAY-3 참조(양식)·P3(도구 무가입)·P5(문구 생성기 — 법적 조치 금지 문구만)·TIME-1

## 리스크·모호점 (게이트 확정 대상)

1. **ADMIN-10 블로그 통합**: 블로그 CRUD가 admin 도메인에 들어가므로 T-E1이 ADMIN-10을 흡수(콘텐츠 메뉴 = 블로그+공지) — 별도 태스크 제거
2. **마크다운 렌더 gem**(kramdown — Gemfile 추가·T-E1 소유)·sanitize 정책(XSS 방어 — allowlist 명시)
3. **예약 발행 Job** 스캔 주기(1분) — Solid Queue recurring(`* * * * *` 매분) — 잡 컨테이너 부하 미미
4. **독촉 문구 생성기의 문구 데이터**: REM-2 4단계 톤별 템플릿 3종×4톤=12종을 서버 상수로(법적 조치·협박 금지 문구만 — P5·LP-12 준수·운영자 검수 문구 한정) — 사용자 입력 삽입은 이스케이프
5. **청구서 양식 PDF**: T-D2 Prawn 재사용 — 양식 샘플 데이터 고정(사용자 입력 일부 반영 가능)
6. **surf-6 성능**: 블로그 상де 렌더 2초 예산 — 캐시(fragment) 권고
7. **OG 이미지 필수** — 업로드 없이 발행 불가 검증(BLOG-5)
8. **사이트맵**: `/sitemap.xml` — 게시글+카테고리 자동 반영(BLOG-2)

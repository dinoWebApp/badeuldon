# 02_prd_update — LP-11·BLOG 병렬 배치 문서 현행화 (2026-11-11, Phase 2)

PRD v0.36 → **v0.37**. 배치 승인(T-E1 코어 + 3-Q fan-out 3태스크 + 3-S) 반영.

## PRD.md 변경 내역

| 위치 | 변경 요지 |
|---|---|
| 문서 버전 | v0.37 (LP-11 콘텐츠 허브·블로그 + ADMIN-10 콘텐츠 메뉴 구현 확정) |
| BLOG-1 | 구현 확정 — blog_slug_redirects(301)·슬러그 형식(소문자 영숫자+하이픈) |
| BLOG-2 | 구현 확정 — **블로그·도구 색인 허용(SURF-3 예외 명시)**·Article JSON-LD·/sitemap.xml·메타 기본값 |
| BLOG-3 | 구현 확정 — published만 공개·페이지당 12건 커서 기반 |
| BLOG-4 | 구현 확정 — 목차 렌더 파생(h2/h3·앵커)·관련 글 동일 카테고리 3건·SURF-6 fragment 캐시 |
| BLOG-5 | 구현 확정(Q18·Q20) — 마크다운 원문+렌더 HTML 별도 저장(kramdown·sanitize allowlist)·AS 첨부 2장·publish_at+매분 스캔 Job·slug 자동 생성 |
| BLOG-6 | 구현 확정 — 내부 링크 부재 시 경고(강제 아님)·관련 글 동일 카테고리 3건 |
| LP-11 | 구현 확정 — /blog 허브화·**무료 도구 3종 /tools 경로**(독촉 문구 생성기=REM-2 4단계 톤 검수 문구 상수·3.3% 계산기=클라이언트 즉시·청구서 양식 PDF=Prawn)·P3(쿠키 저장 없음)·ADMIN-10 콘텐츠 메뉴 통합 |
| ADMIN-10 | 콘텐츠 메뉴 통합 구현 확정(공지+블로그) — 관리 표면 단일화 완성 |
| 결정 기록 | Q18(마크다운+kramdown+sanitize)·Q19(5클러스터 고정 enum·태그 자유)·Q20(예약 발행 매분 스캔) 신설 |

## fan-out 전달 확정 해석

1. **3-Q fan-out은 T-E1 코어 완료 후** — 완료된 선행 산출 참조 허용(§6.14)·소유권 분리(도구=tools 도메인·허브=blog 뷰 확장·예약발행=job)
2. **sanitize allowlist**: kramdown 렌더 후 Rails::HTML5::Sanitizer allowlist(p·h1~h6·ul/ol/li·a[href]·strong/em·code/pre·blockquote·img[src alt]·table 계열)·스크립트·이벤트 핸들러·style 제거
3. **발행 폼 JS**: client-scorecard 컨트롤러(Run C 성적표)와 신규 블로그 요약이 공존 — 이벤트 격리 필수(리뷰 검증 대상)
4. **독촉 문구 생성기 문구**: REM-2 4단계(부드러움/정중/사실적/강경)×3종=12종 서버 상수 — 법적 조치·협박 표현 금지(REM-9 폐기 전례·LP-12 준수)·운영자 검수 완료 문구만 사용

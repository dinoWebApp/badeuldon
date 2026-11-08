# 02_prd_update — 기술 부채 병렬 배치 문서 현행화 (2026-11-09, Phase 2)

PRD v0.26 → **v0.27**. 배치 승인(T1~T4 전부)에 따른 구현 선행 명세 반영.

## PRD.md 변경 내역

| 위치 | 변경 | 근거 |
|---|---|---|
| 문서 버전 | v0.27 (기술 부채 배치 — Pretendard 셀프호스팅·ko locale·봇 UA 열람 제외·거래처 삭제 이력 보존) | Phase 2 필수 |
| CLIENT-1 | 삭제는 **발행 이력 없는 거래처(초안만 보유)**에 한함 — 발행 계열 존재 시 차단·안내(P4·REM-6) | T4 권고안 (a) 확정 — 스키마 변경 없는 모델 가드로 구현(기존 계획의 마이그레이션 불요로 정제) |
| SHARE-3 | 크롤러·봇 UA 접근은 열람 이력·최초 열람 전이·열람 알림(SHARE-4) 대상 **제외** | T3 — 오알림·집계 오염 방지. "기록 제외" 권고안 채택(마킹 기록 대안은 SHARE-3 집계 오염으로 배제) |
| DESIGN-3 | Pretendard **CDN 의존 없이 셀프호스팅** 명시 | T1 — 인앱·오프라인 안정성, PERF-2 정합 |
| ko locale | 규칙 변경 없음 — 인프라 기반 작업(버전 갱신 사유로 기록) | T2 |

## AGENTS.md

- 기술 부채 목록 갱신(셀프호스팅·ko locale·봇 UA 필터·ViewEvent 하드닝·client cascade P4 제거)은 **Phase 9 완료 보고에서** 일괄 수행 — 이 단계 미변경(하네스 관례)

## fan-out 전달 확정 해석 (각 지시서에 첨부)

1. **T1**: Pretendard **Variable woff2 단일 파일**(jsdelivr) → `public/fonts/`, `@font-face`는 Tailwind 진입 CSS, CDN `<link>`는 전 레이아웃(application·viewer·landing 계열)에서 제거
2. **T2**: `default_locale = :ko` + `rails-i18n` gem(Gemfile 독점 소유) + 앱 전용 `config/locales/ko.yml`. 회귀는 7-S 전체 게이트에서 흡수
3. **T3**: 봇 판정 UA 정규식은 **HeadlessChrome 제외**(Capybara 시스템 테스트 자체 UA가 HeadlessChrome — 필터에 넣으면 전 테스트 파괴). 테스트는 명시적 봇 UA(Googlebot 등)로. UA 500자 절단 하드닝 포함
4. **T4**: Client `before_destroy` 가드(발행 계열 청구 존재 시 throw(:abort)·오류 메시지) + ClientsController 친절 안내(소유권에 컨트롤러 추가 — 타 태스크 무접점). 마이그레이션 없음

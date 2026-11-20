# 01_plan — 랜딩페이지 전면 재구성 (2026-11-19, Standard+ · 일반 모드 · Sequential)

## 배경·목표

현 랜딩은 11개 파셜(626줄)로 핵심 3기능(열람 추적·리마인더·약속 수집) 중심. **F-SALES·반복 청구·세금계산서·dunning·주간 다이제스트 등 신기능 전반이 미노출** — "모든 기능 어필" 목표로 재구성. **uibowl mcp로 국내 SaaS 랜딩 레퍼런스 조회 후 벤치마킹**(사용자 지정 도구).

## 재구성 방향 (uibowl 관찰 반영 예정)

1. **신기능 커버리지 확대**: 반복 청구(INV-7)·전자세금계산서(TAX-1/2)·영업 추천(SALES)·dunning(PLAN-5)·이메일(AUTH-8)·주간 다이제스트(NOTI-2) — 기존 features 3카드 → 전 기능 커버 섹션으로 확대
2. **마케팅 강화**: 수치 배지·비포/애프터·소셜 프루프 슬롯(후기 미보유 → 계정 유치 CTA로 대체)·FAQ 확대·최종 CTA 반복
3. **기존 강점 유지**: hero·pain·how_it_works(5단계)·scenarios·message_samples·control(REM-15 안전장치)·pricing·LP-14 커버
4. **구현 방식**: 기존 파셜 수정 + 신규 파셜 추가(`_all_features`·`_sales_program` 등) — index.html.erb 재구성

## 태스크 분해 (Sequential — landing 파셜 다수 공유·index 재구성 단일 파일)

| 단계 | 내용 |
|---|---|
| 1 | uibowl mcp — 국내 SaaS 랜딩 UI 패턴 조회(요금제·기능 소개·CTA 배치) |
| 2 | Developer — 기존 파셜 보강(features 확대·FAQ 확대) + 신규 파셜(all_features·sales_program) + index 재구성 |
| 3 | 오케스트레이터 — uibowl 관찰 반영 검증(스크린샷 렌더) |

## 대상 파일

- 수정: `app/views/landing/index.html.erb`·`_features.html.erb`·`_faq.html.erb`·`_hero.html.erb`(CTA 문구)·`landing.html.erb`(헤더)
- 신규: `app/views/landing/_all_features.html.erb`·`_sales_program.html.erb`(추천 프로그램 어필)
- 테스트: 기존 landing 테스트 갱신(신규 섹션·문구 단정)

## Rule ID

LP-1~15(구조)·DESIGN-8(섹션 배경 리듬·인터랙션)·LP-12(금지 표현)·SURF-4(CTA 단일)·LP-11(블로그 연결)

## 리스크

1. 신규 섹션 추가로 페이지 길이 과다 — uibowl 관찰로 절제
2. 미보유 수치(사용자 수 등) 과장 금지 — LP-12 준수·실측 가능 수치만
3. 기존 landing 테스트 회귀 — 섹션 문구 변경 시 단정 갱신

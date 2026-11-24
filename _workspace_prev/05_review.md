# 05_review — LP-16 랜딩 전면 재구성 리뷰 (2026-11-20 · 일반 모드)

대상: `app/views/landing/index.html.erb` · `_all_features.html.erb`(신규) · `_sales_program.html.erb`(신규) · `_features.html.erb` · `_faq.html.erb` · `_hero.html.erb` — 계층 뷰(View)·정적 마크업. 근거: PRD v0.44 LP-16(신설)·LP-1~15·DESIGN-6/8·LP-12·SURF-4·SURF-6 · `_workspace/03_implementation.md`.

## Status: APPROVED (B0 · C0 · W2)

과거 선례(기술 부채 배치 APPROVED B0·C0·W3)와 동일 기준 — WARNING 2건은 반영 권장 사항이며 APPROVED를 저해하지 않음. 랜딩 테스트 실패 3건(31 runs, 3 failures, 0 errors — 리뷰 중 재현 확인)은 전부 예측된 기존 단정 갱신 대상(03 문서 §6·아래 Tester 지시)이며 코드 결함이 아님.

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | WARNING | LP-16 | `app/views/landing/_all_features.html.erb:11` | 헤드라인 "받을돈이 하는 일, **전부입니다**" — LP-16이 예시 나열한 항목 중 dunning(PLAN-5·결제 실패 재차감)과 이메일(AUTH-8)이 12카드에 없음. 두 항목 모두 랜딩 소구점이 아니라는 제외 판단 자체는 합리적(결제 운영 장치·계정 기능)이나, "전부" 단정과의 긴장이 있고 03 문서에 제외 근거가 명시돼 있지 않음. | ① 헤드라인 완화("받을돈이 하는 일"·"수금에 필요한 일을 한 곳에서" 등) 또는 ② 문구 유지 시 03 문서·02 PRD에 dunning·이메일 제외 판정 근거를 오케스트레이터가 명시. 오케스트레이터 판단 영역. |
| 2 | WARNING | LP-12·NOTI-2 | `app/views/landing/_all_features.html.erb:60-61` | 카드 ⑪ 주간 다이제스트 "매주 월요일 아침, … 요약해 알려드립니다" — 현재형 단정이나 알림톡 템플릿이 미등록 상태(NOTI-2: 템플릿 미등록 → skipped(NO_TEMPLATE)·등록 후 자동 활성화). Job·토글은 구현 완료라 "기능 서술"로 볼 수 있으나(03 문서 §4-5 판정), 가입자가 템플릿 등록 전까지 알림을 받지 못하는 기능의 현재형 단정은 LP-12(사실 서술) 경계. 반복 청구 카드⑤·FAQ의 "청구 안내 알림톡"은 issue_notice(**등록된** 템플릿·SHARE-6)라 사실 — 지적 대상 아님. | 오픈 전 NOTI-2 알림톡 템플릿 등록 완료를 운영 전제로 명시(AGENTS.md 예정 목록에 이미 존재)하거나, 등록 시점까지 카드 문구를 기능 예고형으로 완화. 템플릿 등록 완료 시 본 이슈 소멸. |

**BLOCKER · CRITICAL: 0건** — 12카드 전수가 실제 구현 기능과 일치(아래 매핑), 허구 기능 서술 없음, SURF-4 위반 링크 없음, DB 쿼리·런타임 에러 없음.

## 통과 근거 (전수 검증)

### 1. LP-16 문언 정합 — 12카드 vs 실제 구현 (BLOCKER급 부정확 서술 0건)

| 카드 | 서술 요점 | 실제 구현 검증 | 판정 |
|---|---|---|---|
| ① 열람 추적 | "연 순간 기록·즉시 알림" | SHARE-3/4 — ViewEvent·60초 내 noti_opened | 정합 |
| ② 자동 리마인더 | "만기 전날 예고~최종 안내, 받을돈 명의, 건당 최대 5통" | REM-1/2(기본 트랙 D-1/D+1/D+7/D+14)·PLAN-3(5통) | 정합 |
| ③ 입금 약속 | "가입 없이 버튼 클릭, 약속일에 리마인더 재조정" | P3·PROMISE·PROMISE-3(재스케줄) | 정합 |
| ④ 수금 마감 원클릭 | "마감하면 발송 정지·확인 감사 안내" | PAY-1·PAY-4(paid_thanks 기본 켬) | 정합 |
| ⑤ 반복 청구 [신규] | "매월 지정일 자동 발행 + 안내 알림톡" | INV-7(2026-11-11 구현)·issue_notice 자동 enqueue — issue_notice는 **등록된 템플릿**이라 알림톡 발송 서술은 사실(NOTI-3 noti_recurring_*과 무관) | 정합 |
| ⑥ 전자세금계산서 [신규] | "건당 300원·승인번호 기록·공동인증서 등록 후" | TAX-1/2(2026-11-16)·Q21·공동인증서 2단계 | 정합 |
| ⑦ 내용증명 | "기록 반영 양식·PDF·건당 5,000원·양식 생성까지만" | LEGAL-2/3/4·PLAN-7 | 정합 |
| ⑧ 수금 패스 | "10건 4,000원·90일" | PLAN-4 원문 수치와 동일 | 정합 |
| ⑨ 부분입금 | "잔액 자동 재계산·추가 입금마다 기록" | PAY-2·Q22/Q23 | 정합 |
| ⑩ 수신거부·안전장치 | "수신 거부 시 즉시 중단·발행인 통보·상한/사전통보" | VIEW-7·noti_refusal·REM-11/12 | 정합 |
| ⑪ 주간 다이제스트 | "매주 월요일 아침·만기/약속/수금 완료 요약" | NOTI-2 Job·토글 구현(2026-11-16) — 알림톡 템플릿만 미등록 → W-2 | 조건부 정합 |
| ⑫ 데이터 내보내기 [예정] | "CSV 내려받기·준비 중인 기능입니다" | SEC-4 미구현 확인(app 전역 CSV 부재) — 유일한 '예정' 배지 + 명시적 고지 | 정확한 사실 표기 |

**배지 판정 검증**: '신규' 2종(반복 청구 2026-11-11·전자세금계산서 2026-11-16 — 실제 최근 구현), '예정' 1종(SEC-4만 — 실제 미구현). 부정확한 배지 없음.

### 2. _sales_program — SALES 확정 조건 전수 정합

- "매주 월요일 자동 갱신·현재 유효한 코드만" = SALES-2 / "Plus 첫 결제 20% 할인·첫 달 7,920원·다음 달 정상가" = SALES-4·Q12 / "영업 파트너 20%(12개월)·지인 추천 15%(무기한)" = SALES-1(sales/officer 이원화의 정확한 일반화) / "매달 집계해 다음 달 정산·원천징수 3.3%" = SALES-5(직전월 실차감액·지급 M+1·3.3% 오프라인). **전 수치 PRD 확정치** — LP-12 준수.
- SALES 기능 실재 확인: `config/routes.rb` /sales namespace·sales_reps·sales_commissions — 미구현 기능 소개 아님.
- 참여 문의를 텍스트(카카오톡 채널 '받을돈')로 처리한 판정 타당 — /sales는 SALES-6 영업 직원 전용 로그인 표면이라 공개 참여 경로가 없고, 푸터 문의 채널(`layouts/landing.html.erb:48`)과 동일 패턴.

### 3. FAQ +4 — PRD 원문 정합

전자세금계산서("**사업자 유형 계정**에서 수금 마감 처리한 청구서에 한해" = TAX-1 원문 "사업자 유형 사용자에 한해, paid 건 한정"·300원·승인번호·공동인증서), 반복 청구("매월 발행일 **1~28일**" = INV-7·"일시중지하거나 재개" = recurring enum active/paused/cancelled + pause/resume 실재 확인), 추천 코드(SALES-2/3/4), 휴대폰 인증(AUTH-9 — 알림톡/SMS 폴백·5분). **기존 8항목 원문 불변 확인**(diff — 콤마 추가만).

### 4. SURF-4 — 링크 화이트리스트

신규 a 요소: `new_registration_path` 2개(all_features:99·sales_program:48 — 가입 CTA 허용) + 인페이지 앵커 `#all-features` 1개(_features:34). **인페이지 앵커는 ② 진입이 아니므로 SURF-4 위반이 아님**(SURF-4는 "①→② 진입"을 규제 — 앵커는 같은 문서 내 이동). mailto·외부 href·비밀번호 재설정 직접 진입 0건. 기존 SURF-4 테스트 실패 1건은 화이트리스트 갱신 문제(Tester 지시 1 참조).

### 5. SURF-6 · 아키텍처 · LP-12

정적 마크업 — DB 쿼리·모델 호출 0, `raw`/`html_safe` 0, Ruby 파일 변경 0, 이미지 파일 0(인라인 SVG), 콘텐츠 배열은 기존 `_faq` 파셜 관례와 동일. 금지 표현 스크린(100%·보장·추심 대행·마지막 알림 등) **검출 0건**. hero 배지 3종은 전부 PRD 확정치(PLAN-2 첫 14일·PLAN-3 5통·REM-2 4단계) — "알림톡 19종" 회피 판정은 NOTI-1 18종+초안의 산정 모호성을 고려하면 타당(03 문서 §4-3).

### 6. DESIGN-8 — 배경 리듬·인터랙션·접근성

13섹션 배경 실측: cream(hero 그라데이션)→white(pain)→cream(how)→white(features)→cream(all_features)→ivory(scenarios)→cream(samples)→white(control)→ivory(sales_program)→cream(positioning)→white(pricing)→cream(faq)→white(closing) — **인접 동일 배경 0건**. 카드 hover(-translate-y-0.5·shadow-md)·CTA focus-visible 링·아이콘 aria-hidden 적용·텍스트 대비 양호(stone-500/white·emerald-700/cream). h2(섹션)+h3(카드) 구조 — h1 1개 단정 유지.

### 7. 순서 논리·CTA

hero→pain→how→features→all_features→scenarios→samples→control→sales_program→positioning→pricing→faq→closing — `index.html.erb:9-21`과 일치. 통제(신뢰) 직후·가격 직전에 추천 프로그램 배치는 가격 저항 완화 흐름으로 합리적. 가입 CTA 4곳(hero:29·all_features:99·sales_program:48·closing:13) 실측 — LP-16 "CTA 반복 배치" 충족.

### 8. 기존 규칙 회귀 없음

LP-1~8·10·14·15 기존 파셜 9종 불변(03 문서 §1)·hero 헤드라인/CTA 불변(diff 확인)·`ol li` 5개 단정 유지(신규 섹션 전부 ul/div)·`h1` 1개·LP-9 후기 미표기 유지. REM-15는 PRD에 존재하지 않음 확인(REM-13이 최종) — VIEW-7 근거 전환 판정(03 문서 §4-1) 올바름.

## 참고 사항 (반영 선택 · 이슈 카운트 제외)

- `_sales_program.html.erb:11` 헤드라인 "지인에게 **계정을 주고**" — 실제로 주는 것은 추천 코드. 의미 전달은 되나 "추천 코드를 주고"가 정확. 카피 개선 여지.
- `_workspace/02_prd_update.md`는 "v0.44 → v0.45"라 기술했으나 PRD 헤더는 v0.44(정책 문서 배치 설명) — 병렬 배치의 PRD 버전 라벨 정리는 오케스트레이터 몫. LP-16 본문은 PRD에 정상 반영 확인.

## Tester에게 제안하는 중점 테스트 영역

### A. 기존 테스트 갱신 3건 (03 문서 §6 — 리뷰 재현으로 실패 원인 확정. 반드시 갱신 후 진행)

1. `test_표면_①의_a_요소는_가입_CTA와_헤더_로그인만_②에_진입한다...`(:40) — 허용 href 집합에 **인페이지 앵커(href "#…" 접두 — ② 진입 아님) 추가**. 리뷰 판정: 앵커는 SURF-4 위반이 아니므로 갱신이 정당.
2. `test_주_CTA는_히어로·LP-10_최종에서_가입_화면_실링크다...`(:33) — `count: 2` → **`count: 4`**(hero·all_features·sales_program·closing). 텍스트 단정 `/무료로 시작하기/` 동일 갱신(3개 CTA가 "무료로 시작하기", all_features는 "이 모든 기능, 무료로 시작하기" — 부분 매치 확인).
3. `test_LP-8_FAQ_8항목의_질문이_모두_노출된다...`(:189) — summary `count: 8` → **`count: 12`** + 신규 4질문(전자세금계산서·정기 청구·추천 코드·휴대폰 인증) 문구 단정 추가.

### B. 신규 단정 권장 (10건 내외)

1. **섹션 순서**: all_features가 features 다음·scenarios 이전, sales_program이 control 다음·positioning 이전에 렌더(`assert_match` 순서 비교).
2. **카드 수**: `#all-features ul li` 12개 — LP-16 전 기능 커버 그리드.
3. **배지**: '예정' 배지 정확히 1개(데이터 내보내기 카드)·'신규' 배지 2개(반복 청구·전자세금계산서).
4. **앵커 착지 유효**: `a[href="#all-features"]` 존재 + `section#all-features` 존재(끊어진 앵커 아님).
5. **SALES 수치 문구**: "7,920원"·"20%"·"15%"·"3.3%" 렌더 — SALES-1/4/5 확정치 스냅샷(수치 변경 시 테스트가 알림).
6. **sales_program 링크 무결**: 섹션 내 a 요소는 가입 CTA 1개뿐(외부·mailto href 0).
7. **hero 배지**: "첫 14일 무료 체험"·"청구 건당 최대 5통"·"4단계 정중한 안내" 3종 렌더.
8. **h1 1개 유지**·신규 섹션은 h2 2개 추가 — 문서 구조 회귀 방지.
9. **FAQ 신규 4질문 요약문구 포함**(summary 텍스트 부분 매치).
10. **금지 표현 부재**: 기존 LP-12 단정이 전체 페이지 대상이므로 신규 카드 자동 커버 — 유지 확인만.

### C. 시스템 테스트(선택)

모바일 뷰포트에서 13섹션 스크롤 시 인접 섹션 배경 구분·all_features 12카드 sm:1→sm:2→lg:3열 반응형·배지 줄바꿈 확인.

## Rule ID 준수 매핑 (요약)

| Rule | 구현 위치 | 판정 |
|---|---|---|
| LP-16 | all_features 12카드·sales_program·FAQ+4·CTA 4곳 | 준수(W-1 헤드라인 긴장) |
| LP-12 | 금지 표현 0·수치는 PRD 확정치만 | 준수(W-2 조건부) |
| SURF-4 | 가입 CTA 4(허용)·앵커 1(② 진입 아님) | 준수 |
| SURF-6 | DB 쿼리 0·정적 마크업 | 준수 |
| DESIGN-8 | 배경 리듬 13섹션·hover·focus 링 | 준수 |
| DESIGN-6 | aria-hidden·텍스트 대비·CTA 타깃 | 준수 |
| SALES-1/2/4/5 | sales_program 수치·스텝 | 준수 |
| INV-7·TAX-1/2·LEGAL-2·PLAN-4·PAY-2·VIEW-7·NOTI-2·SEC-4 | 12카드 매핑(§1 표) | 준수 |
| AUTH-9 | FAQ 휴대폰 인증 | 준수 |
| 기존 LP-1~15 | 파셜 9종 불변·기존 단정 유지 | 회귀 없음 |

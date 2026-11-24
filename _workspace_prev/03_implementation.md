# 03_implementation — 랜딩 전면 재구성 (2026-11-20 · 일반 모드 · Standard)

구현 지시(오케스트레이터) 기준 수행 결과. 근거: `_workspace/01_plan.md` · PRD LP-16(신설)·LP-1~15·DESIGN-8·LP-12.

## 1. 변경 파일 전수

| 파일 | 구분 | 변경 요약 |
|---|---|---|
| `app/views/landing/_all_features.html.erb` | **신규** | LP-16 전 기능 커버 섹션 — 12카드 그리드(sm:2/lg:3)·아이콘+혜택 체크리스트·신규/예정 배지·섹션 끝 가입 CTA |
| `app/views/landing/_sales_program.html.erb` | **신규** | LP-16 영업 추천 프로그램 섹션 — 3스텝 카드·정산 조건 스트립·참여 문의(텍스트)·가입 CTA |
| `app/views/landing/index.html.erb` | 수정 | 섹션 순서 재구성(13섹션)·신규 파셜 2종 편성·헤더 주석 갱신(LP-16·CTA 4곳·배경 리듬 명시) |
| `app/views/landing/_features.html.erb` | 수정 | 말미에 "더 많은 기능 보기" 인페이지 앵커 링크(`#all-features`) 추가 — 3카드·PRD 이점 문구 원문 불변 |
| `app/views/landing/_faq.html.erb` | 수정 | 항목 4개 추가(전자세금계산서·반복 청구·추천 코드·휴대폰 인증) — 8→12. 기존 8항목 원문 불변 |
| `app/views/landing/_hero.html.erb` | 수정 | CTA 하단 수치 배지 스트립 3종 추가(첫 14일 무료 체험·청구 건당 최대 5통·4단계 정중한 안내) — 헤드라인·CTA·보조 버튼·목업 불변 |

**변경하지 않은 파일(판정 포함)**
- `app/views/layouts/landing.html.erb` — 01_plan이 "헤더" 수정 후보로 올렸으나, 헤더는 블로그 링크·로그인 직행을 이미 갖춰 LP-11·SURF-4 충족 → 불변 판정.
- `app/helpers/landing_helper.rb` — **존재하지 않음**(지시서의 아이콘 경로 헬퍼는 실제로 `application_helper.rb#step_icon_path`). 신규 섹션 아이콘은 파셜 로컬 데이터 배열(`features[:icon]`)로 처리해 **Ruby 파일 변경 0건** — fan-out 제약(뷰 3종만) 준수.
- 기존 9개 파셜(pain·how_it_works·scenarios·message_samples·message_bubble·control·positioning·pricing·closing) — 불변.

## 2. 신규 섹션 목차 (페이지 순서 — DESIGN-8 배경 리듬)

| # | 섹션 | 배경 | 상태 |
|---|---|---|---|
| 1 | hero | cream 그라데이션 | 수치 배지 스트립 추가 |
| 2 | pain | white | 불변 |
| 3 | how_it_works | cream | 불변 |
| 4 | features | white | 앵커 링크 추가 |
| 5 | **all_features** (`#all-features`) | cream | **신규** |
| 6 | scenarios | ivory(#f4f2ea) | 불변 |
| 7 | message_samples | cream | 불변 |
| 8 | control | white | 불변 |
| 9 | **sales_program** | ivory(#f4f2ea) | **신규** |
| 10 | positioning | cream | 불변 |
| 11 | pricing | white | 불변 |
| 12 | faq | cream | 항목 +4 |
| 13 | closing | white | 불변 |

인접 섹션 동일 배경 없음(cream→white→cream→ivory 교차). 지시서 순서(hero → pain → how_it_works → features → all_features → scenarios → message_samples → control → sales_program → positioning → pricing → faq → closing)와 일치.

**_all_features 12카드**: ①열람 추적 ②자동 리마인더 4단계 ③입금 약속 수집 ④수금 마감 원클릭 ⑤반복 청구(신규) ⑥전자세금계산서(신규) ⑦내용증명 양식 ⑧수금 패스 ⑨부분입금 잔액 관리 ⑩수신거부·안전장치 ⑪주간 수금 다이제스트 ⑫데이터 내보내기(예정)

**_sales_program 구성**: 히어로 문구("지인에게 계정을 주고, 첫 달 20% 할인으로 시작하게 하세요") → 3스텝(코드 주간 갱신 / 첫결제 20% 할인·첫 달 7,920원 / 수수료 20%·12개월 vs 15%·무기한) → 정산 방식 스트립(월 정산·원천징수 3.3%) → 참여 문의(텍스트) + 가입 CTA 패널.

## 3. LP-16 매핑

| LP-16 요구 | 구현 |
|---|---|
| features 3카드 외 전 기능 별도 섹션 노출 | `_all_features` — 아래 Rule ID 매핑 참조 |
| 영업 추천 프로그램 별도 섹션 | `_sales_program` — SALES-1/2/4/5 |
| FAQ 확대 | `_faq` +4(전자세금계산서 TAX-1/2·반복 청구 INV-7·추천 코드 SALES-4·휴대폰 인증 AUTH-9) |
| CTA 반복 배치 | 가입 CTA 4곳 — hero·all_features 끝·sales_program 끝·closing(uibowl 관찰 #3) |

**all_features 카드별 근거 Rule ID**: SHARE-3/4 · REM-2·REM-12·PLAN-3(5통) · PROMISE · PAY-1·PAY-4 · INV-7(1~28일) · TAX-1/2·Q21(건당 300원) · LEGAL-2·PLAN-7(건당 5,000원) · PLAN-4(10건 4,000원·90일) · PAY-2 · VIEW-7 · NOTI-2(직전 7일·월요일) · SEC-4(예정).

**uibowl 관찰 4원칙**: ① 아이콘+혜택 체크리스트(all_features 체크 문장) ② 스텝 가로 스크롤(how_it_works 기존 5열 그리드 유지 — 신규 섹션은 그리드로 잘림 없음) ③ CTA 반복(신규 2섹션 끝 추가 → 총 4) ④ 숫자 배지(히어로 3종·카드 신규/예정·7,920원·20%·15%).

## 4. 판정·주의 사항 (Reviewer 집중 검토 대상)

1. **REM-15 미존재** — 지시서의 "수신거부·안전장치(VIEW-7·REM-15)"에서 REM-15는 PRD에 없음(REM-13이 최종 번호, 01_plan의 "control(REM-15 안전장치)" 표기와 함께 오표기 추정). 카드는 **VIEW-7** 근거로 구현하고 안전장치 문구는 REM-11·REM-12/PLAN-3의 사실 서술로 대체. PRD Rule ID 신설은 fan-out 제약 밖이므로 오케스트레이터 판단 대상.
2. **sales_program 참여 CTA를 텍스트로 구현** — 지시서 "관리자 문의(텍스트 링크)"를 SURF-4 하드 제약(② 진입 링크는 가입·로그인·블로그·법적 고지만 — 지시서 하드 제약 항)과 결합해 **앵커 없는 텍스트 안내**(카카오톡 채널 '받을돈' — 푸터 문의 채널과 동일 패턴)로 구현. 근거: `/sales`는 영업 직원 전용 로그인 표면(SALES-6·noindex)이라 공개 참여 경로가 없고, mailto 등 타 href는 SURF-4 위반·테스트 전면 파탄.
3. **"알림톡 19종" 배지 미채택** — 지시서 예시 수치. PRD NOTI-1은 "18종 승인·운영 반영 + 초안(B-4~B-8)"이며 종수 산정이 모호해 LP-12(측정 근거 수반) 위험. 검증 가능 수치 3종(첫 14일 무료 체험 PLAN-2·청구 건당 최대 5통 PLAN-3·4단계 REM-2)으로 대체.
4. **배지 '신규'·'예정' 판정** — 반복 청구(2026-11-11)·전자세금계산서(2026-11-16)는 구현 완료 → '신규'. SEC-4 데이터 내보내기는 미구현(app 전역 CSV 내보내기 부재 확인) → 유일한 '예정' 배지 + "준비 중인 기능입니다" 명시.
5. **NOTI-2 서술 수위** — 다이제스트 알림톡 템플릿(B-7)은 등록 전 초안 상태이나 Job·토글은 구현됨(NOTI-2 확정 2026-11-16). 카드는 기능 총괄 서술로 처리(기존 랜딩의 기능 서술 관례와 동일).
6. **LP-12·SURF-6·뷰 컨벤션** — 신규 섹션 DB 쿼리·모델 호출 0, `raw`/`html_safe` 0, 이미지 파일 추가 0(인라인 SVG만), 금지 표현(100%·보장·마지막 알림·긍정 문맥 '추심'·발행 후 14일) 미사용 — 테스트 실행으로 검증 통과.
7. **인페이지 앵커 1건 허용 판단** — `#all-features` 앵커는 지시서가 명시한 요구(“더 많은 기능 보기” 앵커 링크)이며 ② 진입이 아니지만, 기존 SURF-4 테스트가 전 a 요소 href 화이트리스트를 검사해 1건 실패(§6 참조). Phase 7 갱신 대상.

## 5. 자가 검증 결과

- `bin/rails test test/controllers/landing_controller_test.rb` — **31 runs, 307 assertions, 3 failures, 0 errors**. 실패 3건은 전부 §6 목록(예측된 갱신 대상)과 일치. 신규 파셜 2종 포함 전체 렌더 에러 없음(0 errors).
- `bin/rubocop` — 412 files inspected, **no offenses**.
- ERB 기존 섹션 마커·문구 불변 확인 — 기존 통과 단정 28건 중 LP-1/2/3/4/5/6/7/10/14/15 관련 전부 통과(섹션 순서 변경·신규 섹션 삽입이 기존 문구 단정에 영향 없음).
- Ruby 파일 변경 0건 → `zeitwerk:check`·`db:migrate` 불요.

## 6. Phase 7 인계 — 기존 테스트 갱신 필요 단정 목록 (수정 금지 준수·미수정)

파일: `test/controllers/landing_controller_test.rb` — **3건**. 신규 섹션·문구에 대한 신규 단정 추가도 이번 Phase에서 함께 권장.

1. **`test_표면_①의_a_요소는_가입_CTA와_헤더_로그인만_②에_진입한다_(SURF-4_개정_—_법적_고지_링크_제외)`** (:40, 실패 지점 :47)
   - 원인: features 말미 인페이지 앵커 `href="#all-features"`가 허용 href 집합(가입·로그인·법적 고지 3종·블로그·root)에 없음.
   - 권장 갱신: 허용 조건에 **인페이지 앵커(`#` 접두 href — ② 진입 아님)** 추가. `assert_select "a[href=?]", new_password_path, count: 0` 등 나머지 단정은 유지 가능.
2. **`test_주_CTA는_히어로·LP-10_최종에서_가입_화면_실링크다_(SURF-4,_AUTH-1_반전)`** (:33, 실패 지점 :36)
   - 원인: 가입 CTA 실링크 2 → **4**(all_features 끝 "이 모든 기능, 무료로 시작하기"·sales_program 끝 "무료로 시작하기" 추가 — LP-16 "CTA 반복 배치" 반영).
   - 권장 갱신: `count: 2` → `count: 4` + 위치 주석 갱신. 문구 단정(`text: /무료로 시작하기/`)은 동일 count 갱신 필요.
3. **`test_LP-8_FAQ_8항목의_질문이_모두_노출된다_(LP-8)`** (:189, 실패 지점 :191)
   - 원인: `summary` 8 → **12**(LP-16 확장 4항목 — 전자세금계산서·반복 청구·추천 코드·휴대폰 인증).
   - 권장 갱신: `count: 8` → `count: 12` + 신규 4질문 문구 단정 추가.

**깨지지 않아 확인된 인접 단정**(갱신 불요): `figure blockquote` 3·`ol li` 5(신규 섹션 전부 ul·div 사용 — _control 선례)·`div[class*='FEE500']` 4(신규 버블 없음)·`h1` 1(신규 섹션은 h2/h3만)·LP-12 금지 표현·`button[disabled] 작동 방식 보기` 1.

## 7. 후속(Phase 3 오케스트레이터) 참고

- uibowl 관찰 검증용 렌더 스크린샷 시 앵커 동선: features "더 많은 기능 보기" → `#all-features`.
- PRD 반영(02_prd_update.md)과 별도로 **REM-15 미존재**·**SEC-4 미구현('예정' 배지)** 2건은 문서 정합성 관점에서 오케스트레이터 확인 권장.

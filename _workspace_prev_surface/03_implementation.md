# 03_implementation

## 3a 랜딩

### 변경 파일

| 파일 | 변경 |
|:---|:---|
| `app/views/landing/index.html.erb` | 섹션 렌더 순서 갱신(scenarios·control 신규 삽입) + DESIGN-8 배경 리듬 주석 |
| `app/views/landing/_hero.html.erb` | 히어로 좌우 비대칭 분할 재구성 + 청구서 뷰어 정적 목업(우측) |
| `app/views/landing/_message_samples.html.erb` | 버블 파셜 추출 + 스텝 페이저(시퀀스 타임라인·단계 n/4 인디케이터) 추가 |
| `app/views/landing/_message_bubble.html.erb` | 신규 — LP-5 카톡 버블 마크업 파셜화(markup 동일 유지) |
| `app/views/landing/_scenarios.html.erb` | 신규 — LP-14 "모든 상황, 자동으로" 시나리오 카드 4종(2×2) + 미니 메시지 목업 |
| `app/views/landing/_control.html.erb` | 신규 — LP-15 "자동이되, 통제는 사용자" 3항목 카드 |
| `app/views/landing/_pain.html.erb` | 카드 hover 디테일 추가(DESIGN-6) |
| `app/views/landing/_positioning.html.erb` | 섹션 배경 cream 전환, 내부 카드 white + hover |
| `app/views/landing/_pricing.html.erb` | 섹션 배경 white 전환(배경 리듬) |
| `app/views/landing/_faq.html.erb` | 섹션 배경 cream 전환(배경 리듬) |

기능·라우트·컨트롤러·모델 변경 없음. 새 데이터 조회 없음(전부 정적 마크업).

### Rule ID 매핑

- **LP-14** — `_scenarios.html.erb`: 약속 재조정(PROMISE-3)·열람 분기(REM-4·SHARE-5)·부분입금(PAY-2)·입금 회신 정지(PROMISE-7) 4카드, benefit 문장 + 상황별 미니 버블 목업. 미니 목업은 실제 알림톡 버블(#FEE500)과 구분되는 중립 스타일 + "상황 미리보기" 라벨(LP-5 실발신 문구와 혼동 방지, 테스트의 FEE500 버블=4개 불변).
- **LP-15** — `_control.html.erb`: 발송 당일 아침 사전 알림·원클릭 마감/보류(REM-11), 건당 5통·14일 자동 종료(REM-12·PLAN-3), 발송 기록 보존(P4). 배지·인라인 SVG 아이콘.
- **LP-1** — `_hero.html.erb`: Q6 헤드라인·서브카피·주/보조 CTA 문구·링크 불변. 레이아웃만 lg:grid-cols-12 비대칭 분할(좌 6 / 우 6 col-start-7), 모바일 세로 스택. 우측 뷰어 목업은 a·button 요소 미사용(span 스타일링), SURF-4 ①→② 진입 링크 불변.
- **LP-5** — `_message_samples.html.erb` + `_message_bubble.html.erb`: 4단계 버블 문구 원문 불변, 시퀀스 타임라인 페이저 + 카드당 "단계 n/4" 인디케이터(순수 CSS, JS/Stimulus 미사용).
- **DESIGN-8** — 섹션 배경 리듬(hero gradient → pain white → how cream → features white → scenarios #f4f2ea → samples cream → control white → positioning cream → pricing white → faq cream → closing white), 카드 hover 섀도 승격(sm→md, 200ms), 라운드 2xl 유지, 토큰 내 색상(stone·emerald·cream·#f4f2ea)만 사용.
- **SURF-4/6** — 신규 섹션·목업에 앵커·버튼 인터랙션 없음, 쿼리 없음, 랜딩 앵커 집합 불변(가입 2 + 로그인 1 + 법적 고지 3).
- **LP-12/P5** — 신규 문구 전체 과장·수치 인용(5통 등 규칙 사실 제외)·공포 조장 없음, "100% 보장"·"마지막 알림" 등 금지 표현 미사용(테스트 회귀 통과).

### 새로 추가한 문구 전문 (Reviewer LP-12 검증용)

**LP-14 섹션**
- 섹션 리드: "일정이 어긋나거나, 일부만 받거나, 상황이 달라져도 — 시퀀스는 그에 맞춰 조용히 이어갑니다."
- ① 약속 재조정: "거래처가 '이번 주까지'라고 답하면, 리마인더 일정이 그 약속에 맞춰 다시 짜입니다." / "등록된 약속일 하루 전에 안내하고, 약속이 지나가면 다음 날 한 번 다시 여웁니다." / 목업: "약속해주신 입금 예정일이 내일입니다. 오늘까지 확인 부탁드립니다."
- ② 열람 분기: "열어본 거래처와 아직 못 본 거래처, 받는 안내가 다릅니다." / "아직 못 연 거래처에게는 확인 요청이, 이미 열어본 거래처에게는 입금 안내가 갑니다." / 목업: "'오즈디자인'의 입금이 아직 확인되지 않았습니다. — 확인하신 내역 기준으로 안내드립니다"
- ③ 부분입금: "일부만 받았어도, 잔액 기준으로 조용히 이어갑니다." / "받은 금액은 기록에 반영되고, 남은 잔액 기준으로만 안내가 이어집니다." / 목업: "일부 입금이 확인되었습니다. 남은 잔액 기준으로 안내드리겠습니다."
- ④ 입금 회신: "거래처가 '이미 입금했어요'를 누르면 발송이 즉시 멈춥니다. 마감은 당신의 확인으로만." / "회신은 발행인에게 전달되고, 수금 완료 처리는 발행인의 확인으로 이뤄집니다." / 목업: "'이미 입금했어요' 응답을 받았습니다. 자동 발송을 멈추고 발행인님께 전달드립니다."
- 목업 라벨: "상황 미리보기 · {약속일 하루 전|열어본 거래처에게|부분입금 확인 후|입금 회신 직후}"

**LP-15 섹션**
- 섹션 리드: "자동 발송이라고 던져 두는 게 아닙니다. 보내기 전에 알고, 정해진 만큼만 보내고, 다 기록으로 남깁니다."
- ① "발송 당일 아침, 미리 알려드립니다" — "자동 발송이 예정된 날에는 당일 아침에 알려드립니다. 원클릭으로 그날 발송을 마감하거나 보류할 수 있습니다." (배지: 사전 알림)
- ② "청구 건당 최대 5통, 14일 후 자동 종료" — "시퀀스는 청구 건당 최대 5통(대체 SMS 포함)으로 제한되고, 발행 후 14일이 지나면 자동으로 종료됩니다. 그 이상은 발송되지 않습니다." (배지: 발송 상한)
- ③ "모든 발송은 기록으로 남고 지워지지 않습니다" — "보낸 모든 안내는 발송 이력으로 남습니다. 언제 무엇을 보냈는지 대시보드에서 그대로 확인할 수 있습니다." (배지: 기록 보존)

**히어로 뷰어 목업(표시 전용)**: "받을돈을 통해 오세안님이 보낸 청구서입니다" / 청구번호 INV-2026-0042 · 만기일 2026-11-05 / 품목 2행(1,500,000원·500,000원) / 청구 총액 2,200,000원 / 응답 버튼(표시 전용): "이미 입금했어요"·"입금 예정일 알리기" / 고지문: VIEW-5 원문 / 떠있는 배지: "열람을 확인했어요"

### 검증 결과

- `bin/rubocop -a` — 136 files, no offenses
- `bin/rails zeitwerk:check` — 통과
- `bin/rails test test/controllers/landing_controller_test.rb` — 21 runs, 271 assertions, 0 failures (기존 assertion 무수정 통과)

## 3b /app 대시보드

### 변경 파일

| 파일 | 변경 |
|:---|:---|
| `app/views/app/dashboards/show.html.erb` | DASH-1 히어로 카드 위계(미수 총액 sm:col-span-2·text-5xl·emerald 액센트 링, 보조 2종 text-3xl), DASH-2 카드형 리스트(아이콘 타일·상태 뱃지·우측 액션 버튼), 빈 상태 일러스트 아이콘, DESIGN-8 focus 링·150ms 트랜지션 |
| `app/helpers/app/base_helper.rb` | `app_nav_link_classes` 활성 상태 딥 그린 인디케이터 바(before: 의사요소)·focus-visible 링 추가, `dash_action_badge(kind)`·`dash_action_icon_path(kind)` 신설(DASH-2 뱃지·아이콘 — 뷰 표현 로직 헬퍼화) |
| `app/views/layouts/app.html.erb` | 헤더 프로필 칩(첫 글자 아바타+표시명), 로그아웃·해시버거 focus-visible 링·duration-150, 사이드바 nav 여백 리듬(px-3 py-4) |
| `app/views/app/invoices/_invoice.html.erb` | 행 hover 디테일(stone-50/80·duration-150), 청구번호 링크 focus-visible 링 |

컨트롤러·모델·라우트·쿼리 변경 없음. 새 데이터 조회 없음. DASH-4 정렬·스코프 불변. 레이아웃 meta(noindex) 미접촉.

### Rule ID 매핑

- **DASH-1** — 요약 3종 위계: 미수 총액 히어로 카드(최상위·큰 tabular numerals), 연체·7일 내 만기는 보조 카드. 빈 상태 문구·`—` 슬롯·0원 미표기 규칙 유지.
- **DASH-2** — 카드형 리스트: 유형별 아이콘(마감 체크 녹색 타일·문의 대화 주황 타일) + DESIGN-2 상태 뱃지(마감 대기 green/답변 대기 orange) + 우측 액션 버튼(sm:flex-row). 문구·링크 불변.
- **DASH-4** — 정렬(연체일 내림차순)·상위 5건 불변, 행 hover·연체일 주황 강조·링크 focus 링만 개선.
- **DESIGN-2** — 상태색 3종(연체 주황/대기 중립/완료 녹색)만 사용, 신규 색상 없음.
- **DESIGN-3** — tabular-nums 유지·히어로 수치 타이포 확대(sm:text-5xl).
- **DESIGN-5** — 액션 유형 시각화(아이콘 타일·뱃지), 목록 상태 뱃지 체계 유지.
- **DESIGN-8** — hover 섀도 승격(sm→md)·focus-visible 딥 그린 링·150~200ms 트랜지션 — 3a 랜딩과 동일 문법.
- **SURF-3** — 레이아웃 head/meta 미접촉.

### 3a와의 일관성 결정

- 트랜지션 duration-150, focus-visible outline-emerald-700, 카드 rounded-2xl·섀도 sm→md hover 승격 — 3a 랜딩 카드 문법 그대로.
- 표면②는 DESIGN-4(정보 밀도·장식 최소)에 따라 배경 톤 변주 없이(cream 유지) 카드·뱃지·타이포 위계로만 승격. 아이콘은 랜딩 LP-3(step_icon_path)과 같은 인라인 SVG stroke 문법 재사용.

### 검증 결과

- `bin/rubocop -a` — 136 files, no offenses
- `bin/rails zeitwerk:check` — 통과
- `bin/rails test test/controllers/app/` — 164 runs, 1155 assertions, 0 failures (기존 assertion 무수정 통과 — 요약 카드 수치·액션 문구·링크 경로·nav aria 구조 불변)

## 3c 뷰어

### 변경 파일

| 파일 | 변경 |
|:---|:---|
| `app/views/viewer/show.html.erb` | 전부 class 수준 조정 — 헤더 VIEW-2 표기 위계(워드마크 축소·하단 구분선), 메타 dl 라벨 위계·행 리듬, 품목 표 thead 상하 보더·행 라벨 톤 정돈, 청구 총액 강조(text-3xl/4xl·이중 보더 border-t-2), 원천징수 하위 블록 구분선, 입금 계좌 카드 복사 배지 강조·계좌번호 확대·hover 디테일(duration-150·shadow-md), PAY-3 입금자명 강조, 응답 버튼 4종 min-h-12(48px·DESIGN-6 터치 타깃)·주/보조 위계·active·hover·focus-visible 디테일, 폼 입력 py-3, 섹션 간격 리듬(mt-4→mt-5 체계화), 고지문 가독성(text-[13px] leading-loose) |

`app/views/viewer/expired.html.erb`·`promise_thanks.html.erb`·`layouts/viewer.html.erb`·Stimulus(clipboard)·컨트롤러·라우트·모델 미접촉. 기본 글자 크기는 레이아웃의 17px(DESIGN-6)를 현행 유지 확인.

### Rule ID 매핑

- **VIEW-2** — 헤더: 워드마크 text-base→text-sm(위계: 문장이 주인공), mt-8→mt-5, 하단 구분선. 문구 원문 불변(h1 exact 텍스트 유지 — 컨트롤러 테스트 assert_select 통과).
- **VIEW-3·DESIGN-3** — 청구번호·발행일·만기일 메타 라벨 위계(xs·semibold·tracking-wide), 품목 표 thead border-y·숫자 우측 tabular-nums, 청구 총액 text-3xl→sm:text-4xl + border-t-2 border-stone-900 이중 규칙선(문서적 강조 — 색 추가 없음), 원천징수·입금하실 금액 하위 구분선 정렬.
- **VIEW-3·PAY-3** — 계좌 카드: 계좌번호 text-2xl/sm:text-[1.7rem] 확대, "탭하여 복사" 배지화(emerald-800/10 배경 — 현행 토큰 내 톤), hover:border-emerald-700/40·shadow-md·duration-150. Stimulus 로직·data-target·fallback 동작 불변("복사됨"/"선택됨" 피드백 유지). 입금자명 strong을 extrabold·stone-900으로 위계만 강화.
- **PROMISE-1·DESIGN-6** — 응답 버튼 4종 min-h-11→min-h-12(48px), 주 액션(에메랄드 fill·text-[15px]·hover/active 섀도 위계) vs 보조 액션(보더·hover 배경 톤) 구분, focus-visible 링 유지. 라벨·개수·button_to/form 구조 불변.
- **VIEW-5** — 고지문 문구 원문 불변, text-xs→text-[13px]·leading-loose 가독성만 개선.
- **DESIGN-4** — 흰 배경·색 최소 유지: 신규 색상 0(emerald/stone 기존 토큰 내), 배경색 변경 없음, 장식 없음 — 보더·타이포·여백만.
- **DESIGN-8** — 3a·3b와 동일 문법(duration-150, focus-visible outline, hover shadow 승격 sm→md)을 문서 톤으로 축소 적용.
- **SURF-3/4·VIEW-8** — head/meta·레이아웃 미접촉, 앵커 추가 없음(시스템 테스트 `assert_empty page.all("a")` 통과).

### VIEW-8 화이트리스트 준수 확인

- **추가한 요소 없음** — 모든 변경이 기존 요소의 class 문자열 수정이며, 새 요소·새 텍스트·새 링크·새 인터랙션 0건. 내비·마케팅·가입 유도·랜딩 링크 없음(기존과 동일).
- 문구 변경 0건 — 라벨·고지문·안내 문구 전부 원문 유지.
- 컨트롤러·라우트·모델·인증 변경 0건, 클립보드 Stimulus JS 미접촉.

### 검증 결과

- `bin/rubocop -a` — 136 files, no offenses
- `bin/rails zeitwerk:check` — 통과
- `bin/rails test test/system/viewer_test.rb test/system/viewer_promise_test.rb test/controllers/viewer_controller_test.rb test/controllers/viewer_promises_test.rb test/controllers/viewer_promises_rate_limit_test.rb` — 44 runs, 328 assertions, 0 failures (기존 assertion 무수정 통과 — h1/dd/td/p 텍스트·section[aria-label]·앵커 0개·클립보드 피드백 불변)

## 6 리뷰 반영 수정

`_workspace/05_review.md` 이슈 6건 전체 반영 완료 (2026-11-02). 지적 파일·라인만 최소 수정.

| # | 심각도 | 요약 | 반영 내용 |
|---|--------|------|-----------|
| 1 | CRITICAL | 자동 종료 기준일 "발행 후 14일" 오기재(REM-12·PLAN-3은 만기 D+14) | `_control.html.erb` — 제목 "청구 건당 최대 5통, 만기일로부터 14일 후 자동 종료", 본문 "만기일로부터 14일 뒤인 최종 안내까지 발송된 뒤 자동으로 종료됩니다"로 교정. 기존 랜딩 테스트에 해당 문자열 assertion 없음 확인 후 수정 |
| 2 | WARNING (확인 요청) | 사전 통보 범위가 모든 자동 발송일로 읽힘(REM-11은 연체 단계 한정) | **반영** — "연체 단계의 자동 발송이 예정된 날에는"으로 한정. 근거: PRD REM-11 원문이 "D+1·D+7·D+14 각 연체 단계"로 명백히 한정하며, LP-15의 포괄 문언은 규칙 원문이 우선한다고 판단. LP-12 과대 약속 소지 해소 |
| 3 | WARNING (확인 요청) | 발송 이력 대시보드 열람 무조건부 문장(PLAN-2는 Plus 기능으로 명시) | **반영(보수안)** — "보낸 모든 안내는 발송 이력으로 남고, 언제 무엇을 보냈는지 지워지지 않고 기록됩니다"로 변경해 기록 보존(P4·REM-6) 사실만 서술. 근거: PLAN-2가 발송 이력을 Plus 기능으로 명시하므로 플랜 게이트 미확정 상태에서 열람 보장 문장 제거가 안전. P4 기록 보존은 전 플랜 사실 |
| 4 | WARNING | 히어로 목업 버튼 "입금 예정일 알리기" → 실제 라벨(PROMISE-1)은 "입금 예정일 지정" | `_hero.html.erb:100` 라벨 텍스트만 수정(마크업 구조 불변) |
| 5 | WARNING | 목업 청구번호 "INV-2026-0042" → 실제 채번 형식은 BD-YYYYMMDD-NNN(INV-1) | `_hero.html.erb:64`를 "BD-20261105-001"로 수정(만기일 2026-11-05와 정합) |
| 6 | WARNING | 푸터 법적 고지 링크 터치 타깃 44px 미달(DESIGN-6) | `layouts/landing.html.erb:46-48` — 링크 3종에 `inline-flex min-h-11 items-center` 추가 |

### 검증 결과

- `bin/rubocop -a` — 136 files, no offenses
- `bin/rails zeitwerk:check` — 통과
- `bin/rails test test/controllers/landing_controller_test.rb` — 21 runs, 271 assertions, 0 failures

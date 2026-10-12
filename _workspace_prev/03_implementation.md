# 03_implementation.md — Phase 3 구현 보고: UI 품질 기준 적용(디자인 시스템 + 랜딩 전체 LP-1~8·10) + AUTH-1.3 프로필 설정

- **일자**: 2026-10-12
- **범위**: `_workspace/01_plan.md` 개정 v2 B절 전체 (B-1 디자인 시스템 / B-2 랜딩 전체 / B-3 AUTH-1.3)
- **기준**: PRD v0.18.1 §7.1(LP-1~10)·§7.3(DESIGN-1~7)·§6.1(AUTH-1.3), AGENTS.md 「UI 품질 기준」

## 1. 변경 파일 목록

### 신규 생성 (14)

| 파일 | 요약 |
|:---|:---|
| `db/migrate/20261012000001_add_profile_fields_to_users.rb` | `users`에 `display_name`·`business_type`(integer)·`bank_name`·`account_number`·`account_holder`·`phone` 추가 — 전 컬럼 null 허용(미설정=프로필 미완료 판정 근거) (AUTH-1.3) |
| `app/controllers/app/profiles_controller.rb` | `/app/profile` edit+update. `require_authentication` 첫 실전 적용(기본 가드 상속), `params.expect`, 성공 303/실패 422, `save(context: :profile)` |
| `app/helpers/app/profiles_helper.rb` | 국내 은행 20개 select 목록 + 필드별 오류 상태 입력 클래스(라벨·힌트·오류 완성도) |
| `app/views/app/profiles/edit.html.erb` | 프로필 설정 화면 — 「내 정보」(표시명·사업자 유형 라디오카드·연락처)/「입금 계좌」(은행·계좌번호·예금주) 섹션 구분, 프리랜서 카드에 「원천징수 3.3% 표기 적용」 안내 |
| `app/javascript/controllers/account_number_controller.js` | 계좌번호 자동 하이픈(4자리 그룹) — Stimulus 1개, UI 보조만(도메인 로직 없음) |
| `app/views/landing/_hero.html.erb` | LP-1 히어로 — 확정 문구·CTA 링크 불변, 디자인 고도화(배지·타이포 위계·크림→화이트 그라데이션·CTA 디테일) |
| `app/views/landing/_pain.html.erb` | LP-2 페인 공감 — PRD 지정 인용 3종 **원문** 카드 |
| `app/views/landing/_how_it_works.html.erb` | LP-3 작동 방식 — 5단계 스텝(번호 배지·인라인 SVG 아이콘·연결선), 이미지 파일 없이 순수 마크업+CSS |
| `app/views/landing/_features.html.erb` | LP-4 핵심 기능 3종 — PRD 지정 benefit-first 이점 문장 **원문** |
| `app/views/landing/_message_samples.html.erb` | LP-5 발신 문구 공개 — D-1/D+1/D+7/D+14 4단계 카카오톡 버블형 카드(문구 신규 작성, §3.2 참조) |
| `app/views/landing/_positioning.html.erb` | LP-6 포지셔닝 — 「추심 서비스가 아닙니다」 4요소 + VIEW-5 고지문 **원문** 인용 블록 |
| `app/views/landing/_pricing.html.erb` | LP-7 요금제 — Free/Plus/수금 패스 3카드, Plus 강조(링·배지), 건당 5통 표기, 「부가세 포함」 명시(결정 #4) |
| `app/views/landing/_faq.html.erb` | LP-8 FAQ — PRD 지정 8항목 details/summary 아코디언(JS 없이, 문구 신규 작성) |
| `app/views/landing/_closing.html.erb` | LP-10 최종 CTA(히어로 메시지 반복+동일 링크 CTA 1회) + 푸터(서비스 소개·문의 채널·© — 약관 링크 미포함, 결정 #5) |

### 수정 (16)

| 파일 | 변경 |
|:---|:---|
| `app/assets/tailwind/application.css` | Tailwind v4 `@theme` 토큰 — `--font-sans` Pretendard 스택(시스템 스택 제거, DESIGN-3), `--color-cream: #faf9f5`(DESIGN-2), body base(크림 배경·antialiased) |
| `app/views/layouts/application.html.erb` | Pretendard CDN `<link>`(jsdelivr v1.3.9 variable), `lang="ko"`, 메타 description(content_for 지원), 조건부 noindex 메타(SURF-3), 상단 심플 헤더 바(좌측 워드마크 span·우측 로그인 링크 = **비인증 AND 랜딩 외부**에서만 — SURF-4), 플래시 `p#notice`/`p#alert` 유지, 본문 크림 배경 |
| `app/helpers/application_helper.rb` | `noindex?`(경로 접두 `/app`·`/b/`·`/admin`·`/welcome` — SURF-3), `show_login_link?`(SURF-4), `step_icon_path`(LP-3 아이콘 경로) |
| `public/robots.txt` | `Disallow: /app`·`/b/`·`/admin`·`/welcome` — SURF-3 robots 차단 절반 보완 |
| `app/controllers/concerns/authentication.rb` | `after_authentication_url` — 로그인 직후 `display_name` 미설정 시 `edit_app_profile_url` 우선 리다이렉트(AUTH-1.3). return_to는 프로필 완료 후 의미가 없으므로 프로필이 우선 |
| `app/models/user.rb` | `enum :business_type, { business: 0, freelancer: 1 }`, `on: :profile` 컨텍스트 검증(display_name·business_type 필수, phone·account_number 형식), `normalizes :display_name`(strip) (AUTH-1.3) |
| `config/routes.rb` | `namespace :app { resource :profile, only: %i[edit update] }` — 표면 ② 블록 신설 |
| `app/controllers/registrations_controller.rb` | `welcome` 액션이 `@user = Current.user` 설정(뷰 분기용). 가입 리다이렉트는 welcome **유지**(하단 §4) |
| `app/views/registrations/welcome.html.erb` | 조건 분기: 미설정 → 프로필 설정 안내 패널+CTA(「프로필 설정 시작하기」), 설정됨 → 임시 완료 화면. h1 「가입이 완료되었습니다」·로그아웃 불변 |
| `app/views/sessions/new.html.erb` | 디자인 시스템 재적용(카드 폼·rounded-xl·포커스 링) — **문구·링크·기능 불변** |
| `app/views/registrations/new.html.erb` | 동일 재적용 — 문구·링크·오류 블록(role=alert) 불변 |
| `app/views/passwords/new.html.erb` | 동일 재적용 |
| `app/views/passwords/edit.html.erb` | 동일 재적용 |
| `app/views/landing/index.html.erb` | 전면 재구성 — 9개 파셜 렌더 + 메타 description(LP-1~8·10, LP-9 미표기) |
| `app/controllers/landing_controller.rb` | 주석만 갱신(LP-1~8·10 반영) — 동작 변경 없음 |
| `config/locales/en.yml` | User 프로필 오류 4종 한글 문구(display_name.blank·business_type.blank·phone.invalid·account_number.invalid) |
| `db/schema.rb` | `db:migrate`로 갱신(users 프로필 6컬럼) |

## 2. Rule ID 매핑

| Rule ID | 구현 |
|:---|:---|
| **AUTH-1.3** | users 프로필 6컬럼(모두 이후 수정 가능), `/app/profile` edit+update, 표시명·사업자 유형은 `:profile` 컨텍스트에서 필수(가입 시점 자유), 계좌 3종·연락처 선택, 은행 select 국내 목록, 라디오카드(프리랜서=원천징수 3.3% 표기 안내), 계좌번호 자동 하이픈 Stimulus 1개, 로그인 직후 미설정 리다이렉트(`after_authentication_url`), 가입 직후 welcome에서 설정 안내, 저장 후 임시 완료 화면 |
| **DESIGN-1** | 「정중한 사무실」 톤 — 크림 배경+딥 그린 액센트+stone 중립, 장식은 랜딩(①)에 한해 절제 사용(SVG 아이콘·그라데이션), 인증·프로필 화면은 정보 우선 |
| **DESIGN-2** | `--color-cream: #faf9f5` 토큰 + emerald-800/900 단일 액센트 전역 적용(레이아웃·전 화면) |
| **DESIGN-3** | Pretendard CDN 전역 폰트(시스템 스택 제거), 금액·수치는 tabular-nums 대비 큰 사이즈(요금제 카드) |
| **DESIGN-4** | 표면별 강도 — ① 자유도(배지·버블 UI·그라데이션), 인증/프로필은 장식 최소 |
| **DESIGN-6** | 터치 타깃(px-8 py-4 CTA·py-3 버튼·라디오카드 p-4), 폼 포커스 링(ring-2)·placeholder·오류 상태 색 |
| **DESIGN-7** | 레퍼런스 벤치마킹 포인트만 취함 — Stripe식 절제·타이포 위계, 볼타식 정보 위계(요금제), 토스 송금식 폼 UX(라벨+힌트+오류) — 화면 복제 없음 |
| **LP-1** | Q6 헤드라인·서브카피·주 CTA 「무료로 시작하기」→`new_registration_path`·보조 문구 「무료 · 카드등록 없음 · 3분」 **불변**, 배지/위계/CTA 디테일만 고도화 |
| **LP-2** | PRD 지정 인용 3종 원문(열람 불안·독촉 부담·관계 걱정), 해결 소개 전 공감 배치 |
| **LP-3** | 수금 루프 5단계(발행→전달·열람 추적→자동 리마인더→약속 수집→수금 마감) — 각 단계 한 줄 설명, 번호·아이콘·연결선 |
| **LP-4** | PRD 지정 3종 이점 문장 원문 + 보조 설명 |
| **LP-5** | 실제 4단계 발신 문구 예시 공개(투명성) — REM-1 서비스 명의·REM-2 단계별 톤·Q2 법적 조치 언급 없음 |
| **LP-6** | 4요소 구성 + VIEW-5 고지문 원문 게시(채무자가 볼 수 있는 유일한 서비스 소개임을 감안한 서술) |
| **LP-7** | Free(3건/5거래처·수동 발송), Plus(9,900원·14일 무료 체험·무제한·자동 시퀀스·약속 수집·이력·리포트), 수금 패스(10건 4,000원·90일) — 수치 원문, **「부가세 포함」 명시**(결정 #4), 건당 5통(대체 SMS 포함) 각주, 가격 CTA 없음 |
| **LP-8** | PRD 지정 8항목 아코디언(details/summary — JS 0) |
| **LP-9** | **미표기** — 후기 미보유, 섹션 자체 없음(빈 후기·가짜 후기 없음) |
| **LP-10** | 히어로 메시지 반복 + CTA 1회(동일 링크), 푸터에 서비스 소개·문의 채널(카카오톡 채널 '받을돈')·©. 약관·개인정보 링크 미포함(결정 #5) |
| **SURF-3** | 랜딩 noindex 없음 + 메타 description 추가(색인 허용), `/app`·`/b/`·`/admin`(+인증 전용 `/welcome`) noindex 메타·robots.txt 차단 |
| **SURF-4** | 랜딩의 모든 `a`는 가입 CTA뿐(헤더 로그인 링크는 랜딩에서 숨김, 문의 채널은 텍스트 표기, 인페이지 앵커 없음) — ①→② 단일 진입 |
| **SURF-5** | 태그라인·작동 방식(5단계 루프 시각화)·요금제(PLAN-1~4)·FAQ(추심 오인 해소 포함)·가입 CTA 전부 갖춤 |
| **SURF-6** | 랜딩 정적 마크업 — 쿼리·모델 호출 없음, 외부 리소스는 Pretendard CDN 1건, 이미지 파일 0 |
| **REM-2** | LP-5 4단계 문구 톤(예고→확인→재요청→최종 안내), 정중한 합니다체, D+14에 법적 조치·내용증명 언급 없음(Q2) |
| **REM-1** | LP-5 버블 발신자 표기 「받을돈」(서비스 명의) |
| **LP-12** | 신규 문구 전체 — 확정 보장·압박·추심 오인 표현 미사용. `100%`·`보장` 단어 자체를 페이지에서 배제(기존 테스트 정규식 준수) |
| **PLAN-1/2/4** | LP-7 카드 수치 원문 표기 |
| **PLAN-3** | 「청구 건당 최대 5통(대체 SMS 포함)」 요금제 각주 + FAQ ⑤ |
| **P1·P5** | 문구 톤 검증 대상으로 명시(§3), VIEW-5 고지문 원문·추심 아님 포지셔닝 |
| **TIME-1 외** | 해당 없음(발송 로직 미포함) |

## 3. 신규 작성 문구 목록 (Reviewer 집중 검증 대상)

### 3.1 LP-5 발신 문구 4종 (REM-2·P1·Q2 기준) — `_message_samples.html.erb`
- **D-1 예고**: 「안녕하세요. 받을돈입니다. [발행인 표시명]님이 보낸 청구서 ‘[청구서명]’(결제 금액 [금액]원)의 결제 예정일이 내일 [만기일]입니다. 미리 안내드리며, 확인 부탁드립니다.」
- **D+1 확인**: 「안녕하세요. 받을돈입니다. 예정일이 지난 ‘[청구서명]’의 입금이 아직 확인되지 않았습니다. 이미 입금하셨다면 링크에서 알려주시면 [발행인 표시명]님께 전달드리겠습니다. 사정이 있으시면 입금 예정일을 알려주세요.」
- **D+7 재요청**: 「안녕하세요. 받을돈입니다. ‘[청구서명]’ 결제가 일주일 지연되고 있습니다. 일정 조정이 필요하시다면 링크에서 입금 예정일을 제안해 주세요. [발행인 표시명]님께 바로 전달드리겠습니다.」
- **D+14 최종 안내**: 「안녕하세요. 받을돈입니다. ‘[청구서명]’이 만기 후 2주가 되었습니다. 이번 안내가 해당 청구서의 마지막 알림입니다. 입금 예정일이나 입금 완료 알림을 링크에 남겨주시면 [발행인 표시명]님께 전달드리겠습니다.」 — 법적 조치·내용증명 언급 없음(Q2)
- `[ ]` 자리표시는 "예시 문구 템플릿"임을 본문에서 명시(「[ ] 안은 발송 시 채워지는 자리입니다」)

### 3.2 LP-8 FAQ 답변 8종 (LP-12 기준) — `_faq.html.erb`
- ① 추심·법무 대행 아님 고지(발행인 직접 발행 도구) ② 문구 톤·예정일 제안 조율 설명 ③ 개인 연락처 미노출 ④ 거래처 무가입·무설치 ⑤ 발송 비용 서비스 부담+건당 5통 제한 ⑥ 고유 링크·로그인 보호 설명(과잉 안전 공언 회피) ⑦ 해지 기간 말까지 이용(PLAN-5) ⑧ 프리랜서 3.3% 표기 적용 안내
- 섹션 헤딩/부제: 「발행만으로는, 돈이 받아지지 않습니다」(LP-2), 「청구 링크 한 번으로, 수금 루프가 굴러갑니다」(LP-3), 「독촉이 아니라, 확인과 약속으로 수금합니다」(LP-4), 「거래처가 받을 메시지, 미리 보여드립니다」(LP-5), 「쓰는 만큼만, 투명한 요금」(LP-7) 등 각 섹션 헤딩도 신규 문구
- 메타 description 1건(색인 허용 표면용)

## 4. 설계 결정 및 기존 테스트 영향

### 4.1 의도적 동작 변경 2건 (승인된 플랜 반영 — Phase 7 테스트 갱신 필요)

| 변경 | 근거 | 영향받는 기존 테스트 | 내용 |
|:---|:---|:---|:---|
| LP-10 최종 CTA 추가 | 플랜 B-2「LP-10 … CTA 1회(동일 링크)」 | `LandingControllerTest#test_주_CTA는_가입_화면_실링크다` | `a[href=new_registration_path]` count 기대 1 → 실제 2(히어로+최종). 문구·링크 불변은 유지(양쪽 모두 「무료로 시작하기」+가입 링크), SURF-4 앵커 순수성 테스트(전체 `a`가 가입 링크뿐)는 **통과 유지** |
| 로그인 직후 프로필 리다이렉트 | 플랜 B-3「가입/로그인 직후 미완료 리다이렉트(AfterAuthentication 경로 활용)」 | `SessionsControllerTest#test_올바른_자격_증명은_303과_세션_발급으로_로그인한다`, `RegistrationsControllerTest#test_변형_이메일로_가입하면_정규화된_이메일로_로그인된다` | fixture 사용자는 display_name이 없어(테스트 파일 수정 불가) 로그인 리다이렉트가 root → `/app/profile/edit`로 변경. Phase 7에서 fixture에 display_name 추가 또는 어설션 갱신 필요 |

### 4.2 테스트 무손상 설계 (기존 어설션 회귀 방지 조치)

- 랜딩 h1은 히어로 1개뿐(나머지 섹션 전부 h2/h3) — `assert_select "h1", count: 1` 유지
- 「작동 방식 보기」 disabled 버튼은 히어로에 1개만 존재(LP-3 앵커 이동은 SURF-4 위반이라 비활성 유지) — `count: 1` 유지
- 서브카피·보조 문구는 히어로에 원문 유지(최종 CTA의 반복 문구는 `count` 미지정 어설션과 양립)
- 전체 페이지에서 `100%`·`보장` 어휘 배제 — LP-12 정규식 유지
- 가입 리다이렉트는 welcome 유지 + welcome 화면에서 프로필 설정 CTA로 연결(가입 테스트의 `redirect_to welcome_path`·h1·notice 전부 통과)
- 로그아웃·flash `p#notice`/`p#alert` id·인증 화면 문구·링크 전부 불변

### 4.3 기타 결정
- **은행 목록**: `App::ProfilesHelper::BANKS` 상수 20개(국내 주요 은행·뱅크) — 모델 도메인이 아닌 표현 데이터로 헬퍼 배치
- **검증 방식**: 폼 객체 대신 `save(context: :profile)` 컨텍스트 검증 선택 — 단일 모델·단일 폼 과제에 맞는 가장 지루한(boring) 구현, 가입 경로에 영향 없음
- **푸터 사업자 정보**: 상호·등록번호 등 실사 데이터가 문서상 미확보라 서비스 소개·문의 채널(카카오톡 채널 '받을돈')·©만 표기. 등록 정보 확보 후 한 줄 추가하면 되는 구조(결정 #5와 동일 선상 — 허위 데이터 표기 금지)
- **robots.txt**: SURF-3의 "robots 차단" 절반을 메타 noindex와 쌍으로 보완(`/welcome`도 인증 전용 화면으로 포함)

## 5. 자체 점검 결과 (2026-10-12 실측)

| 점검 | 결과 |
|:---|:---|
| `bin/rails db:migrate` | **성공** — AddProfileFieldsToUsers 6컬럼, `db/schema.rb` 갱신 확인 |
| `bin/rubocop` | **0 offenses** (48 files) |
| `bin/rails zeitwerk:check` | **통과** ("all is good!") |
| `bin/rails test` | **50 runs, 280 assertions, 3 failures, 0 errors** — 3건 모두 §4.1의 의도적 동작 변경(문구·링크·SURF-4 불변 요건은 회귀 없음). 상세는 §4.1 표 |
| 프로필 플로우 실측(rails runner 통합 세션) | 비인증 `/app/profile/edit` → 302 로그인 · 로그인(미설정) → 303 `/app/profile/edit` · 빈값 저장 → **422**+한글 오류(「표시명(또는 상호)을 입력해 주세요.」 등) · 6필드 정상 저장 → **303 `/welcome`** → DB 재조회로 6컬럼 전부 일치 확인(`"김디자인 스튜디오"/business/국민은행/123-45-678901/김디자인/010-1234-5678`) · 완료 화면 문구 확인 · 재로그인(완료) → 303 `/`(root), (미설정) → 303 `/app/profile/edit` |
| 검증 컨텍스트 실측 | `valid?`(가입 컨텍스트)는 프로필 미설정 통과 / `valid?(:profile)`은 display_name·business_type blank 거부 + phone·account_number 형식 거부 + 한글 메시지, `normalizes :display_name` strip 확인 |
| 뷰 렌더 실측 | 프로필 화면: 라디오카드(「원천징수 3.3% 표기 적용」)·은행 select·`data-controller="account-number"`·noindex 메타 노출 확인 |
| 잔존 데이터 | smoke용 사용자·세션 전부 삭제 확인 |

서버 기동·테스트 작성은 하지 않음(Phase 4·7·8 인계).

## 6. 후속 인계 노트 (Reviewer/Tester)

1. **Phase 7 테스트 갱신 목록**: §4.1 표의 3건 — (a) 랜딩 CTA count 1→2 (히어로+LP-10, 동일 문구·링크), (b) 로그인 리다이렉트 root→profile(또는 fixture에 `display_name` 추가). 그 외 47건 통과 유지.
2. **LP-5·LP-8·섹션 헤딩 문구**는 §3 목록 기준으로 톤·금지 표현 검증 요망(REM-2·LP-12·P1).
3. Pretendard는 CDN(`<link>` jsdelivr) — 프로덕션 도입 시 셀프호스팅 전환 여부는 후속 결정 사항.
4. `/app`은 프로필 화면만 존재 — 대시보드 본체(표면 ②) 구축 시 `after_authentication_url`의 완료 분기 대상을 `/app`으로 바꾸면 됨(1행).
5. 랜딩 그라데이션·아이콘 등 Tailwind 클래스 빌드는 `bin/dev` watch 대상 — `app/assets/builds/tailwind.css`는 Phase 4 빌드에서 재생성됨.

## 수정 이력 (Phase 6)

- **일자**: 2026-10-12
- **근거**: `_workspace/05_review.md` Phase 5 리뷰(CHANGES_REQUESTED — CRITICAL 1·WARNING 7·확인요청 1) 이슈별 1:1 최소 수정. 위 본문(§1~6)은 원본 유지.
- **D+14 문구 변경(#2)**: 오케스트레이터가 리뷰어 제안 1안을 채택 확정하여 반영.

| 리뷰 이슈 | 심각도 | 수정 내용 | 파일 |
|:---|:---|:---|:---|
| #1 계좌정보 로그 미필터링 | **CRITICAL** | `filter_parameters`에 `:account_number, :account_holder, :phone` 추가 — 프로필 저장 시 파라미터 로그 평문 기록 차단 | `config/initializers/filter_parameter_logging.rb` |
| #2 LP-5 D+14 문구 | WARNING | 「이번 안내가 해당 청구서의 마지막 알림입니다」→「이번 안내로 정기 리마인더를 마칩니다」 — 정기 시퀀스(REM-12)의 종결을 지칭, PROMISE-3 약속일 리마인드와의 모순 제거(§3 문구 목록의 해당 문장도 본 절 기준으로 갱신됨) | `app/views/landing/_message_samples.html.erb` |
| #3 요금 수치 tabular-nums | WARNING | 가격 `<p>` 3곳(0원·9,900원·4,000원)에 `tabular-nums` 적용 — 빌드 CSS에 유틸리티 존재 확인(클래스 지정만으로 적용). §2 DESIGN-3 행 기술·실제 불일치(후속 추적 E) 해소 | `app/views/landing/_pricing.html.erb` |
| #4 저대비 텍스트 7곳 | WARNING | 힌트 6곳 + 푸터 © `text-stone-400`→`text-stone-500`(WCAG AA 4.5:1 목표). `placeholder:text-stone-400`은 헬퍼에 그대로 유지(리뷰 허용) | `app/views/app/profiles/edit.html.erb`(6곳), `app/views/landing/_closing.html.erb`(1곳) |
| #5 프로필 수정 재진입 경로 | WARNING | welcome 완료 분기에 「프로필 수정」 보조 링크(`edit_app_profile_path`) 추가 — 「모두 이후 수정 가능」 관측 가능화(/app 대시보드 구축 시 대체). 터치타깃 44px(py-3+text-sm) | `app/views/registrations/welcome.html.erb` |
| #6 헤더 로그인 링크 터치타깃 | WARNING (Low) | `px-3 py-2`→`inline-flex min-h-11 items-center px-3` — 44px 확보(리뷰 제안 2안) | `app/views/layouts/application.html.erb` |
| #7 계좌 오류 문구 | WARNING (Low) | invalid 문구에 길이 안내 포함: 「계좌번호 형식을 확인해 주세요. 숫자와 하이픈(-)으로 5자 이상 입력해 주세요.」 — 검증 정규식 `\A\d[\d-]{4,19}\z`(5~20자)와 일치 | `config/locales/en.yml` |
| #8 placeholder 불일치 | WARNING (Low) | 계좌 placeholder 「예) 123-45-678901」→「예) 1234-5678-9012」 — 자동 하이픈 4자리 그룹(`account_number` 컨트롤러)과 일치 | `app/views/app/profiles/edit.html.erb` |

### 자체 점검 결과 (2026-10-12 실측)

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **0 offenses** (48 files inspected) |
| `bin/rails zeitwerk:check` | **통과** ("Otherwise, all is good!") |
| [FILTERED] 러너 검증(선택) | `ActiveSupport::ParameterFilter`에 앱 설정 적용 실측 — `account_number`·`account_holder`·`phone` → `[FILTERED]`, `bank_name`·`display_name`은 평문 유지 |
| 테스트 작성·서버 기동 | 미실행 (Phase 7 Tester 인계 — 이슈 #1 로그 [FILTERED] 검증, #3·#4·#6 클래스 변경에 따른 빌드 재생성 확인 포함) |

- **범위**: 리뷰 이슈 8건(수정 지시 9항목 — #2 문구 채택 별도)만 수정, 문구·링크·기능·기존 본문 불변. 미수정 확정 항목(LP-3 실화면 이미지·푸터 약관·Pretendard 셀프호스팅·보조 CTA 비활성 = 후속 추적 A~D) 유지.
- 마이그레이션 없음 · `db/schema.rb` 변경 없음.

# 07_test_report.md — Phase 7 테스트 보고: 랜딩 전체(LP-1~8·10) + AUTH-1.3 프로필

- **일자**: 2026-10-12
- **Tester**: DesignTester
- **대상**: Phase 6 수정 완료 코드(랜딩 전체 리디자인 + AUTH-1.3 프로필 설정) 기준 테스트 신규 작성·갱신·전체 실행
- **결론**: **83 runs, 557 assertions, 0 failures, 0 errors, 0 skips — 전체 통과.** 코드 버그 0건. 실행 중 발생한 4건의 실패·오류는 전부 테스트 오류로 분류되어 자체 수정 후 통과(§4).

## 1. 실행 결과 요약

| 구분 | Before(Phase 6 인계 시점) | After(Phase 7 완료) |
|:---|:---|:---|
| 실행 | 50 runs / 280 assertions | **83 runs / 557 assertions** |
| 결과 | 3 failures (03 §4.1 명세 이행분 — 갱신 대상) | **0 failures, 0 errors, 0 skips** |
| 시드 | 31003 (실패 확인) | 4993·1290·22874 등 3회 재실행 모두 통과 |

- 명령: `bin/rails test` (8 프로세스 병렬)
- `bin/rubocop`: **50 files inspected, no offenses** — 테스트 소스 미사용 정의 0건, 들여쓰기 2칸 준수
- 외부 API 실호출: **0건** — 이번 계층(컨트롤러 통합·모델·정적 뷰)에 핵클·토스페이먼츠 의존 로직 없음. 이메일 발송(passwords)은 기존 테스트 어댑터 범위 유지

## 2. 변경 파일

| 파일 | 변경 | 내용 |
|:---|:---|:---|
| `test/fixtures/users.yml` | 갱신 | `gamma` 추가 — 프로필 완료 6필드(display_name·freelancer·은행·계좌·예금주·연락처). alpha·beta는 미설정 유지 → root/profile 리다이렉트 양 분기 검증 기반 |
| `test/controllers/landing_controller_test.rb` | 갱신+신규 | 주 CTA count 1→2 갱신(문구·링크 불변 포함 강화), LP-2~8·10·메타 description·Q2 신규 10건 |
| `test/controllers/sessions_controller_test.rb` | 갱신+신규 | 로그인 리다이렉트 root→profile 갱신, 완료 사용자 root 분기·return_to보다 프로필 우선 신규 2건 |
| `test/controllers/registrations_controller_test.rb` | 갱신 | 변형 이메일 재로그인 리다이렉트 갱신(신규 계정 = 프로필 미설정) |
| `test/controllers/app/profiles_controller_test.rb` | **신규** | AUTH-1.3 통합 12건 — 가드·폼·422·303·DB 6컬럼·재로그인·welcome 링크·소유자 스코프·로그 [FILTERED] |
| `test/integration/surf3_indexing_test.rb` | **신규** | SURF-3 회귀 4건 — /app·/welcome noindex, 랜딩 색인 허용, robots.txt 차단 경로 |
| `test/models/user_test.rb` | 신규 5건 | :profile 컨텍스트 검증(필수·형식·한글 문구), 가입 컨텍스트 통과, 표시명 strip 정규화 |

## 3. 시나리오별 결과 (Reviewer 지정 6개 영역)

### 3.1 랜딩 전체 (LandingControllerTest — 18건 전부 통과)

| 시나리오 | Rule ID | 결과 | 검증 내용 |
|:---|:---|:---|:---|
| 히어로 렌더·h1 1개 | SURF-1·LP-1 | ✅ | 레이아웃 h1 없음 → h1 1개 = 랜딩 뷰 렌더 증거(회귀 유지) |
| Q6 헤드라인 원문 | LP-1 | ✅ | 「말하기 어려운 '돈 다오'…」 정규식 매칭(회귀 유지) |
| LP-1 구성 4종 | LP-1 | ✅ | 서브카피 루프 어휘·주 CTA·보조 문구·보조 CTA disabled(회귀 유지) |
| 주 CTA 실링크 | SURF-4·AUTH-1 | ✅ | **count 1→2 갱신** — 히어로+LP-10, 동일 링크 `new_registration_path`·동일 문구 「무료로 시작하기」 각 2건 |
| 앵커 순수성 | SURF-4 | ✅ | 전체 `a` == 가입 링크뿐, 로그인·재설정 링크 0건(회귀 유지) |
| 카카오 CTA 잔존 부재 | AUTH-1 | ✅ | (회귀 유지) |
| noindex 부재 + title | SURF-3 | ✅ | 랜딩 색인 허용(회귀 유지) |
| 금지 표현 부재 | LP-12 | ✅ | `100%`·`보장` 전체 응답 부재(회귀 유지) |
| 메타 description | SURF-3 | ✅ | **신규** — 1건 존재, 레이아웃 폴백이 아닌 랜딩 전용 문구(「수금 루프」 포함) |
| LP-2 인용 3종 원문 | LP-2 | ✅ | **신규** — `figure blockquote` 3건 + PRD 원문 3매칭(LP-6 고지문 blockquote와 스코프 구분) |
| LP-3 5단계 루프 | LP-3 | ✅ | **신규** — ol li 5건 + 5단계 라벨(발행→수금 마감) |
| LP-4 이점 3종 원문 | LP-4 | ✅ | **신규** — PRD 지정 문장 3매칭 |
| LP-5 4단계 라벨·문구 | LP-5·REM-2 | ✅ | **신규** — D-1/D+1/D+7/D+14 배지 + 예고/확인/재요청/최종 안내 + 4개 버블 모두 「안녕하세요. 받을돈입니다.」 개시(REM-1 서비스 명의) |
| LP-5 D+14 문구 | 리뷰 #2·Q2 | ✅ | **신규** — 「이번 안내로 정기 리마인더를 마칩니다」 채택 문구 노출, 구문 「마지막 알림」 부재(PROMISE-3 모순 회귀 방지), D+14 본문에 법적 조치·내용증명·채권 언급 0건(Q2 — LP-6의 서비스 경계 서술과 스코프 분리) |
| LP-6 포지셔닝·고지문 | LP-6·P5 | ✅ | **신규** — h2 「…추심 서비스가 아닙니다」 + VIEW-5 고지문 **원문** 매칭 |
| LP-7 요금 수치 | LP-7·PLAN-1/2/3/4 | ✅ | **신규** — 월 3건·거래처 5개 / 9,900원 / 첫 14일 무료 체험 / 4,000원 / 90일 유효 / 건당 5통(대체 SMS 포함) / 「부가세 포함」 2곳 이상 |
| LP-8 FAQ 8항목 | LP-8 | ✅ | **신규** — `summary` 8건 + PRD 지정 8질문 전부 노출 |
| LP-10 푸터 문의 채널 | LP-10·결정 #5 | ✅ | **신규** — 카카오톡 채널 ‘받을돈’·© 2026 |

### 3.2 AUTH-1.3 통합 (신규 프로필 12건 + 세션 2건 + 모델 5건 + 가입 1건 갱신)

| 시나리오 | Rule ID | 결과 | 검증 내용 |
|:---|:---|:---|:---|
| 비인증 edit 접근 | 기본 가드 | ✅ | **신규** — 302 → `new_session_path` |
| 비인증 저장 시도 | 기본 가드 | ✅ | **신규** — `assert_no_changes` display_name, 로그인 리다이렉트 |
| 로그인(미설정) 분기 | AUTH-1.3 | ✅ | **갱신** — 303 → `/app/profile/edit`(구 root), notice 유지 |
| 로그인(완료) 분기 | AUTH-1.3 | ✅ | **신규** — gamma(6필드 fixture) 303 → root |
| return_to보다 프로필 우선 | AUTH-1.3 | ✅ | **신규** — 비인증 /welcome 진입→로그인 시에도 303 → profile(welcome 아님) |
| 폼 렌더 | AUTH-1.3 | ✅ | **신규** — 필수 2+선택 4 필드, 라디오 2종, 은행 select, 하이픈 Stimulus 컨트롤러, placeholder 「예) 1234-5678-9012」(리뷰 #8 회귀) |
| 빈값 제출 | AUTH-1.3 | ✅ | **신규** — 422 + 표시명·사업자 유형 한글 오류, DB 미변경 |
| 형식 오류 제출 | AUTH-1.3 | ✅ | **신규** — 422 + 연락처 문구 + 계좌 5자 이상 길이 안내 문구(리뷰 #7 회귀) |
| 필수 2필드만 저장 | AUTH-1.3 | ✅ | **신규** — 선택 4필드 공백 허용(nil 유지), 표시명 strip 정규화 |
| 6필드 저장 | AUTH-1.3 | ✅ | **신규** — 303 → welcome + 완료 화면 h1·notice + **DB 6컬럼 전부 일치** |
| 완료 후 재로그인 | AUTH-1.3 | ✅ | **신규** — 저장→로그아웃→재로그인 303 → root |
| welcome 미설정 분기 CTA | AUTH-1.3 | ✅ | **신규** — 「프로필 설정 시작하기」 링크 |
| welcome 완료 분기 링크 | 리뷰 #5 | ✅ | **신규** — 「프로필 수정」 링크 노출 |
| 소유자 스코프 | 보안 | ✅ | **신규** — email·password를 파라미터로 주입해도 화이트리스트 밖으로 불변(권한 상향 차단), 타 사용자(beta·gamma) 레코드 무영향 |
| **로그 [FILTERED]** | **리뷰 #1 CRITICAL** | ✅ | **신규** — 저장 요청 실제 로그 캡처: `account_number`·`account_holder`·`phone` → `[FILTERED]`, 평문 부재 확인. `bank_name`·`display_name`은 평문 유지(과잉 필터링 아님) |
| 프로필 컨텍스트 검증 | AUTH-1.3(모델) | ✅ | **신규 5건** — 가입 컨텍스트는 프로필 미설정 통과 / :profile에서 필수 2필드 한글 오류 / 완료 사용자 통과 / phone·account_number 형식 거부 / 표시명 strip |
| 변형 이메일 재로그인 | AUTH-1.4 | ✅ | **갱신** — 신규 계정 로그인 303 → profile(미설정이므로) |

### 3.3 SURF-3 noindex/robots 회귀 (신규 4건)

| 시나리오 | 결과 |
|:---|:---|
| /app/profile noindex 메타 1건 | ✅ |
| /welcome noindex 메타 1건 | ✅ |
| 랜딩 noindex 메타 0건(색인 허용) | ✅ |
| robots.txt Disallow /app·/b/·/admin·/welcome | ✅ |

## 4. 실패·오류 상세와 원인 분류

실행 과정에서 4건이 발생했으나 **전부 테스트 오류**(테스트 코드 결함) — 코드 버그 0건, 원본 코드 수정 없음.

| # | 현상 | 분류 | 원인과 수정 |
|:---|:---|:---|:---|
| 1 | 로그 필터 테스트 NoMethodError `stop_broadcasting` | 테스트 오류 | Rails 8 `BroadcastLogger` API는 `stop_broadcasting_to` — 메서드명 수정 |
| 2 | blockquote 카운트 3 기대, 실제 4 | 테스트 오류 | LP-6 VIEW-5 고지문도 blockquote — LP-2 스코프를 `figure blockquote`로 한정 |
| 3 | 로그 [FILTERED] 문자열 미매칭 | 테스트 오류 | Rails 8 파라미터 로그 inspect 포맷은 `"key" => "value"`(공백 포함) — 기대 문자열 수정. (로그 캡처 결과 `[FILTERED]` 자체는 정상 출력 — 리뷰 #1 수정분 동작 확인) |
| 4 | (편집 직후 파서 경고) `assert_predicate x, :valid?(:profile)` | 테스트 오류 | 심볼 리터럴+호출로 해석되는 잘못된 작성 — `assert x.valid?(:profile)`로 수정 |

## 5. 회귀 결과

- 기존 47건: **전부 통과 유지** — 문구(title·Q6 헤드라인·인용 원문)·링크(가입 실링크·앵커 순수성)·인증(세션 30일·rate limit·CSRF·열거 방지)·재설정(AUTH-8)·메일 어설션 전부 무손상.
- 갱신 3건(03 §4.1): 랜딩 CTA count·로그인 리다이렉트 2건 — 플랜 명세 이행분만 어설션 변경, 나머지 검증은 강화(동일 문구·링크 명시).
- SURF-4 앵커 순수성·h1 1개·LP-12 금지어·보조 CTA disabled: 랜딩 전면 재구성 후에도 기존 어설션 그대로 통과 — 03 §4.2 설계(무손상) 검증됨.

## 6. 비고 (Phase 8 인계)

1. 시스템 테스트는 이번 계층 아님(플랜 확인) — Tailwind 빌드(`bin/dev` 재생성)는 Phase 8 확인 대상 유지. 리뷰 #3·#4·#6 클래스 변경분은 통합 테스트가 아닌 브라우저 확인 필요.
2. 랜딩 셀렉터는 문구 원문 기준으로 작성 — LP-5·LP-8·섹션 헤딩 문구 변경 시 대응 테스트가 동일 파일에 응집해 있어 추적 용이.
3. `/b/*`·`/admin` 표면은 미구현으로 noindex 메타 실응답 검증 불가 — robots.txt 라인 존재 + 헬퍼 접두 목록(`/b/`·`/admin`)으로 회귀 고정. 해당 표면 구축 시 실응답 테스트 추가 권장.

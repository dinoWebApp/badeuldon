# 07_test_report.md — Phase 7 테스트: 이메일/비밀번호 인증(OAuth 폐기 반전) + 랜딩 CTA

- **일자**: 2026-10-12
- **대상**: Phase 6 수정 완료본(Phase 5b 재리뷰 APPROVED) — 가입·로그인·로그아웃·비밀번호 재설정·랜딩 CTA
- **기반**: PRD v0.18(AUTH-1·AUTH-1.4·AUTH-1.6·AUTH-8·SURF-4·LP-1), `_workspace/03_implementation.md`, `_workspace/05_review.md` 재리뷰 「Phase 7 Tester 최종 중점 영역 §1~§5」
- **계층**: 모델 + 컨트롤러 통합 + 메일러(계약상 시스템 테스트 제외 — 뷰어 플로우는 본 Phase 범위 아님)

## 1. 실행 결과 요약

| 항목 | 결과 |
|:---|:---|
| `bin/rails test` (전체 회귀 포함) | **50 runs, 278 assertions — 0 failures, 0 errors, 0 skips** |
| 파일별 | UserTest 8 · RegistrationsControllerTest 12 · SessionsControllerTest 9 · PasswordsControllerTest 11 · LandingControllerTest 8 · PasswordsMailerTest 1 · HealthCheckTest(기존) 1 |
| `bin/rubocop` | **45 files inspected, no offenses** (들여쓰기 2칸 준수) |
| 외부 API 실호출 | **0건** — 메일은 테스트 배송(`ActionMailer::Base.deliveries`), 핵클·토스 등 외부 의존 없음 |

## 2. 시나리오별 결과 (재리뷰 중점 영역 §1~§5 대응)

### §1 회원가입 — `test/controllers/registrations_controller_test.rb` (리뷰 이슈 #1·#3 회귀)
| 시나리오 | 결과 |
|:---|:---|
| 가입 폼 렌더(폼·로그인 링크) | PASS |
| 정상 가입 → 303 `/welcome`·세션 발급(User+Session 각 +1)·쿠키 존재·환영 notice 렌더 | PASS |
| 가입 세션으로 `/welcome` 접근 200 | PASS |
| 인증 없는 `/welcome` → 로그인 리다이렉트(가드) | PASS |
| **동일 이메일 재가입 → 422 + 「이미 등록된 이메일입니다」 렌더, User.count 불변(500 소멸 회귀)** | PASS |
| **대소문자·공백 변형(`  ALPHA@EXAMPLE.COM `) 재가입 → 422 + 동일 문구** | PASS |
| 변형 이메일 가입 → 정규화값(`mixed.case@example.com`) 로그인 303 (AUTH-1.4) | PASS |
| 검증 실패 4종 각 422 + 한글 문구 렌더: 빈 이메일 / 빈 비밀번호 / 확인 불일치 / 73자 비밀번호 | PASS ×4 |
| 가입 rate_limit — 11회째 요청 리다이렉트 + 「너무 많은 요청이 있었습니다…」 | PASS |

모델 계층(`test/models/user_test.rb`): 이메일 정규화·필수·고유(동일·변형)·비밀번호 필수(생성 시)·72바이트 초과·확인 불일치·authenticate 성공/실패 — **PASS ×8**. 오류 문구는 en.yml 한글 문구 그대로 단정(이슈 #3 회귀 고정).

### §2 로그인/로그아웃 — `test/controllers/sessions_controller_test.rb` (리뷰 이슈 #2 회귀)
| 시나리오 | 결과 |
|:---|:---|
| 로그인 폼 렌더 + 가입·재설정 링크(인증 화면 상호 링크) | PASS |
| 정상 로그인 → 303 루트·세션 +1·「로그인되었습니다.」 | PASS |
| **세션 쿠키 30일 만료 속성(AUTH-1.6) — Set-Cookie `expires` ≈ now+30일(±5분)** | PASS |
| **미가입 이메일 → 422 + 「이메일 또는 비밀번호가 올바르지 않습니다.」 본문 렌더(flash.now), 세션 불변** | PASS |
| **오류 비밀번호 → 422 + 동일 문구 본문 렌더** | PASS |
| **계정 존재/부재 응답 동일(열거 방지)** — 동일 이메일·동일 비밀번호로 계정 존재 시/destroy! 후 응답 본문 비교(요청마다 무작위인 CSRF 토큰만 마스킹) → **상태·본문 완전 동일** | PASS |
| 로그아웃 → 303·세션 파기·notice, **파기된 이전 쿠키로 `/welcome` 재진입 → 로그인 리다이렉트** | PASS |
| 로그인 rate_limit — 11회째 리다이렉트 + 「너무 많은 시도가 있었습니다…」 | PASS |
| CSRF 토큰 없는 `POST /session` → 422 거부, 세션 미생성 | PASS |

### §3 비밀번호 재설정 — `test/controllers/passwords_controller_test.rb` + `test/mailers/passwords_mailer_test.rb`
| 시나리오 | 결과 |
|:---|:---|
| 재설정 요청 폼 렌더 + 로그인 복귀 링크 | PASS |
| **가입 이메일 요청 → 메일 큐잉 검증(`assert_enqueued_email_with`)·수행 후 `deliveries` 1건·수신자 = 가입 이메일·notice 렌더** | PASS |
| **미가입 이메일 → 메일 0건, 가입 이메일과 동일 303·동일 notice(열거 방지)** | PASS |
| 요청 rate_limit — 11회째 리다이렉트 + 「너무 많은 요청이 있었습니다…」 | PASS |
| 유효 토큰 edit → 200 + 폼(action = 해당 토큰 경로) | PASS |
| 변조 토큰 → new_password 리다이렉트 + 만료 안내 alert 렌더 | PASS |
| **15분 경과 토큰(`travel 16.minutes`) → 동일 거부(AUTH-8 만료)** | PASS |
| **재설정 완료 → digest 변경·303·notice, 새 비밀번호 로그인 303 / 구 비밀번호 로그인 422** | PASS |
| **사용된 토큰 재사용 edit → 거부(1회성)** | PASS |
| **확인 불일치 → 422 + 「비밀번호를 확인해 주세요.」 본문 렌더(flash.now), digest 불변(이슈 #2·AUTH-8 축 회귀)** | PASS |
| **기존 세션 무효화 — 로그인 상태(브라우저 A)에서 토큰 재설정 → 세션 0건, A의 이전 쿠키로 `/welcome` → 로그인 리다이렉트** | PASS |
| 메일러(모델 계층) — 제목 「[받을돈] 비밀번호 재설정 안내」·수신자 = 가입 이메일·HTML/TEXT 양쪽 「이 링크는 15분 후 만료되며,」 고정 한글 문구(이슈 #5 회귀)·본문에 `/passwords/` 링크 | PASS |

### §4 랜딩 CTA — `test/controllers/landing_controller_test.rb` 갱신 (SURF-4·LP-1)
| 시나리오 | 결과 |
|:---|:---|
| GET / 비로그인 200 + 히어로 렌더, h1 Q6 문구, 서브카피(기존 회귀) | PASS ×3 |
| **주 CTA 「무료로 시작하기」 = `new_registration_path` 실링크 1개(기존 「카카오로 시작하기」 disabled 버튼 어설션 교체)** | PASS |
| **보조 문구 「무료 · 카드등록 없음 · 3분」 + 보조 CTA disabled 버튼 유지** | PASS |
| **SURF-4 단일 진입점 — 랜딩 내 모든 `<a>`의 href가 가입 경로뿐, 로그인·재설정 링크 0개(기존 「`<a>` 0개」 어설션 교체)** | PASS |
| 이전 카카오 CTA·「로그인은 곧 오픈됩니다」 잔존 0(AUTH-1 반전 회귀) | PASS |
| SURF-3 noindex 부재 + title / LP-12 금지 표현(기존 회귀) | PASS ×2 |

### §5 가드·부가 검증
- **가드**: 로그인 필요 경로는 `/welcome`이 유일(표면 ② `/app`·AUTH-7 관리자는 미구현 확정 — Phase 3 범위). 비인증 접근 → 로그인 리다이렉트 검증 완료(§1 표). 추가 가드 경로 없음 → 추가 테스트 불요.
- **CSRF 1건**: §2 표(422 거부).
- **rate_limit**: 세션·가입·재설정 각 1건(§1~§3 표).

## 3. 원인 분류

코드 버그로 판정된 실패 **0건**. 개발 중 발생한 실패 4건은 전부 **테스트 오류**로 자체 수정 후 통과:

| 실패 | 원인 분류 | 수정 |
|:---|:---|:---|
| `undefined method 'stub'` | 테스트 오류 — Minitest 6.0.6에서 `minitest/mock` 제거(`Object#stub` 부재) | 캐시 스토어 increment를 MemoryStore로 우회하는 싱글턴 메서드 helper(`with_memory_rate_limit_store`, ensure로 복원)로 대체 |
| 빈 비밀번호 로그인 기대 422 → 실제 400 | 테스트 오류 — `params.expect` 계약상 빈 값은 `ParameterMissing`(400). 실패 로그인 시나리오는 비어있지 않은 오류 비밀번호 사용이 올바름 | 프로브 요청을 `wrong-password`로 변경(422 경로) |
| edit 폼 action 불일치 | 테스트 오류 — `password_reset_token`은 호출마다 재생산되어 GET과 단정이 다른 토큰 사용 | 토큰을 1회 캡처 후 재사용 |
| 미정의 `attempt_login`(registrations) | 테스트 오류 — 헬퍼 누락 | private 헬퍼 추가 |

**관찰(결함 아님)**: 로그인 프로브로 빈 비밀번호를 보내면 400(파라미터 누락) — 폼은 `required` 속성으로 빈 제출을 클라이언트에서 차단하므로 정상 경로 아님. 검증 실패 422 시나리오는 실제 폼에서 도달 가능한 입력만 사용.

## 4. 회귀 결과

- 기존 `test/integration/health_check_test.rb`(GET /up 200) 포함 전체 `bin/rails test` **통과**(위 요약표).
- 기존 랜딩 테스트 중 무효화된 어설션 2건(「카카오로 시작하기」 버튼, `<a>` 0개)은 갱신되었고 나머지 기존 단계(h1·서브카피·SURF-3·LP-12)는 원 어설션 유지로 통과.
- fixtures는 `test/fixtures/users.yml` 표준 세트(alpha/beta, 비밀번호 `password`, Rails 표준 ERB 다이제스트)로 갱신 — 구 식별자(one/two) 참조는 전무하여 타 파일 영향 없음.

## 5. 스킵 사유

| 항목 | 사유 |
|:---|:---|
| AUTH-1.6 세션 30일 | **스킵 아님** — 통합 계층에서 로그인 응답 Set-Cookie의 `expires` 속성을 파싱해 30일(±5분)로 간접 검증 완료(§2 표) |
| 계정 열거 타이밍 저항(`authenticate_by`) | 응답 상태·본문 동일성만 검증. 처리 시간 측정은 환경 노이즈로 불안정하여 테스트 부적합 — Rails 내장 타이밍 저항 구조에 의존(리뷰 확인 사항) |
| 열거 방지 본문 바이트 비교 | CSRF 토큰 등 요청마다 무작위인 값만 마스킹 후 완전 비교로 구현 — 마스킹 제외 전체 비교는 불가(무작위성 자체가 정상 동작) |
| 시스템 테스트(브라우저) | 본 Phase 계약상 제외(컨트롤러 통합 + 모델 계층). 뷰어(③) 인앱 QA는 VIEW 도메인 후속 Phase 대상 |
| `/app`·관리자 가드 | 표면 ②·AUTH-7 미구현 확정(Phase 3 범위) — 대상 경로 자체가 없음 |

## 6. 품질 자체 점검 (Tester 체크리스트)

- [x] 재리뷰 중점 §1~§5 시나리오 전부 커버(§1 12건·§2 9건·§3 12건·§4 8건·§5 3건 + 모델 8건)
- [x] 외부 API 실호출 0건(메일은 테스트 배송으로 `deliveries` 배열 검증)
- [x] 테스트 소스 미사용 정의 0건, `bin/rubocop` 0 offenses, 들여쓰기 2칸
- [x] 기존 테스트 전체 회귀 통과(50 runs / 278 assertions / 0F·0E·0S)
- [x] 리뷰 이슈 #1(중복 422)·#2(flash.now 렌더)·#3(한글 문구)·#5(메일 만료 문구) 회귀 테스트 고정

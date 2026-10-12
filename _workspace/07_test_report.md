# 07_test_report.md — Phase 7 테스트: /app 대시보드 뼈대 + 레이아웃 분리 + welcome 소멸

- **일자**: 2026-10-12
- **범위**: 기존 실패 16건 갱신(03 §4.2 방향) + /app 셸 신규 시나리오 + Phase 6 수정 3건 반영 확인
- **기준**: PRD v0.18.2 §6.9(DASH-1/2/4)·§6.2(ONB-1)·§7(SURF-3/4/6)·§6.1(AUTH-1.3), 03 §4.1 리다이렉트 전후표, 05_review.md 「Tester 중점 §1~3」

## 1. 최종 실행 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rails test` (전체 회귀) | **93 runs, 607 assertions, 0 failures, 0 errors, 0 skips — 전부 통과** |
| `bin/rubocop` | **0 offenses** (54 files inspected — 신규 파일 포함) |
| 테스트 소스 미사용 정의 | 0건 — welcome 관련 어설션은 의도적 404 회귀 1건만 잔존 |
| 외부 API 실호출 | 0건 (대상 스코프에 외부 의존 없음 — stub 불요) |

- **직전 대비**: 83 runs(2 failures + 14 errors) → 93 runs(0/0). 실패 16건 전부 해소, 신규 10건 추가(dashboards 9 + welcome 소멸 회귀 1), 기존 통과 67건 회귀 0건.
- **테스트 오류 vs 코드 버그**: 갱신 과정에서 발생한 실패는 전부 테스트 오류(구 어설션이 소멸한 welcome 화면·구 목적지를 참조)로 분류되어 자체 수정으로 해소. **코드 버그 0건** — Developer 코드 수정 없음.

## 2. 기존 16건 갱신 내역 (03 §4.2와 1:1 대응)

| # | 테스트(갱신 후) | 파일 | 갱신 내용 | 결과 |
|:---|:---|:---|:---|:---|
| 1 | 정상 가입은 303으로 세션을 시작하고 **프로필 설정으로** 안내한다 | registrations | `edit_app_profile_path` + follow h1 「프로필 설정」·notice 유지 | ✅ |
| 2 | 가입으로 시작한 세션으로 **/app에** 접근할 수 있다 | registrations | /app 접근 → 미완료 가드 리다이렉트로 세션 유효성 검증(로그인 밀림 아님) | ✅ |
| 3 | 인증 없이 **/app** 접근은 로그인 화면으로 리다이렉트된다 | registrations | `new_session_path` 목적 보존(05 리뷰 보완노트 반영) | ✅ |
| 4 | 변형 이메일 가입은 정규화 이메일로 로그인된다 | registrations | 첫 어설션 → `edit_app_profile_path` | ✅ |
| 5 | 6필드 저장은 303으로 **/app에** 안내하고 6컬럼 전부 반영 | app/profiles | `app_root_url` + follow h1 「대시보드」·notice | ✅ |
| 6 | 필수 2필드 저장·선택 4필드 공백 | app/profiles | `welcome_url` → `app_root_url` | ✅ |
| 7 | 소유자 스코프(권한 상향·탈취 불변) | app/profiles | `welcome_url` → `app_root_url` | ✅ |
| 8 | welcome 미설정 분기 CTA | app/profiles | **삭제**(화면 소멸) → 신규 「프로필 완성 중」 플레이스홀더 테스트로 대체 | ✅ |
| 9 | welcome 완료 분기 수정 링크 | app/profiles | **삭제**(화면 소멸) → 신규 완료 표시명 헤더 테스트로 대체 | ✅ |
| 10 | 프로필 완료 후 재로그인하면 **/app으로** 진입한다 | app/profiles | 저장·재로그인 어설션 모두 `app_root_url` | ✅ |
| 11 | 재설정 완료 시 기존 세션 전부 무효화 | passwords | 재진입 검증 경로 `edit_app_profile_path`(인증 표면 — 05 리뷰 보완노트) | ✅ |
| 12 | 완료 사용자 로그인은 **/app으로** 진입한다 | sessions | 폴백 `app_root_url` + 테스트명 갱신 | ✅ |
| 13 | 방문 예정 페이지 있어도 미설정이면 설정 우선 | sessions | return_to 세팅 경로 → `app_root_path` 후 **프로필 우선 재확인** | ✅ |
| 14 | 로그아웃 시 이전 쿠키 재진입 불가 | sessions | 재진입 검증 경로 → `edit_app_profile_path` | ✅ |
| 15 | **대시보드(/app)** noindex 메타 출력 | integration/surf3 | welcome 테스트 삭제 → /app 대시보드 신규(05 리뷰 권장 반영) | ✅ |
| 16 | robots.txt 3경로 차단 | integration/surf3 | `Disallow: /welcome` 어설션 제거, 3행 유지 + 테스트명 갱신 | ✅ |

## 3. 신규 시나리오 결과

### 3.1 /app 셸 — `test/controllers/app/dashboards_controller_test.rb` (신규 9건)

| 테스트 | 검증 Rule | 결과 |
|:---|:---|:---|
| 비인증 /app → 302 `new_session_path` | AUTH-1 | ✅ |
| 미완료(alpha) /app 직접 접근 → `edit_app_profile_path` 가드 | AUTH-1.3 | ✅ |
| 완료(gamma) /app 200 — h1 「대시보드」·헤더 표시명 「감마스튜디오」·robots 메타 1건 | DASH 셸·Phase 6 #2·SURF-3 | ✅ |
| DASH-1 카드 3종 라벨(미수 총액·연체 건수·금액·7일 내 만기) + 빈 상태 문구 3회 + 대시 슬롯(aria-hidden) 3회 + **「0원」 부재** | DASH-1·거짓 수치 금지 | ✅ |
| DASH-2 「오늘 할 일이 없습니다」 + 발행 시 카드 안내 문구 | DASH-2 | ✅ |
| ONB-1 CTA `button[disabled][aria-disabled=true]` 「첫 청구서 발행하기」 + 배지 「준비 중 — …」 | ONB-1 | ✅ |
| DASH-4 「연체일이 긴 순서부터 표시됩니다」 정렬 안내 | DASH-4 | ✅ |
| 사이드바 — 대시보드만 `aria-current="page"`(설정 비활성 확인), 청구서·거래처 `span[aria-disabled=true]` 2건 + 「준비 중」 배지 2건, 설정 `href=edit_app_profile_path` 실링크 | DESIGN-6·플랜 결정 #2 | ✅ |
| 로그아웃 `form.button_to[action=/session]` 내 `input[name=_method][value=delete]` + `button[data-turbo-confirm="로그아웃하시겠습니까?"]` | CSRF·DESIGN-6 | ✅ |

### 3.2 인증 화면·기타 신규

| 테스트 | 파일 | 결과 |
|:---|:---|:---|
| 로그인/가입/재설정 폼에 워드마크 「받을돈」 존재 + `a` 요소 0건(링크 아님) — 3화면 각각 | sessions·registrations·passwords (기존 GET 테스트 확장, Phase 6 #1) | ✅ |
| 프로필 화면 헤더 미완료 플레이스홀더 「프로필 완성 중」(alpha) / 완료 표시명 「감마스튜디오」(gamma) | app/profiles (Phase 6 #2 — #8·#9 대체) | ✅ |
| `GET /welcome` → **404** 소멸 회귀 | registrations (신규 1건) | ✅ |
| 랜딩 색인 허용 역방향·robots 3행 — 기존 테스트 그대로 통과 | integration/surf3 | ✅ |

### 3.3 리다이렉트 전수 대응표 (03 §4.1)

| 시나리오 | 커버 테스트 | 결과 |
|:---|:---|:---|
| 가입 → 프로필 | registrations #1 | ✅ |
| 프로필 저장 → /app | app/profiles #5·#6 | ✅ |
| 로그인(완료) → /app | sessions #12·app/profiles #10 | ✅ |
| 로그인(미완료) → 프로필 | sessions 기존 「올바른 자격 증명…」(변경 불요) | ✅ |
| 비인증 /app → 로그인 | registrations #3 + dashboards #1 | ✅ |
| /app 직접 접근(미완료) → 프로필 | dashboards #2 | ✅ |
| return_to 있음 + 미완료 → 프로필 우선 | sessions #13(/app 치환 후 재확인) | ✅ |
| `GET /welcome` → 소멸 | registrations 404 회귀 | ✅ |

## 4. 원인 분류 요약

- **갱신 과정 실패(모두 테스트 오류)**: ① `welcome_path`/`welcome_url` 헬퍼 소멸 NameError 13건 — 소멸 화면·구 목적지 참조, 신규 경로 치환으로 해소. ② `root_url` 폴백 변경 1건 — `app_root_url` 갱신. ③ robots `/welcome` 행 제거 1건 — 어설션 제거. ④ welcome noindex 화면 소멸 1건 — /app 대시보드 케이스로 대체.
- **코드 버그**: 0건. 구현(Phase 3·6)은 리다이렉트 표(03 §4.1)·DASH 빈 상태·가드 동작이 테스트 기대와 전부 일치.
- **시도 중 수정 사례**: welcome 소멸 회귀 테스트를 `assert_raises(ActionController::RoutingError)`로 작성했다가 Rails 8.1 통합 테스트는 미매칭 라우트를 404 응답으로 변환함을 실측(404 본문 확인)하여 `assert_response :not_found`로 정정 — 최종 통과.

## 5. Tester 자체 점검 체크리스트

- [x] 외부 API 실호출 0건
- [x] 테스트 소스 미사용 정의 0건 — `bin/rubocop` 0 offenses(54 files)
- [x] 들여쓰기 2칸(space) 준수
- [x] 기존 테스트 전체 회귀(`bin/rails test`) — 93 runs 0 failures
- [x] 랜딩 67건(앵커 순수성·h1·LP-10 푸터 등) 회귀 0건 — 레이아웃 분리 후에도 기존 어설션 유지 통과
- [x] 시스템 테스트: 이번 스코프(정적 셸·문구·가드)는 컨트롤러 통합 계층으로 충분 — 브라우저 여정은 F-INV 데이터 유입 시점에 신설 예정(05 리뷰 §3 스코프 노트 참조)

## 6. 후속 인계 노트

1. **F-INV 실데이터 전환점**: `dash_summary_cards`가 수치를 채우면 DASH-1 빈 상태 어설션(문구 3회·대시 3회·「0원」 부재)을 조건 분기 테스트로 교체해야 한다 — `test/controllers/app/dashboards_controller_test.rb` 단일 파일.
2. **ONB-1 CTA 활성화 시**: `button[disabled][aria-disabled=true]` 어설션을 실링크 어설션으로 교체(동일 지점).
3. **사이드바 청구서·거래처 메뉴 활성화 시**: `span[aria-disabled=true]` 2건·「준비 중」 배지 2건 어설션을 링크 어설션으로 교체.
4. 테스트는 `app_root_path`/`edit_app_profile_path` 등 라우트 헬퍼만 사용 — 하드코딩 경로는 welcome 404 회귀 테스트(`/welcome` 문자열)뿐(소멸 검증 목적).

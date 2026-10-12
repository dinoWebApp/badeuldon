# 07_test_report.md — F-CLIENT 거래처·품목 관리 테스트 (Phase 7)

- **일자**: 2026-10-12 · **작성자**: ClientTester
- **대상**: F-CLIENT 거래처(CLIENT-1)·품목(CLIENT-2)·PLAN-1 거래처 한도 + Phase 6 수정 4건 회귀
- **기준**: PRD v0.18.3 §6.3·§6.10·LP-12, `_workspace/03_implementation.md`(Phase 6 수정 이력), `_workspace/05_review.md`(「Tester 중점」)

## 실행 결과 요약

| 항목 | 결과 |
|:---|:---|
| 전체 회귀 `bin/rails test` | ✅ **156 runs, 935 assertions, 0 failures, 0 errors, 0 skips** |
| 이전 기준(03 §4) 대비 | 93 runs/1 failure → 156 runs/0 failure — **신규 63건 추가, 기존 실패 1건(사이드바) 해소** |
| `bin/rubocop` | ✅ 64 files inspected, **no offenses** (들여쓰기 2칸 포함) |
| 코드 버그 | **0건** — 발견 실패 2건 모두 테스트 오류로 자체 수정 후 통과(§ 실패 원인 분류) |
| 외부 API 실호출 | 0건 — F-CLIENT는 외부 API 미사용 기능(핵클·토스페이먼츠 호출 경로 자체가 없어 stub 불필요) |

## 변경 파일

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `test/fixtures/clients.yml` | 신규 | alpha 5개(PLAN-1 한도 도달 상태)·gamma 1개(CRUD 정상 경로)·beta 1개(소유권 404 대상) |
| `test/fixtures/items.yml` | 신규 | gamma·alpha·beta 각 1개 — 소유권 격리·목록 렌더 검증용 |
| `test/models/client_test.rb` | 신규 | 13건 — 필수·선택·연락처/이메일 형식·정규화·PLAN-1 한도·AUTH-1.5 |
| `test/models/item_test.rb` | 신규 | 11건 — 단가 경계 3종·빈 단가 1건·정규화·AUTH-1.5 |
| `test/controllers/app/clients_controller_test.rb` | 신규 | 23건 — CRUD 7종·소유권 404·PLAN-1 한도 UI·서버 게이트 |
| `test/controllers/app/items_controller_test.rb` | 신규 | 14건 — CRUD·단가 경계 HTTP 경로·소유권 404 |
| `test/controllers/app/dashboards_controller_test.rb` | 갱신 | 사이드바 테스트 갱신 + aria-current 분기 신규(§ 사이드바 갱신) |
| `test/integration/surf3_indexing_test.rb` | 갱신 | /app/clients·/app/items noindex 1건 추가 |

**코드 수정 없음** — 규칙 준수(발견 이슈 전무).

## 시나리오별 결과

### 거래처 CRUD (CLIENT-1)

| 시나리오 | 결과 | 근거 |
|:---|:---|:---|
| 필수·선택 6필드 등록 → 303·notice·6컬럼 DB 반영 | ✅ | clients_controller `필수·선택 6필드 등록은 303…` |
| 선택 3종 공백 등록 허용 → 303 | ✅ | `선택 3종 공백 등록은 303으로 성공한다` |
| 필수 누락 → 422 + 한글 오류 3종(role=alert li) | ✅ | `필수 누락 등록은 422와 필드별 한글 오류…` |
| phone 숫자만 허용·+82 거부(422 한글 오류) | ✅ | `연락처는 숫자만 입력도 허용하고…`(모델: 하이픈·지역번호·070 허용, 0505·자릿수 미달 거부) |
| 이메일 형식 오류 → 422 한글 오류 | ✅ | 컨트롤러 + 모델 각 1건 |
| 수정 303·DB 반영 / 수정 실패 422·기존값 보존 | ✅ | 각 1건 |
| 삭제 303·레코드 제거 + 목록·상세 turbo_confirm button_to 구조(`이 거래처를 삭제하시겠습니까?`) | ✅ | `삭제는 303…`·`목록·상세의 삭제 버튼은…` |
| 목록 카드·상세 전 필드 렌더 | ✅ | `목록은 거래처 카드에…`·`상세는 필수·선택 전 필드를…` |
| 비인증 302 로그인 / 프로필 미완료 → 프로필 화면 가드 | ✅ | 각 1건 |

### 소유권 격리

| 시나리오 | 결과 |
|:---|:---|
| 타 사용자 거래처 show·edit → 404 | ✅ (gamma → beta_secret) |
| 타 사용자 거래처 update·delete → 404 + 값 보존 | ✅ |
| 타 사용자 품목 show·edit / update·delete → 404 + 값 보존 | ✅ (2건) |

### PLAN-1 Free 거래처 한도

| 시나리오 | 결과 | 근거 |
|:---|:---|:---|
| 5번째까지 등록 성공, 6번째 422+「Free 플랜은 거래처 5개까지입니다」 | ✅ | `5번째까지는 등록되고 6번째부터 차단된다`(gamma 1→5 등장 경계) |
| 6번째 모델 등록 무효(base 오류)·4개→5번째 유효 | ✅ | client_test 각 1건 |
| 한도 도달 목록: 배너 + CTA 링크 소멸 + aria-disabled span | ✅ | `한도 도달 목록은 배너와 비활성 CTA로…`(li 5개 확인) |
| 한도 도달 등록 화면(직접 접근): 배너 + 저장 disabled·aria-disabled | ✅ | `한도 도달 등록 화면은…` |
| 한도 도달 POST → 422 + 한도 문구 li(서버 최종 게이트) | ✅ | `한도 도달 사용자의 6번째 등록 POST는…` |
| **create 실패 재렌더 배너·저장 비활성 유지(Phase 6 #2)** | ✅ | `한도 도달 상태의 등록 실패 재렌더에도…` — alert li 4건(필수 3종 + 한도 base) |
| 삭제 후 재등록 슬롯 회수(5개 유지) | ✅ | 컨트롤러 + 모델 각 1건 |
| 한도 도달 상태 수정 허용(on: :create) | ✅ | 컨트롤러 + 모델 각 1건 |
| 한도 문구 LP-12 준수(확정 보장·100% 표현 부재) | ✅ | `한도 오류 문구는 Plus 이용 가능성만 안내하고…` |

### 품목 · 단가 경계 (CLIENT-2 + Phase 6)

| 시나리오 | 결과 | 근거 |
|:---|:---|:---|
| CRUD: 등록 303·수정 303·삭제 303 + 목록·상세 렌더(tabular-nums 150,000원) + turbo_confirm | ✅ | items_controller 4건 |
| **음수 단가** → 422「단가는 0원 이상의 정수로 입력해 주세요」 | ✅ | 컨트롤러 + 모델 |
| **단가 0원 허용**(기본값 0·≥0) → 303 저장 0 | ✅ | 컨트롤러 + 모델 |
| **20자리("9"×20)** → **500(RangeError) 아닌 422**「단가는 1,000,000,000원 이하로 입력해 주세요」 | ✅ | 컨트롤러 + 모델(`RangeError가 아닌 검증 실패` — Phase 6 #1 CRITICAL 회귀) |
| 상한 경계: 1,000,000,000 허용 / +1 거부(MAX_UNIT_PRICE 상수 공유) | ✅ | 컨트롤러 + 모델 |
| **빈 단가 오류 1건만**(blank 중복 제거, not_a_number 부재) | ✅ | 모델 `errors[:unit_price] == [blank]` 정확 일치 + 컨트롤러 alert li 1건(Phase 6 #4) |
| 품목명 누락 422 / 소수("3.5")·비숫자("만원") 거부 / 품목명 strip | ✅ | 모델 4건 |

### 정규화 (Phase 6 #5)

| 시나리오 | 결과 |
|:---|:---|
| business_number `"  123-45-67890  "` → `"123-45-67890"` strip | ✅ |
| name·contact_name·phone strip / email strip+소문자 | ✅ |

### 기존 테스트 갱신 — 사이드바 (dashboards_controller_test)

| 시나리오 | 결과 |
|:---|:---|
| 사이드바: `aria-disabled` span **2→1**(청구서만), 「준비 중」 **2→1**, 거래처·품목 실링크(href) 렌더, 대시보드만 aria-current | ✅ — 기존 실패 1건 해소(03 §4 갱신 대상) |
| **aria-current 분기**: /app/clients에서 「거래처」·/app/items에서 「품목」 활성 표시 | ✅ — 신규 1건 |

### 회귀·비기능

| 시나리오 | 결과 |
|:---|:---|
| 대시보드·인증(세션/가입/비밀번호)·프로필·랜딩·메일러·health 기존 전체 통과 | ✅ 156 runs 0 failures |
| noindex /app/clients·/app/items meta robots(SURF-3) | ✅ surf3_indexing_test 1건 추가 |
| 사용자 삭제 시 거래처·품목 연쇄 삭제(AUTH-1.5) | ✅ 모델 2건 |

## 실패 원인 분류 (자체 수정 이력)

실행 과정에서 2건 실패 — **모두 테스트 오류**, 코드 버그 0건:

1. `한도 도달 상태의 등록 실패 재렌더…`(alert li 3건 기대 → 4건 실측): 한도 도달 상태의 blank 제출은 필수 3종 오류 **+ 한도 base 오류**가 함께 노출되는 것이 올바른 동작(서버 게이트 유지 확인). 기대치 4건으로 수정 + 한도 문구 li 추가 어설션.
2. `목록은 거래처 카드에 등록 정보를 렌더한다`(「감과장 담당」을 `dd`에서 탐색): 카드의 담당자 표기는 `<p>` 요소. 셀렉터 `dd`→`p` 수정.

수정 후 해당 파일 재실행 23 runs 0 failures → 전체 재실행으로 확정.

## 자체 점검 (Tester 체크리스트)

- [x] Rule ID별 정상·경계·예외 시나리오 커버(CLIENT-1·2, PLAN-1, LP-12, AUTH-1.5, SURF-3)
- [x] 외부 API 실호출 0건(대상 기능에 호출 경로 자체 없음)
- [x] 테스트 소스 미사용 정의 0건 — `complete_profile_of` 6곳 사용, `new_valid_client` 사용 확인 / RuboCop 0 offenses
- [x] 기존 테스트 전체 회귀 통과(156 runs, 0 failures — 이전 실패 1건 포함 해소)
- [x] fixtures 표준 세트 유지: alpha 5거래처(한도용)·gamma·beta, 품목 3건, 금액 정수(원)
- [x] 코드 수정 0건 — 검증 실패·UI 문제 전무(Phase 6 수정분 4건 모두 실측 통과)

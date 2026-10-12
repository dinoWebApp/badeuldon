# 03_implementation.md — F-CLIENT 거래처·품목 관리 구현

- **일자**: 2026-10-12
- **구현 기준**: `_workspace/01_plan.md`(승인 플랜) · PRD v0.18.3 §6.3(CLIENT-1·2)·§6.10(PLAN-1)
- **응답 전략**: 페이지 전환(§7.3 — "페이지 이동은 Turbo Drive 기본") 선택. 생성·수정·삭제 성공 303 리다이렉트, 실패 422 재렌더. Turbo Frame/Stream 미도입(리포지터리 첫 Frame 사용 시점이 아니므로 보수적 선택, 향후 F-INV 폼에서 Frame 검토 여지)

## 1. 변경 파일

### 신규 (14)
| 파일 | 내용 |
|:---|:---|
| `db/migrate/20261012000002_create_clients.rb` | clients 테이블 — user_id FK(null:false·인덱스), name·contact_name·phone null:false, email·business_number·memo 선택 |
| `db/migrate/20261012000003_create_items.rb` | items 테이블 — user_id FK(null:false·인덱스), name null:false, unit_price integer null:false default 0 |
| `app/models/client.rb` | Client 모델 — 검증·PLAN-1 한도(아래 §3) |
| `app/models/item.rb` | Item 모델 — name presence, unit_price 정수 ≥0 |
| `app/controllers/app/clients_controller.rb` | 거래처 7종 표준 CRUD — 소유권 스코프 `Current.user.clients` |
| `app/controllers/app/items_controller.rb` | 품목 7종 표준 CRUD — 동일 패턴, 한도 없음 |
| `app/views/app/clients/index.html.erb` | 목록(카드형)·빈 상태·한도 배너·CTA 비활성 |
| `app/views/app/clients/_client.html.erb` | 거래처 카드 — 이름·담당자·연락처 + 선택 요약(이메일·사업자번호·메모) + 수정/삭제 |
| `app/views/app/clients/show.html.erb` | 상세 — 전 필드 dl + 편집·삭제(CLIENT-3 확장 여지) |
| `app/views/app/clients/new.html.erb` / `edit.html.erb` / `_form.html.erb` | 등록·수정 — 공용 폼(필수 3종+선택 3종), 한도 시 저장 비활성 |
| `app/views/app/items/index.html.erb` / `_item.html.erb` / `show.html.erb` / `new.html.erb` / `edit.html.erb` / `_form.html.erb` | 품목 CRUD 화면 — 단가 tabular numerals(DESIGN-3) |

### 수정 (4)
| 파일 | 내용 |
|:---|:---|
| `app/models/user.rb` | `has_many :clients/items, dependent: :destroy`(AUTH-1.5 탈퇴 시 삭제) |
| `app/helpers/app/base_helper.rb` | ① 사이드바 「거래처」 실링크 활성화 + 「품목」 메뉴 신규(설정 위) ② 폼 필드 공통 클래스 `form_input_classes`·`form_error_message` 추가(프로필 화면 `profile_input_classes`와 동일 문법) |
| `config/routes.rb` | `namespace :app`에 `resources :clients`, `resources :items` |
| `config/locales/en.yml` | client·item 검증 오류 한글 문구(기존 user 패턴과 동일 위치) |

`db/schema.rb` — 마이그레이션 실행으로 자동 갱신(version 2026_10_12_000003).

## 2. Rule ID 매핑

| Rule ID | 구현 위치 |
|:---|:---|
| **CLIENT-1** | 거래처 CRUD 전체 — clients 컨트롤러 7종 + 뷰 6종. 필수 3종(거래처명·담당자명·알림 수신 휴대폰 번호)/선택 3종(이메일·사업자번호·메모)은 PRD 필드 그대로 |
| **CLIENT-2** | 품목 라이브러리 CRUD — items 컨트롤러·뷰. 품목명·단가만 저장(PRD 명시 필드 외 추가 금지). 청구서 선택 UI는 F-INV 후속 |
| **PLAN-1** | Free 거래처 5개 한도 — 아래 §3 |
| **AUTH-1.5** | `User has_many :clients/:items, dependent: :destroy` — 탈퇴 시 데이터 삭제 |
| **DESIGN-3** | 금액 tabular numerals — 품목 카드·상단 단가(`tabular-nums`), 사업자번호 표기 |
| **DESIGN-4** | 표면 ② 정보 밀도·장식 최소 — 대시보드 카드 문법(rounded-2xl·stone 보더·white) 재사용 |
| **DESIGN-5** | 단가 큰 숫자 카드(text-2xl/3xl font-extrabold), 빈 상태 카드형 CTA |
| **DESIGN-6** | 모든 인터랙션 min-h-11(44px) 터치 타깃, focus-visible 링·트랜지션 |
| **SURF-3** | /app 하위 신규 경로 — `App::BaseController` 상속으로 noindex·레이아웃·가드 체인(require_authentication·require_complete_profile) 상속. `public/robots.txt`의 `Disallow: /app`이 하위 경로 포함(기존 유지) |
| **LP-12** | 한도 안내 문구 — 확정 보장 없이 Plus 이용 가능성만 안내(「무제한 이용할 수 있습니다」) |

## 3. PLAN-1 한도 구현 위치 (단일 지점)

- **상수**: `Client::FREE_CLIENT_LIMIT = 5` (`app/models/client.rb`) — F-PLAN에서 구독 체크로 교체할 때 이 상수와 `free_plan_client_limit` 검증만 수정하면 된다.
- **검증 지점(서버 최종 게이트)**: `Client#free_plan_client_limit` — `on: :create` 한정(수정은 자유), `user.clients.count >= FREE_CLIENT_LIMIT`면 base 오류 「Free 플랜은 거래처 5개까지입니다. Plus로 무제한 이용할 수 있습니다」. 메시지의 "5"도 상수 보간.
- **UI 분기(동일 상수 공유)**: `App::ClientsController` index·new에서 `@limit_reached` 산출 → 목록 배너 + CTA 비활성(`aria-disabled`), 등록 폼 저장 버튼 비활성. 클라이언트 비활성화는 UX 보조일 뿐, 실제 차단은 모델 검증.
- 한도 도달 직접 접근(`/app/clients/new`)에서도 배너 + 비활성 폼, 서버 저장 시 422 + 동일 문구.

## 4. 실패 예상(확인된) 기존 테스트 — Phase 7 갱신 대상

`bin/rails test` 결과: **93 runs, 603 assertions, 1 failures, 0 errors**

| 테스트 | 위치 | 사유 |
|:---|:---|:---|
| `사이드바는 대시보드 활성 표시·준비 중 메뉴·설정 실링크를 렌더한다` | `test/controllers/app/dashboards_controller_test.rb:75`(84·86·87행 어설션) | 거래처가 `aria-disabled` 준비 중 배지 → 실링크로 전환되어 `nav span[aria-disabled='true']` 2→1, `/거래처/` 배지 0, 「준비 중」 2→1. 사이드바 활성화의 의도된 변경 — Phase 7에서 「거래처·품목 실링크 + 청구서만 준비 중」으로 갱신 필요 |

기존 테스트 파일은 수정하지 않았다(계약 준수).

## 5. 자체 점검 결과

| 항목 | 결과 |
|:---|:---|
| `bin/rails db:migrate` | ✅ 성공 — clients·items 생성, `db/schema.rb` version 2026_10_12_000003 갱신 |
| `bin/rails zeitwerk:check` | ✅ "all is good" |
| `bin/rubocop` | ✅ 60 files inspected, no offenses |
| `bin/rails test` | ✅ 93 runs — 위 §4의 1건만 실패(의도된 사이드바 변경) |
| 액션 10줄 이내·`params.expect`·303/422·소유권 스코프 | ✅ 두 컨트롤러 모두 적합 |
| 뷰 쿼리 금지 | ✅ 뷰는 @변수·헬퍼만(`@limit_reached`는 컨트롤러 산출), `raw`/`html_safe` 없음 |
| 삭제 안전 | ✅ `button_to` + `turbo_confirm` 확인 대화상자 |

## 6. 후속 제외 확인 (이번 미구현 — 계획대로)

CLIENT-3(거래처 카드·누적 청구액)/CLIENT-4(지급 성적표) — F-INV·F-PAY 데이터 의존. 품목 선택 UI — F-INV. 거래처 삭제 시 청구 정책 — 참조 없는 현재 즉시 삭제(승인 해석), F-INV에서 INV-6 연계 확정. 플랜 구독 체크 — F-PLAN(상수 교체 지점 §3).

## 수정 이력 (Phase 6)

Phase 5 리뷰(`05_review.md`) 이슈 4건만 최소 수정 — CRITICAL 1 + WARNING 3. 미수정 확정: #3(동시성 비원자 — F-PLAN 시점 with_lock/직렬화), #6(보조 인터랙션 focus-visible — 화면 확장 시 통일).

| 리뷰 이슈 | Rule ID | 수정 내용 | 파일 |
|:---|:---|:---|:---|
| #1 CRITICAL | CLIENT-2 | 단가 상한 검증 추가 — `MAX_UNIT_PRICE = 1_000_000_000` 상수를 모델(`less_than_or_equal_to:`)·뷰(`max:`)가 공유. 거대 단가가 저장 단계 RangeError(500) 대신 검증 실패(422)로 전환 | `app/models/item.rb` · `app/views/app/items/_form.html.erb`(new/edit은 공용 폼 사용) |
| #2 WARNING | PLAN-1 | create 실패 재렌더 분기에 `@limit_reached` 재산출(index·new와 동일 식) — 실패 화면에서도 배너·저장 버튼 상태 일관 | `app/controllers/app/clients_controller.rb` |
| #4 WARNING | — | numericality에 `allow_blank: true`(presence가 blank 담당) — 빈 단가 시 blank 오류 1건만 출력 | `app/models/item.rb` |
| #5 WARNING | CLIENT-1 | `normalizes`에 `business_number` 추가(strip) — F-TAX(팝빌) 매칭 대비. memo는 다중행 텍스트로 제외 유지 | `app/models/client.rb` |

**수반 변경(이슈 #1 필수 수반)**: `config/locales/en.yml`에 `item.unit_price.less_than_or_equal_to` 한글 문구 추가(「단가는 1,000,000,000원 이하로 입력해 주세요.」). 신규 검증 키의 문구가 없으면 기본 영문 메시지가 노출되므로 기존 item·client 문구 관례(en.yml 한글 처리)에 맞춤. YAML은 상수 참조가 불가해 수치를 상수와 짝 맞추는 주석으로 표기.

**실측 결과**(`bin/rails runner`, 롤백 트랜잭션 — 종료 시 `users=1 items=0 clients=0` 무변경 확인):

| 항목 | 결과 |
|:---|:---|
| 20자리 단가("9"×20) | ✅ `valid?=false` + 「단가는 1,000,000,000원 이하로 입력해 주세요.」, `save=false` — RangeError 미발생(500 아님, 422 검증 실패) |
| 빈 단가 | ✅ 오류 1건만 「단가를 입력해 주세요.」(blank+not_a_number 중복 제거) |
| business_number 공백 | ✅ `"  123-45-67890  "` → `"123-45-67890"`, nil/공백 전용 입력도 예외 없이 정규화 |
| #2 판정식 | ✅ 컨트롤러와 동일 식 `count >= FREE_CLIENT_LIMIT` 산출 확인(보유 0개 → false) |
| `bin/rubocop` | ✅ 60 files inspected, no offenses |
| `bin/rails zeitwerk:check` | ✅ all is good |

기존 테스트 파일은 수정하지 않았다(계약 준수 — Phase 7 갱신 대상 유지). 서버 기동·신규 테스트 작성 없음.

# 05_review.md — F-CLIENT 거래처·품목 관리 (Phase 5 코드 리뷰)

- **일자**: 2026-10-12 · **리뷰어**: ClientReviewer
- **대상**: `_workspace/03_implementation.md` 변경분 — 마이그레이션 2 · 모델 2 · User 연관 · 컨트롤러 2 · 뷰 12 · base_helper · routes · en.yml · schema
- **기준**: PRD v0.18.3 §6.3(CLIENT-1·2)·§6.10(PLAN-1)·LP-12 · AGENTS.md UI 품질 기준 · ARCHITECTURE_CONVENTION
- **검증 방법**: 정적 리뷰 + `bin/rails runner` 실증 프로브(롤백 트랜잭션 — DB 무변경 확인: `users=1 clients=0 items=0`)

## Status: CHANGES_REQUESTED

CRITICAL 1건(사용자 입력값으로 500 유발) — 수정 후 해당 건만 재확인이면 된다. 나머지는 WARNING(수정 권장, Phase 7 병행 가능).

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | **CRITICAL** | CLIENT-2 (데이터 품질) | `app/models/item.rb:7-8` | **거대 단가 입력 시 422가 아닌 500 발생(실증)**. `numericality: { only_integer: true, greater_than_or_equal_to: 0 }`에 상한이 없어 20자리 숫자("9"×20)는 검증을 통과하고, 저장 시 `ActiveModel::RangeError: … out of range for SQLite3`로 500. 폼의 `number_field`(min:0, step:1만 지정, `_form.html.erb:28`)도 max 미지정이라 브라우저에서 그대로 입력 가능. 데이터 오염은 없으나(트랜잭션 롤백) 일반 입력 경로에서 트리거 가능한 미처리 예외 | `numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_UNIT_PRICE }` 상수 상한 추가(예: `1_000_000_000` — 비즈니스 상한, 향후 PostgreSQL 전환 시 int4 한도 문제도 동시 예방). 뷰 `max:`도 동일 상수 지정 |
| 2 | WARNING | PLAN-1 (UX 정합) | `app/controllers/app/clients_controller.rb:18-25` | `create` 실패 재렌더(`render :new`) 시 `@limit_reached` 미산출 → 배너 누락·저장 버튼이 활성으로 표시. 우회 POST 등으로 한도 초과 저장이 실패한 화면에서 UI가 "저장 가능"처럼 보임(실제 서버 게이트는 모델 검증으로 계속 422 차단 — 데이터 무결성 영향 없음) | 실패 분기에 `@limit_reached = Current.user.clients.count >= Client::FREE_CLIENT_LIMIT` 추가 |
| 3 | WARNING | PLAN-1 (동시성) | `app/models/client.rb:24-29` | 한도 검사가 count-후-insert 비원자. 동시 create 2건이 count=4를 모두 관측하면 6번째+7번째 동시 삽입 가능. 악용 주체가 계정 소유자 본인뿐(타 사용자 데이터 무관)이고 F-PLAN에서 구독 체크로 재작업 예정이라 WARNING | 즉시 수정보다 F-PLAN 전환 시 `user.with_lock`(SELECT…FOR UPDATE) 또는 유사 직렬화로 해결 명시. 급하면 검증 내 `User.lock.find(user.id)` 후 count |
| 4 | WARNING | — (UX 사소) | `app/models/item.rb:7-8` | 빈 단가 제출 시 `blank` + `not_a_number` 오류 2건 동시 출력(실증: "단가를 입력해 주세요. \| 단가는 0원 이상의 정수로…"). 폼 상단 경고 박스에 중복 메시지 노출 | `numericality`에 `allow_blank: true` 추가(presence가 blank 담당) |
| 5 | WARNING | CLIENT-1 (데이터 위생) | `app/models/client.rb:18-19` | `normalizes :name, :contact_name, :phone, :email`만 strip하고 `business_number`(·`memo`)는 미정규화. " 123-45-67890"가 공백 채 저장 — F-TAX(팝빌 사업자번호 매칭) 시점에 정확 매칭 방해 | `business_number`를 normalizes 대상에 추가(`memo`는 다중행 텍스트라 현행 유지 가능) |
| 6 | WARNING | DESIGN-6 (경미·확인 요청) | `app/views/app/clients/_client.html.erb:38-42` 외 신규 뷰 보조 액션 전반 | 보조 인터랙션(카드 수정·삭제, 취소, "← 목록" 링크)에 `focus-visible` 링 없음 — 기본 UA 포커스 링은 동작하므로 접근성 결함은 아니나, 기존 primary 액션 관례(명시 링)와 상세 수준 불일치 | 향후 화면 확장 시 보조 액션에도 `focus-visible:outline-*` 추가 통일(이번 필수 수정 아님) |

**이슈 아님 — 확인 기록**: 거래처 phone 정규식 `\A\d{2,3}-?\d{3,4}-?\d{4}\z`는 기존 `user.rb:19`(프로필 연락처)과 동일한 repo 관례이며 010/지역/070 수용(실증), 0505·+82·끊긴 번호 거부 — PRD "휴대폰 번호" 필드 관점 타당. 모델 길이 검증 부재(HTML maxlength만)도 기존 user 모델과 동일 관례(현행 SQLite에 255 초과 무해). 사이드바 기존 테스트 1건 실패는 명세 이행분(`03_implementation.md` §4 — Phase 7 갱신 대상).

## Rule ID 준수 매핑

| Rule | 판정 | 근거 |
|:---|:---|:---|
| **CLIENT-1** (필드 1:1) | ✅ | PRD §6.3 121행 원문 — 거래처명·담당자명·알림 수신 휴대폰(필수) / 이메일·사업자번호·메모(선택). 마이그레이션·모델·폼·상세 전부 6필드 정확 대응, **추가·누락 없음**(user_id·timestamps는 인프라) |
| **CLIENT-2** (품목명·단가만) | ✅ 구조 | items는 name + unit_price(integer)만 — 과잉 필드 없음. 단 상한 미검증이 이슈 #1 |
| **PLAN-1** (거래처 5개) | ✅ (이슈 #2·#3 예외) | 상수 단일 지점 `Client::FREE_CLIENT_LIMIT=5` — 모델 검증(최종 게이트)·뷰 배너·CTA 비활성이 동일 상수 공유. **실증**: 6번째 create 422 + "Free 플랜은 거래처 5개까지입니다…", 한도 도달 수정 허용(행 증가 없음 — 우회 아님), 삭제 후 재등록 허용, `/app/clients/new` 직접 접근 배너+저장 비활성 |
| **AUTH-1.5** (탈퇴 삭제) | ✅ | `has_many :clients/items, dependent: :destroy`(user.rb:5-6) |
| **LP-12** (문구) | ✅ | "Plus로 무제한 이용"은 PLAN-2 명세상 사실(무제한 청구·거래처) — 회수 확정 보장·압박 표현 없음 |
| **SURF-3** (noindex) | ✅ | `App::BaseController` 상속 → app 레이아웃 → `_head`의 `noindex?` meta + robots.txt `Disallow: /app`(하위 경로 포함) |
| **DESIGN-3/4/5/6** | ✅ (이슈 #6 경미) | 단가 `tabular-nums`+큰 숫자 카드, 사업자번호 tabular-nums · 대시보드 카드 문법(rounded-2xl·stone 보더·white·shadow-sm) 재사용 · 빈 상태 카드형 CTA · primary 액션 `min-h-11`+focus-visible |
| **보안·소유권** | ✅ | 두 컨트롤러 전 액션이 `Current.user.clients/items` 스코프(index·build·find) — 타 사용자 id는 `ActiveRecord::RecordNotFound`·`raw`/`html_safe` 불사용·로그 민감정보 없음 |
| **아키텍처** | ✅ | 액션 전부 10줄 이내 · `params.expect` 화이트리스트(6+2필드) · 성공 303/실패 422 · 뷰에 쿼리 없음(`FREE_CLIENT_LIMIT` 상수 참조만 — 쿼리 아님) · `App::BaseController` 상속으로 가드·레이아웃 체인 · 한도 검증 위치=모델(서버 최종 게이트)+컨트롤러는 UI 분기만 — 타당 |
| **마이그레이션** | ✅ | null:false 명시(필수 3종+user_id) · FK·`index_clients_on_user_id`/`index_items_on_user_id` · 단가 정수 원 단위(부동소수 금지) · schema.rb 동기화(2026_10_12_000003) |
| **범위 준수** | ✅ | 플랜 명시 23파일 외 코드 변경 없음 · CLIENT-3/4·품목 선택 UI 미구현 확인(거짓 수치·플레이스홀더 데이터 없음 — 상세 화면은 등록 정보만) |

## 한도 우회 경로 검증 (논리적·실증)

| 우회 경로 | 결과 |
|:---|:---|
| 수정(update)으로 우회 | ✅ 불가 — 검증 `on: :create`는 행 신규 생성만 대상, update는 행 수 불변. 한도 도달 상태의 수정은 정상 허용(실증 D2) |
| 6번째 create 직접 POST (버튼 비활성 우회) | ✅ 차단 — 모델 검증 422 + 동일 문구(실증 D1). 단 재렌더 UI 상태가 이슈 #2 |
| 대량 생성(벌크/임포트 엔드포인트) | ✅ 경로 부재 — 라우트는 표준 7종만, 컨트롤러는 단일 build |
| 삭제 후 재등록 | ✅ 올바른 동작 — 슬롯 회수 후 재등록 허용(실증 D3, 5개 재유지) |
| 동시성 경쟁 | ⚠️ 이론상 우회 가능(이슈 #3) — count-후-insert 비원자, 본인 계정 이득만 가능·피해 한도 1~2개 초과 |
| 플랜 미조회 우회 | ✅ 해당 없음 — F-PLAN 전 전 사용자 Free 취급은 승인된 해석(02_prd_update) |

## Tester에게 제안하는 중점 테스트 영역

1. **PLAN-1 한도 시나리오**(최우선): 5개 등록 성공 → 6번째 UI(배너·CTA·저장 비활성) → 직접 POST 422+문구 → 1개 삭제 → 재등록 성공 → 수정은 항상 허용. 이슈 #2 반영 후: 한도 초과 실패 재렌더에서 배너·버튼 상태 일관성
2. **품목 단가 경계**(이슈 #1 반영 후): 음수·"3.5"·비숫자 → 422 문구 / 거대값(20자리) → 422(수정 전 500으로 결함 입증 가능) / 0원 유효 / 빈값 메시지(이슈 #4)
3. **소유권 격리**: 사용자 A로 로그인해 B의 client·item id로 show/edit/update/delete 직접 요청 → 404 (7종 전 액션)
4. **CRUD 정상 경로**: 303 리다이렉트·notice 문구·목록 반영·삭제 turbo_confirm, CLIENT-1 필수 3종 누락 시 필드별 오류(이메일 형식·연락처 형식 포함)
5. **사이드바 명세 갱신**(기존 실패 1건): 거래처·품목 실링크+활성 표시, 청구서만 `aria-disabled` 준비 중 — `dashboards_controller_test.rb:75` 어설션 갱신
6. **AUTH-1.5**: 사용자 삭제 시 거래처·품목 연쇄 삭제
7. **회귀**: 대시보드·프로필 기존 92건 통과 유지(구현 보고 기준)

# T4 — 솔라피 잔액 모니터링 구현 내역 (ADMIN-5·REM-10)

배치: 기능 잔여·기술 부채 병렬 배치 (§6.14 fan-out) — 2026-11-20
범위: 솔라피 래퍼 `get_balance` + ADMIN-5 운영 대시보드 잔액 표시 + 라이브 실측([INFERENCE] 해소)

## Rule ID 매핑

| Rule ID | 구현 |
|:---|:---|
| ADMIN-5 | 운영 대시보드 메시지 발송 지표 영역에 솔라피 잔액 표시(5분 캐시·임계치 주황 경고·조회 실패 fallback) |
| REM-10 | 선불 크레딧 잔액 조회 래퍼 — "크레딧 소진으로 인한 발송 중단이 발생하지 않도록 잔액 모니터링"의 API 계층 |
| P4 무관성 확인 | balance는 읽기 전용 조회 — 발송 이력(SEC-5 멱등·PLAN-3 상한)·MessageLog 적용 대상 아님(래퍼 주석 명시) |

## 생성/수정 파일

| 파일 | 변경 |
|:---|:---|
| `app/services/solapi/client_service.rb` | 수정 — `get_balance`·`BALANCE_PATH`·`NET_REQUEST_CLASSES`(GET 지원)·`parse_balance`·`parse_amount` 추가, 헤더 주석에 잔액 조회 섹션 신설 |
| `app/controllers/admin/dashboards_controller.rb` | 수정 — `load_solapi_balance`(캐시·fallback) 추가, `load_metrics`에 1줄 위임 |
| `app/helpers/admin/dashboards_helper.rb` | **신규** — `LOW_BALANCE_THRESHOLD`·`solapi_balance_text`·`solapi_balance_value_class`·`solapi_balance_low?` |
| `app/views/admin/dashboards/show.html.erb` | 수정 — 메시지 발송 지표 행에 "솔라피 잔액" 추가, 기존 "기술 부채" 각주를 실제 표시 안내로 교체 |

## ① 래퍼 `get_balance`

- `GET /cash/v1/balance` — 단일 발송(POST /messages/v4/send)과 **동일 HMAC-SHA256 Authorization 헤더**(signature = HMAC(api_secret, date + salt)) 재사용. 기존 `build_request`는 Post 하드코딩이라 `NET_REQUEST_CLASSES = { get: ..., post: ... }` 맵으로 확장(미지원 메서드는 KeyError fail-fast).
- `ensure_credentials!(require_pf_id: false)` — 잔액 조회에 pf_id 불요(발송 채널 파라미터 아님).
- 반환 정규형: `{ balance: Integer(원), point: Integer }`.
- **방어적 파싱**: `balance` 키 누락·null·비숫자(숫자형 문자열 "12,345"은 콤마 제거 후 정수 허용)는 `ApiError(code: "UNEXPECTED_BALANCE_RESPONSE")` fail-fast — 잘못된 잔액을 정상처럼 표시하는 것을 차단. `point`는 부여 크레딧 없는 계정 기본 0으로 관대 정규화.
- 네트워크·응답 오류는 기존 `request`→`parse`의 ApiError 정규화(TIMEOUT/CONNECTION/HTTP_xxx)를 그대로 상속.
- stub 주입: 기존 패턴 동일 — ActiveRecord 비의존 순수 클래스, 응답 Hash를 `request` 레벨에서 stub 가능(테스트 작성은 본 태스크 금지 — Tester 런으로 이관).

## ② ADMIN-5 대시보드 표시

- **컨트롤러**(`load_solapi_balance`): 래퍼 호출 + 캐시만 담당(10줄 규약 — 액션 `show`는 `load_metrics` 1줄 호출 유지, private 위임). 뷰→쿼리 금지 위반 없음(@변수만 전달).
- **캐시 설계**: 성공 5분(`Rails.cache` — production Solid Cache·development memory_store·test null_store를 태움), **실패 1분 단기 캐시**(`:unavailable` 센티널 — 캐시 없음(nil)과 구분). 실패를 캐시하는 이유: 잔액 API 장애 중 대시보드 새로고침마다 외부 호출(타임아웃 최대 10s×open/read)이 누적되는 낙수 방지. 1분으로 짧게 해 복구 지연은 최소화.
- **fallback**: `Solapi::ApiError` rescue → `Rails.logger.warn`(code·message 진단 보존) → 뷰에 nil → 헬퍼가 "일시 조회 불가"(중립 회색) 표시. 대시보드 500 없음.
- **임계치**: `LOW_BALANCE_THRESHOLD = 50,000원` — 미만 시 값 주황(`text-orange-600`)+ "충전 필요" 배지(`bg-orange-100`·경고 상태색 계열, admin 표면 기존 실패 카운트 주황 표기와 동일 팔레트). 경계값(=50,000)은 정상 판정(미만 조건).
- **헬퍼 신설 근거**: 임계치 상수·조건 분기가 표현 로직(뷰 직접 비교 금지 — AGENTS "표현 로직 3줄+ 는 헬퍼로")이라 화이트리스트의 "관련 admin 헬퍼"로 `Admin::DashboardsHelper` 신설. admin 헬퍼 파일은 기존 부재(신설이 최초).
- 뷰 각주 교체: "※ 솔라피 크레딧 잔액은 로컬 집계에 미포함(라이브 실측 전 — 기술 부채)" → 실제 잔액 표시 안내(캐시·임계치·fallback 문언). 기술 부채 해소에 따른 청산.

## ③ 라이브 실측 결과 (2026-11-20 — 이 태스크만 허용된 읽기 전용·무료 호출)

`bin/rails runner`로 `Solapi::ClientService.new.get_balance` 1회 실호출(운영 credentials):

- **[INFERENCE] 전면 해소** — 실측 확정 스키마:
  - 요청: GET `https://api.solapi.com/cash/v1/balance` + 동일 HMAC Authorization 헤더 → **200**
  - 응답 본문: `{"balance": <정수(원)>, "point": <정수>}` 단일 객체(symbolize 후 `[:balance, :point]`)
  - 타입: balance·point 모두 `Integer`(원 단위 정수 — 콤마·소수 없음)
  - point는 부여 크레딧 없는 계정 기준 `0` 관측
- 잔액 값(마스킹): `7*6*`원(4자리 — 1천원대). **50,000원 임계치 미만 → 운영 계정이 현재 주황 "충전 필요" 상태로 표시된다. 잔액 충전 필요(운영 액션 — 발송 중단 방지 REM-10 취지).**
- 코드 반영: 래퍼 `get_balance`·`BALANCE_PATH` 주석을 실측 확정 문언으로 갱신(기존 send 실측 기록 선례와 동일 방식). [INFERENCE] 마킹 잔존 없음.

## 검증 (fan-out 제약 내)

- `bin/rubocop` 3개 .rb 파일 — **0 offenses**. (.erb는 rubocop-omakase Include 밖 — 명시적 파일 지정 시에만 Ruby로 오파싱되는 환경 특성, bin/ci 대상 아님 확인)
- `bin/rails runner` 스모크(테스트 파일 아님·외부 호출 없음): 헬퍼 표현 로직 8케이스(nil·임계치 경계 49,999/50,000·정상색·통화 포맷) + 컨트롤러 실패 fallback 경로(TIMEOUT stub → nil + :unavailable 1분 캐시 → 재호출 시 캐시 재사용으로 외부 호출 차단) 전부 통과. 헬퍼 모듈 `Admin::DashboardsHelper` zeitwerk 상수 해석도 runner 부트에서 확인.
- 전체 테스트·zeitwerk:check·마이그레이션·커밋 — fan-out 제약으로 미수행(병렬 태스크의 미완료 파일 오차단). Tester 런에서 `Solapi::ClientService` stub 주입 테스트와 대시보드 통합 테스트로 커버 예정.

## 운영 노트

- 잔액은 대시보드 로드 시점 기준 5분 이내 값 — 즉시성이 필요하면 캐시 수동 삭제(`Rails.cache.delete("admin/dashboards/solapi_balance")`).
- 임계치 50,000원은 래퍼가 아닌 헬퍼에 둠 — 발송 단가 변동·다중 표면(잡 알림 등) 재사용 시 상수 이동 검토.
- 남은 기술 부채: 없음(ADMIN-5 잔액 [INFERENCE] 소멸). 본 태스크는 발송(write) API를 전혀 호출하지 않음.

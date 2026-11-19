# 03_implementation — 병렬 배치 태스크 A: 경량 정리 묶음 (2026-11-16)

소유권 화이트리스트 내에서만 수정. 테스트 미실행(3-S 이후 게이트) · git 커밋 없음.

## 변경 파일 목록

| 파일 | 변경 |
|---|---|
| `config/deploy.yml` | env.clear에 `CACHE_CONTROL` 추가 |
| `config/locales/en.yml` | 한국어 잔존 블록 전면 제거 → `en: ~` 골격 + 주석 |
| `config/locales/en.yml.bak` | 수정 전 원문 백업 — **커밋 대상 아님(로컬 보존 전용)**, .gitignore 추가 권장 |
| `app/javascript/controllers/hello_controller.js` | 삭제(scaffold 잔존) |
| `app/javascript/controllers/portone_shared.js` | 신설 — SDK 가드·customer 조립 공통 헬퍼 |
| `app/javascript/controllers/portone_payment_controller.js` | 공통부를 portone_shared로 위임(동작 동일) |
| `app/javascript/controllers/portone_billing_controller.js` | 공통부를 portone_shared로 위임(동작 동일) |
| `app/javascript/controllers/index.js` | 수정 없음 — eagerLoadControllersFrom 방식이라 hello 등록 라인이 원래 없음(파일 삭제만으로 충분) |

## 작업 1 — 폰트 장기 캐시 헤더 (W-3)

- `deploy.yml` env 블록에 `CACHE_CONTROL: "public, max-age=31536000, immutable"` 추가(env.clear — Kamal 표준 구조, secret과 병존).
- Thruster는 `CACHE_CONTROL` 환경변수로 정적 서빙 응답의 Cache-Control 헤더를 제어한다.

### 폰트 서빙 경로 확인 결과
- 실제 경로: **`public/fonts/PretendardVariable.woff2`** (2,057,688 bytes) — `@font-face`는 `app/assets/tailwind/application.css`에서 `/fonts/PretendardVariable.woff2`로 직접 참조(레이아웃 `_head.html.erb` 주석과 일치).
- Thruster는 `public/` 전체를 정적 서빙하므로 **폰트는 Thruster 정적 서빙 대상 맞음** — 위 CACHE_CONTROL이 적용된다.
- 주의: 폰트 파일은 digest(fingerprint)가 없다. 헤더가 immutable이므로 **폰트 교체 시 파일명 변경(예: 버전 접미) 필요** — deploy.yml 주석에도 명기.

### CF 엣지 Cache Rule 권장 설정 (사용자 수동 항목)
- 대상: `badeuldon.kr/assets/*` 및 `badeuldon.kr/fonts/*`
- 캐시 상태: "Cache Everything", Edge TTL: 1개월~1년(Edge Cache TTL 31536000 권장)
- Browser TTL: 31536000(Origin의 Cache-Control 상속도 가능 — Origin이 이미 immutable을 보내므로 "Respect origin"이 가장 단순)
- `/b/*`·`/app`·`/admin`은 캐시 제외(Bypass) — 대시보드·뷰어는 동적 응답
- 참고: CF 프록시 기본 동작상 html은 캐시하지 않으므로 룰은 정적 경로 한정 유지 권장

## 작업 2 — en.yml 잔존 구조 정리

- 제거 대상: `activerecord.errors.models.{user,client,item,invoice,invoice_item}` 전체 한국어 블록(en.yml 33~116행) + scaffold 키 `hello: "Hello world"`(뷰·코드 미사용 확인).
- 사전 교차 확인: 해당 블록 전체가 `ko.yml`에 이미 동일 키·동일 문구로 이식되어 있음을 대조 확인(누락 0건) — **ko.yml 수정 불요**.
- `default_locale=:ko` 확인(`config/application.rb`).
- 제거 키 목록(모두 ko.yml에 존재 — 회귀 없음):
  - user: email.blank/taken, password.blank/password_too_long, password_confirmation.confirmation, display_name.blank, business_type.blank, phone.invalid, account_number.invalid
  - client: name.blank, contact_name.blank, phone.blank/invalid, email.invalid
  - item: name.blank, unit_price.blank/not_a_number/not_an_integer/greater_than_or_equal_to/less_than_or_equal_to
  - invoice: client.required, client_id.blank, due_on.blank, bank_name.blank, account_number.blank, account_holder.blank, base.total_amount_must_be_positive
  - invoice_item: description.blank, quantity.blank/not_a_number/not_an_integer/greater_than_or_equal_to/less_than_or_equal_to, unit_price 동일 5키
  - hello (en.yml scaffold)
- 검증: `bin/rails runner`로 `I18n.exists?` 주요 6키(모델별 대표 깊은 키) 샘플 검증 → **ALL I18N KEYS OK (locale=ko)**. YAML 파싱 검증(deploy/en/ko) 통과.

## 작업 3 — Stimulus 정리

- `hello_controller.js` 삭제. `grep -rn "hello" app/views` → 매치 0건(en.yml 주석 내 "hello"는 문서 문자열뿐). index.js는 eager 로딩 방식이라 등록 제거 불요.
- portone 2종 컨트롤러 중복 정리(동작 변경 없음·뷰 데이터 속성 계약 유지):
  - 신설 `portone_shared.js`: `portoneSdkAvailable()`(SDK 가드)·`buildPortoneCustomer({fullName, phone, email, requireEmail})`(KG이니시스 customer 조립 — fullName 필수, phone은 존재 시에만, email은 requireEmail이면 빈 값도 싣는다 = 기존 billing의 무조건 email 전달·payment의 조건부 전달을 그대로 보존).
  - payment/billing 각각 import로 교체. 나머지(requestPayment/requestIssueBillingKey 호출·콜백 폴백·alert)는 원문 유지 — customer 객체 최종 키 집합은 변경 전과 동일(email 빈 문자열 케이스 포함 동등).
- `node --check` 문법 검증 3파일 모두 통과.

## 자가 검증 결과
- YAML: deploy.yml·en.yml·ko.yml 파싱 OK
- JS: node --check 3파일 OK
- i18n: runner 키 존재 검증 OK
- rubocop: 순수 Ruby 파일 변경 없음(deploy.yml·yml·js만) — 해당 없음
- 하드 제약 준수: 화이트리스트 외 파일 0건 수정, 마이그레이션/routes/테스트 미생성, 부트(전체) 없이 runner만 사용, 커밋 없음

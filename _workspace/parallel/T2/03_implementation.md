# T2 — ko locale 구현 산출물 (2026-11-09)

## 변경 파일
1. `Gemfile` — `gem "rails-i18n", "~> 8.0"` 추가
2. `Gemfile.lock` — rails-i18n 8.1.0 설치 반영 (`bundle install` 완료)
3. `config/application.rb` — `config.i18n.available_locales = [:en, :ko]`, `config.i18n.default_locale = :ko` 추가 (TIME-1 KST 설정 아래)
4. `config/locales/ko.yml` — 신규. 앱 전용 골격(`app.name`) + rails-i18n ko 사전에 없는 `errors.messages.not_saved` 보완. 헤더·날짜·속성명 기본번역은 rails-i18n 위임을 주석 명시
5. `test/config/locale_test.rb` — 신규. 기본 로케일 ko + rails-i18n 한글 사전(blank·날짜 long 포맷·not_saved) 검증 2건

## rails-i18n 버전
- rails-i18n **8.1.0** (Rails 8.1 호환 최신, Gemfile은 `~> 8.0` 지정)

## 자기 스코프 검증 결과
- `bin/rails runner`: `I18n.locale` → `ko`, `I18n.l(Date.current)` → `2026-11-09`(기본 포맷), `I18n.t("errors.messages.blank")` → `내용을 입력해 주세요`, `I18n.l(Time.current, format: :long)` → `2026년 11월 09일 06시 44분` 확인
- `bin/rails test test/config/locale_test.rb`: **2 runs, 7 assertions, 0 failures** 통과
- `bin/rubocop` (Ruby 파일 스코프: application.rb·locale_test.rb·Gemfile): **0 offenses**. 참고: .yml 파일은 omakase 기본 스캔 대상이 아님 — 명시적으로 인자로 넘기면 Ruby 파서로 잘못 해석되어 오탐(기존 en.yml도 동일)이므로 제외함

## 발견 회귀 후보 (영어 기본 메시지 단언 테스트)
- 없음. `test/` 전체에서 `can't be blank` 등 영어 기본 검증 메시지 단언 문자열 검색 결과 0건 — 모델들이 한글 커스텀 메시지 사용 중이라 기존 테스트 수정 불필요
- 참고: rails-i18n ko 사전에는 `errors.messages.not_saved`·`record_invalid` 중 not_saved가 누락되어 있어 앱 ko.yml에서 보완함(record_invalid는 사전에 존재)

## 3-S 통합 수정 (2026-11-09 추가)
- **원인**: 기존 앱은 en 기본 로케일 + en.yml에 한국어 activerecord 번역을 넣는 패턴. `default_locale=:ko` 전환으로 en.yml이 로딩 대상에서 빠져 rails-i18n ko의 일반 문구로 덮임 → 전체 테스트 36건 실패
- **수정**:
  1. `config/locales/en.yml`의 `activerecord.errors.models` 블록 전체(user·client·item·invoice·invoice_item)를 **한국어 원문 그대로** `ko.yml`로 이식 — 테스트 기대치 변경 없이 해소
  2. `en.yml`은 en 백업으로 유지, 낯선 구조(en에 한국어)에 대한 정리 과제 주석만 추가
- **검증**: 지시받은 8개 파일 실행 → **143 runs, 921 assertions, 0 failures, 0 errors** (client_test·item_test·invoice_item_test·clients/invoices/items/payments/profiles controller tests 전부 통과)
- locale_test.rb 재실행도 0 failures (test/config/locale_test.rb는 7 assertions 통과)
- **잔여 실패**: 없음
- rubocop: Ruby 파일 변경 없음(이번 수정은 yml만)

## 소유권 준수 (원본)
- 화이트리스트 외 파일 미수정 (app/, db/, config/routes.rb, PRD 등 건드리지 않음)
- repo-wide 테스트·마이그레이션 실행 안 함 (자기 스코프만)

# 병렬 배치 T1·T3·T4 — 통합 테스트 리포트 (07_test_report)

일자: 2026-11-20 · Tester: badeuldon-reviewer (리뷰+테스트 통합 런 — 일반 모드 기준)

## 게이트 결과

| 게이트 | 결과 |
|:---|:---|
| 개별 파일 실행 | 전부 통과 (아래 표) |
| **전체 `bin/rails test`** | **1,466 runs · 9,068 assertions · 0 failures · 0 errors · 0 skips** (36.96s) — 기존 회귀 0 |
| **전체 `bin/rubocop`** | **412 files · 0 offenses** |
| 외부 실호출 | **0** — 솔라피 get_balance는 전부 stub(FakeSolapiBalanceClient·FakeSolapiTransport·생성자 대역), 포트원·바로빌 기존 stub 체계 불변 |

## 신규/갱신 테스트 (11파일 — 신규 4·갱신 7 · 신규 테스트 28건)

### T3 — payments.note·digest 인덱스·routes·비고 표시

| 파일 | 신규/갱신 | 케이스 | 커버 Rule |
|:---|:---|:---|:---|
| `test/services/payments/record_service_test.rb` | 신규(4) | ① 과다입금 note 저장(문구 "남은 잔액을 30,000원 초과하여 마감 처리"·"거래처와 직접 협의")+감사 병행 ② 정확한 마감 note nil·감사 0 ③ 부분입금 note nil ④ 마감 후 재입금 note nil·감사 1회(상태 불변) | Q22·P4·PAY-1·PAY-2 |
| `test/models/message_log_digest_index_test.rb` | 신규(3) | ① 같은 (user·template_key·scheduled_at) digest 2행째 → `ActiveRecord::RecordNotUnique`(DB 방어선) ② scheduled_at 상이 → 복수 행 허용(주 단위 키) ③ 일반(digest=false) 동일 키 2행 → 영향 0(부분 인덱스 범위 밖) | SEC-5 준칙·NOTI-2·W-1(전번 리뷰) |
| `test/controllers/app/payments_over_policy_test.rb` | 갱신(+1) | 과다입금 비고가 상세 페이지 입금 이력에 1줄 렌더(플래시 문언 "초과해"와 비고 "초과하여 마감 처리"를 구분해 특정) — 마감 후 재입금 추가 후에도 비고 1행 유지 | Q22 구조화·T3 |
| `test/controllers/admin/sales_reps_controller_test.rb` | 갱신(+1) | DELETE 라우트 부재(recognize_path → RoutingError)·member PATCH 3종 불변 | 관찰⑤·P4 |

### T4 — 솔라피 잔액

| 파일 | 신규/갱신 | 케이스 | 커버 Rule |
|:---|:---|:---|:---|
| `test/services/solapi/client_service_test.rb` | 갱신(+4) | ① get_balance GET /cash/v1/balance·무바디·HMAC 인증 헤더·정수 정규형 `{balance, point}` ② 콤마 문자열 "12,345" 정규화 ③ point 누락 → 0 ④ 스키마 이탈(balance 누락·null·비숫자) → `UNEXPECTED_BALANCE_RESPONSE` fail-fast 3종 | ADMIN-5·REM-10 |
| `test/helpers/admin/dashboards_helper_test.rb` | 신규(5) | ① nil → "일시 조회 불가"·중립 회색·low? false ② 49,999 주황·low? true ③ **경계 50,000 정상**(미만 조건) ④ 120,000 통화 표기(ko locale 접미사 "120,000₩") ⑤ 0원도 충전 필요 | ADMIN-5 |
| `test/controllers/admin/dashboards_controller_test.rb` | 갱신(+5·기존 5 케이스 stub화) | ① 잔액 렌더("솔라피 잔액"·"120,000₩"·경고 배지 부재) ② 임계 미만 주황+"충전 필요" 배지 ③ 조회 실패 → "일시 조회 불가" 폴백·200 유지 ④ 성공 5분 캐시 — 재요청 래퍼 1회만 호출(MemoryStore 스왑) ⑤ 실패 1분 센티널 — 재요청 재호출 없음 | ADMIN-5·REM-10·05_review C-1 |

### C-1 해소 — 대시보드 렌더 실호출 차단 (기존 테스트 stub화)

| 파일 | 조치 |
|:---|:---|
| `test/controllers/admin/sessions_controller_test.rb` | 12h 세션 유지 테스트(렌더 11회)를 `with_solapi_client` 대역으로 교체 — 세션 판정 로직 불변 |
| `test/controllers/admin/base_guard_test.rb` | 잠금 경계 렌더(200) 1곳 stub화 |
| `test/controllers/sales/session_isolation_test.rb` | 관리자 세션 유지 렌더 2곳 stub화 — 쿠키 격리 판정 불변 |
| (`dashboards_controller_test.rb` 위 표) | 기존 5 케이스의 `get admin_root_path` 전부 `with_solapi_balance`로 래핑 |

### T1 — 정책 문서

| 파일 | 신규/갱신 | 케이스 | 커버 Rule |
|:---|:---|:---|:---|
| `test/controllers/pages_policy_test.rb` | 신규(5) | ① 3문서 비로그인 200·제목 렌더 ② noindex 메타 0 — 색인 허용(SURF-3 공개 법적 고지 확인) ③ terms 핵심 문구(건당 300원·건당 5,000원·20% 할인·취소 과금·미리보기·세무 자문 아님·바로빌·청구 건당 1회·개인 비대상) ④ privacy(휴대폰 번호 필수·유일성 검증·5분 1회용·바로빌((주)케이넷)·공동인증서 바로빌 보관·인증번호 발송 포함·발행 대행) ⑤ refund(환불 불가·건당 5,000원·300원·취소 과금) | TAX-1·Q21·LEGAL-2·Q24·AUTH-9·SURF-3·LP-12(존재 기준) |

## 개별 파일 실행 결과 (전체 실행 전 검증)

| 파일 | runs | failures |
|:---|---:|---:|
| test/services/payments/record_service_test.rb | 4 | 0 |
| test/models/message_log_digest_index_test.rb | 3 | 0 |
| test/controllers/app/payments_over_policy_test.rb | 10 | 0 |
| test/controllers/admin/sales_reps_controller_test.rb | 13 | 0 |
| test/services/solapi/client_service_test.rb | 22 | 0 |
| test/helpers/admin/dashboards_helper_test.rb | 5 | 0 |
| test/controllers/admin/dashboards_controller_test.rb | 10 | 0 |
| test/controllers/pages_policy_test.rb | 5 | 0 |
| test/controllers/admin/sessions_controller_test.rb | 16 | 0 |
| test/controllers/admin/base_guard_test.rb + sales/session_isolation_test.rb | 12 | 0 |

## 테스트 중 발견·수정 사항 (코드 버그 아님 — 테스트 자체 조정)

1. **C-1 (05_review)** — 대시보드 렌더의 솔라피 실호출을 4개 기존 테스트 파일에서 stub화로 해소. 실행 중 `base_guard`(잠금 경계 렌더)·`sales/session_isolation`(2곳)의 추가 200 렌더 지점을 발견해 함께 처리했다. **소스 코드 버그 아님** — 컨트롤러 직접 생성은 기존 컨벤션(PortOne 계열과 동일)이나, 후속으로 래퍼 주입점 도입을 기술 부채 후보로 기록(05_review C-1).
2. **ko locale 통화 접미사** — `number_to_currency(unit: "₩")`가 "₩120,000"이 아니라 "120,000₩"로 렌더된다(대시보드 기존 매출 카드 "9,900₩"와 동일 규격 — 일관성 유지). 테스트를 실측 형식으로 고정했다. 표기 변경이 필요하면 별도 UI 결정 사항.
3. 테스트 수정 과행(괄호 누락·hash literal 문법 2건)은 작성 중 즉시 정정 — 산출물에는 반영 완료.

## Tester 결론

- 지시 항목 전 커버: T3(note·digest 인덱스·비고 표시·routes 404)·T4(get_balance stub 정상/콤마/이탈·헬퍼 경계·캐시 히트·fallback·대시보드 렌더)·T1(라우트 200·noindex 허용·핵심 문구).
- 외부 실호출 0·전체 스위트 0 failures·RuboCop 0 — 게이트 통과.
- 운영 액션(테스트 범위 밖 — 05_review·T4 문서 인계): 운영 솔라피 잔액이 임계(50,000원) 미만(4자리 관측) — **충전 필요**(REM-10 발송 중단 방지).

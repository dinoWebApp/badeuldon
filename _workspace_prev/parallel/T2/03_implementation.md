# T2 클라이언트 IP 전역 통일 — 구현 보고 (ADMIN-2·Q32)

## 변경 파일

| 파일 | 변경 |
|---|---|
| `app/controllers/concerns/client_ip.rb` | 신설 — `ClientIp.of(request)` 단일 출처 |
| `app/controllers/viewer_controller.rb` | `viewer_client_ip` → 헬퍼 위임(메서드 유지) |
| `app/controllers/concerns/authentication.rb` | 세션 생성 `ip_address:` 교체(50행) |
| `app/controllers/registrations_controller.rb` | rate_limit `by:` + 감사 ip(2곳) |
| `app/controllers/app/profiles_controller.rb` | destroy 감사 ip(1곳) |
| `app/controllers/admin/sessions_controller.rb` | 감사 5곳 + last_login_ip + 새 IP 비교 + 메일러(8곳) |
| `app/controllers/admin/passwords_controller.rb` | 감사 ip(1곳) |
| `app/controllers/admin/sales_reps_controller.rb` | 감사 ip(5곳) |
| `app/controllers/admin/sales_commissions_controller.rb` | 감사 ip(1곳) |
| `app/controllers/sales/sessions_controller.rb` | 감사 3곳 + 세션 발급(4곳) |
| `test/controllers/concerns/client_ip_test.rb` | 신설 — 5케이스 단위 테스트 |
| `test/controllers/admin/sessions_controller_test.rb` | CF 헤더 감사 IP 단언 테스트 1건 보강 |

## 적용처 전수(교체 전 → 후, `request.remote_ip` → `ClientIp.of(request)`)

- authentication.rb:50 `ip_address: request.remote_ip` → `ip_address: ClientIp.of(request)`
- registrations_controller.rb:18 `by: -> { request.remote_ip }` → `by: -> { ClientIp.of(request) }`
- registrations_controller.rb:123 / profiles_controller.rb:36 / passwords_controller.rb:30 / sales_commissions_controller.rb:21 / sales_reps_controller.rb:26·42·57·69·80 / sales/sessions_controller.rb:43·45·54·56 / admin/sessions_controller.rb:76·85·155·157·158·167·169·170 — 전부 동일 표현식 교체
- viewer_controller.rb:73-75: `request.headers["CF-Connecting-IP"].presence || request.remote_ip` → `ClientIp.of(request)` (메서드명·호출처 유지, 주석 갱신)

grep으로 `app/` 내 잔존 `request.remote_ip` 0건 확인. 컨트롤러 액션 본문 구조 변경 없음(표현식만).

## 헬퍼 코드 전문 (`app/controllers/concerns/client_ip.rb`)

```ruby
module ClientIp
  IPV4 = /\A\d{1,3}(\.\d{1,3}){3}\z/
  IPV6 = /\A(?:[0-9A-Fa-f]{0,4}:){1,7}[0-9A-Fa-f]{0,4}(?:\.\d{1,3}){0,3}\z/

  module_function

  def of(request)
    header = request.headers["CF-Connecting-IP"].to_s.strip
    return header if header.match?(IPV4) || header.match?(IPV6)

    request.remote_ip
  end
end
```

- 채택 조건: 헤더 존재 + 단일 IP 형태(쉼표 목록·공백·빈 값은 strip 후 형식 불일치 → 폴백)
- IPv6 regex는 IPv4 매핑 최장 45자 표기(`...:ffff:255.255.255.255`)를 수용(기존 viewer 테스트가 이 형태를 단언 — SHARE-3)
- 헤더 주석에 Q32 근거(CF 터널 단일 경로·원본 포트 비공개·SHARE-3 선례·로컬 무헤더) 기록

## 테스트 결과

- 신설 `client_ip_test.rb`: IPv4 채택 / 헤더 없음 폴백 / 쉼표 목록 폴백 / 공백·빈 값 폴백 / IPv6 채택 — 5건 통과
- 보강: admin 로그인 성공 시 CF 헤더 IP(203.0.113.7)가 `AuditLog(login_success).ip`와 `admins.last_login_ip`에 기록됨을 단언 — 통과
- 지정 테스트 10파일 전부: **134 runs, 1026 assertions, 0 failures, 0 errors** (`DATABASE_URL=sqlite3:tmp/parallel/T2/test.sqlite3`)
- `bin/rubocop` 소유 12파일: no offenses. `bin/rails zeitwerk:check`: 통과

## 남은 우려

1. 최초 전체 실행 시 viewer 만료·무효 토큰 2케이스가 404 기대를 200으로 통과한 일시적 실패가 있었으나 재실행(단독·전체 모두)에서 0 failures — 다른 병렬 태스크의 fixture 수정(`test/fixtures/invoices.yml` — 타 태스크 소유) 중간 상태와 겹친 것으로 추정, 최종 상태는 정상. 재현 불가라 관찰만 기록.
2. IPv6 형태 검증은 형태 소거용(0~255 옥텟·섹션 값 검증은 안 함) — 계획서 명시 범위 내. 비정상 값은 폴백(remote_ip)으로 수렴.
3. `test/test_helpers/admin_session_test_helper.rb`는 소유 밖이라 수정하지 않았고, 보강 테스트는 파일 내 직접 POST로 CF 헤더를 실었다.

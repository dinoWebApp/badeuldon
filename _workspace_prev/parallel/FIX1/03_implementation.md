# FIX1 — 병렬 배치 리뷰 반영 수정 (T2 W-1·W-2, T4 W-2)

2026-11-26 · 절약 모드 · 리뷰 APPROVED의 WARNING만 수정. 소유 파일 외 변경 없음, git 상태 변경 없음.

## 변경 파일

| 파일 | 변경 |
|:--|:--|
| `app/controllers/concerns/client_ip.rb` | W-1(T2) — IPV4·IPV6 정규식 상수 폐기, `IPAddr.new` 기반 판정으로 교체. `require "ipaddr"` 추가. 채택 시 원문 헤더 문자열 반환(P4 원문성) |
| `test/controllers/concerns/client_ip_test.rb` | W-1 실측표를 테스트로 고정 — 무의미 값 6종 폴백, zone id 채택(실측 기준), mapped IPv6 3종 원문 채택 |
| `app/controllers/admin/tickets_controller.rb` | W-2(T2) — `ticket_close` 감사에 `ip: ClientIp.of(request)` 1인자 추가(구조 불변) |
| `app/controllers/app/subscriptions_controller.rb` | W-2(T2) — `coupon_redeemed` 감사(`record_coupon_redeemed_audit`)에 `ip: ClientIp.of(request)` 1인자 추가 |
| `test/controllers/admin/tickets_controller_test.rb` | `CF-Connecting-IP: 203.0.113.51` 헤더 요청 → 감사 행 `ip` 단언 1건 신설 |
| `test/controllers/app/subscriptions_coupon_test.rb` | `CF-Connecting-IP: 203.0.113.42` 헤더 요청 → 감사 행 `ip` 단언 1건 신설(with_portone_client 스텁 유지) |
| `app/models/client.rb` | W-2(T4) — 118행 주석만 보정(코드 변경 없음) |

## 헬퍼 최종 코드 (`client_ip.rb` 전문)

```ruby
# 클라이언트 IP 단일 출처(Q32·ADMIN-2) — 운영은 전부 Cloudflare 터널 경유라 request.remote_ip가
# 터널 컨테이너의 같은 값으로 수렴해 감사 로그·관리자 새 IP 감지(AUTH-7.4)·등록 rate limit(AUTH-9)·
# 세션 기록이 사실상 무의미해졌다. CF가 실방문자 IP로 설정하는 CF-Connecting-IP(SHARE-3 뷰어 선례)를
# 우선 채택한다. 운영 원본 포트는 비공개(AGENTS.md 배포 인프라 — CF 터널만 수신)라 이 헤더는
# 터널 경유 요청에만 존재하며 위조 경로가 없고, 로컬·테스트 등 헤더 없는 요청은 remote_ip로
# 폴백한다. 헤더가 있어도 형식 판정은 루비 표준 라이브러리 IPAddr.new의 주소 파싱 기준으로 하며 —
# 쉼표 목록·공백·빈 값·포트 접미·콜론만 있는 값·옥텟 범위 이탈 값은 전부 폴백한다(리뷰 W-1 반영 —
# 느슨한 정규식이 ":"·"999.999.999.999" 같은 무의미한 값까지 채택하던 것을 없앤다). IPv4-mapped
# IPv6의 최장 45자 표기(0000:0000:0000:0000:0000:ffff:255.255.255.255)와 대문자 전체형도 수용된다.
# 단, IPAddr은 zone id 표기(fe80::1%eth0)를 유효 주소로 파싱하므로 이 값은 채택된다. 채택 시
# 정규화·재포맷 없이 원문 헤더 문자열을 그대로 기록해 P4 원문성을 보존한다.
require "ipaddr"

module ClientIp
  module_function

  def of(request)
    header = request.headers["CF-Connecting-IP"].to_s.strip
    return header if valid_ip?(header)

    request.remote_ip
  end

  def valid_ip?(value)
    return false if value.empty?

    IPAddr.new(value)
    true
  rescue IPAddr::InvalidAddressError, ArgumentError
    false
  end
end
```

## IPAddr.new 실측표 (ruby -ripaddr 직접 실행, 2026-11-26)

| 값 | IPAddr.new | 테스트 기대 |
|:--|:--|:--|
| `:` | 거부(InvalidAddressError) | 폴백 |
| `:::` | 거부 | 폴백 |
| `1:::2` | 거부 | 폴백 |
| `::ffff:1.2.3` | 거부 | 폴백 |
| `999.999.999.999` | 거부 | 폴백 |
| `1.2.3.4:8080` | 거부 | 폴백 |
| `fe80::1%eth0` | **통과** | **채택(원문)** — 지시의 "폴백 기대"를 사실에 맞춰 조정(아래 참고) |
| `1.2.3.4, 5.6.7.8` | 거부 | 폴백 |
| `203.0.113.7` | 통과 | 채택(원문) |
| `2001:db8::1` | 통과 | 채택(원문) |
| `::ffff:203.0.113.7` | 통과 | 채택(원문) |
| `2001:0DB8:0000:0000:0000:0000:0000:0001` | 통과 | 채택(원문) |
| `0000:0000:0000:0000:0000:ffff:255.255.255.255` (45자 매핑형) | 통과 | 채택(원문) |

**지시 대비 조정 1건**: `fe80::1%eth0`(zone id)은 IPAddr이 유효 주소로 파싱해 통과한다 — 판정 기준이 IPAddr이므로 테스트 기대를 "채택(원문)"으로 고정하고 파일 주석에도 명시했다.

## 테스트 결과 (전용 DB `tmp/parallel/FIX1/test.sqlite3`)

- `bin/rails test test/controllers/concerns/client_ip_test.rb test/controllers/admin/tickets_controller_test.rb test/controllers/app/subscriptions_coupon_test.rb test/controllers/app/subscriptions_controller_test.rb test/models/client_test.rb` → **61 runs, 343 assertions, 0 failures, 0 errors**
- `viewer_controller_test.rb` + `admin/sessions_controller_test.rb` (ClientIp 경유 회귀) → **40 runs, 311 assertions, 0 failures**
- `bin/rubocop` (소유 7파일) → 0 offenses
- `bin/rails zeitwerk:check` → 통과
- 결제 경로 테스트는 기존 `with_portone_client` 스텁 내 실행 — 외부 실호출 없음

## 남은 우려

- zone id 값이 이제 감사 로그에 원문 기록될 수 있다 — CF가 실제로 그런 값을 보내지 않고(엣지에서 덮어씀) 위조 경로도 없어(공개 포트 0) 영향 없음으로 판단. 정밀 차단이 필요하면 별도 후속.
- 감사 로그의 `ip` 컬럼 저장 길이 제약은 기존 RecordService 스키마를 그대로 따른다(신규 컬럼 없음).
- W-3(운영 노트 1행 — 기존 `admins.last_login_ip` 터널 IP로 인한 첫 로그인 신규 IP 알림 1회)은 문서 작업이라 이 태스크 범위 밖(금지 항목) — 오케스트레이터 반영 대상.

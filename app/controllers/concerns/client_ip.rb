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

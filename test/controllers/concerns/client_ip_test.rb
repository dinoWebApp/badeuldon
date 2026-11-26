require "test_helper"

# Q32·ADMIN-2 — 클라이언트 IP 단일 출처(ClientIp.of) 판정 단위 테스트.
# 형식 판정은 IPAddr.new 기준(리뷰 W-1) — 아래 실측표가 곧 기대값이다.
class ClientIpTest < ActiveSupport::TestCase
  test "CF-Connecting-IP가 단일 IPv4면 그 값을 채택한다" do
    request = ActionDispatch::TestRequest.create
    request.headers["CF-Connecting-IP"] = "203.0.113.7"

    assert_equal "203.0.113.7", ClientIp.of(request)
  end

  test "헤더가 없으면 remote_ip로 폴백한다" do
    request = ActionDispatch::TestRequest.create

    assert_equal request.remote_ip, ClientIp.of(request)
  end

  test "헤더가 쉼표 목록이면 채택하지 않고 remote_ip로 폴백한다" do
    request = ActionDispatch::TestRequest.create
    request.headers["CF-Connecting-IP"] = "1.2.3.4, 5.6.7.8"

    assert_equal request.remote_ip, ClientIp.of(request)
  end

  test "헤더가 공백이나 빈 값이면 remote_ip로 폴백한다" do
    blank = ActionDispatch::TestRequest.create
    blank.headers["CF-Connecting-IP"] = "   "
    assert_equal blank.remote_ip, ClientIp.of(blank)

    empty = ActionDispatch::TestRequest.create
    empty.headers["CF-Connecting-IP"] = ""
    assert_equal empty.remote_ip, ClientIp.of(empty)
  end

  test "단일 IPv6 값은 채택한다" do
    request = ActionDispatch::TestRequest.create
    request.headers["CF-Connecting-IP"] = "2001:db8::1"

    assert_equal "2001:db8::1", ClientIp.of(request)
  end

  test "무의미한 콜론·옥텟 이탈·포트 접미 값은 전부 remote_ip로 폴백한다" do
    rejected = [
      ":", # 콜론만 있는 값
      ":::", # 빈 그룹 연속
      "1:::2", # 빈 그룹 연속(그룹 사이)
      "::ffff:1.2.3", # IPv4 꼬리 옥텟 부족
      "999.999.999.999", # 옥텟 범위 이탈
      "1.2.3.4:8080" # 포트 접미
    ]
    rejected.each do |value|
      request = ActionDispatch::TestRequest.create
      request.headers["CF-Connecting-IP"] = value

      assert_equal request.remote_ip, ClientIp.of(request), "#{value}은(는) 채택되면 안 된다"
    end
  end

  test "zone id 표기는 IPAddr이 유효 주소로 파싱하므로 원문 그대로 채택된다(실측 기준)" do
    request = ActionDispatch::TestRequest.create
    request.headers["CF-Connecting-IP"] = "fe80::1%eth0"

    assert_equal "fe80::1%eth0", ClientIp.of(request)
  end

  test "IPv4-mapped IPv6의 약식·대문자 전체형·45자 최장 표기는 원문 그대로 채택한다" do
    accepted = [
      "::ffff:203.0.113.7",
      "2001:0DB8:0000:0000:0000:0000:0000:0001",
      "0000:0000:0000:0000:0000:ffff:255.255.255.255"
    ]
    accepted.each do |value|
      request = ActionDispatch::TestRequest.create
      request.headers["CF-Connecting-IP"] = value

      assert_equal value, ClientIp.of(request), "#{value}은(는) 원문 그대로 채택돼야 한다"
    end
  end
end

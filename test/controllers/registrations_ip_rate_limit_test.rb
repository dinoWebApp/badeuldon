require "test_helper"
require_relative "../test_helpers/fake_solapi_client"
require_relative "../test_helpers/solapi_stubbing"

# AUTH-9·Q32 — 인증번호 엔드포인트 IP rate limit(20회/1시간)의 버킷 분리.
# rate_limit의 `by:`가 ClientIp.of(request)이므로 Cloudflare 터널 경유(CF-Connecting-IP
# 헤더) 요청은 헤더 값별로 별도 버킷이 되고, 헤더 없는 요청은 remote_ip 버킷에 묶인다.
# 솔라피 발송은 with_solapi_client 대역(외부 실호출 금지), 번호당 SendService 한도는
# 회차별 신규 번호로 회피한다.
class RegistrationsIpRateLimitTest < ActionDispatch::IntegrationTest
  include SolapiStubbing

  IP_LIMIT = 20

  test "인증번호 발송 IP 한도는 CF-Connecting-IP별로 버킷이 분리된다 (AUTH-9·Q32)" do
    with_memory_rate_limit_store do
      IP_LIMIT.times do
        send_phone_code(cf_ip: "1.2.3.4")
        assert_response :success
      end

      # 21번째 — 같은 헤더 IP 버킷은 한도에 걸린다
      send_phone_code(cf_ip: "1.2.3.4")
      assert_response :too_many_requests

      # 다른 헤더 IP는 별도 버킷이라 통과한다
      send_phone_code(cf_ip: "5.6.7.8")
      assert_response :success
    end
  end

  test "헤더 없는 요청은 remote_ip 버킷에 묶여 같은 한도가 적용된다 (AUTH-9·Q32)" do
    with_memory_rate_limit_store do
      IP_LIMIT.times do
        send_phone_code
        assert_response :success
      end

      send_phone_code
      assert_response :too_many_requests
    end
  end

  private

    # 회차마다 새 번호로 SendService의 번호당 rate limit(1분 1회·1시간 3회)을 회피한다.
    def send_phone_code(cf_ip: nil)
      headers = { "User-Agent" => "Rails Testing" }
      headers["CF-Connecting-IP"] = cf_ip if cf_ip
      @phone_seq = @phone_seq ? @phone_seq + 1 : 10_500_001
      with_solapi_client(FakeSolapiClient.new) do
        post send_phone_code_registration_path,
             params: { phone: "010#{@phone_seq}" }, headers: headers
      end
    end
end

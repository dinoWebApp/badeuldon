require "test_helper"
require_relative "../../test_helpers/fake_outbound_mail_client"
require_relative "../../test_helpers/outbound_mail_stubbing"
require_relative "../../test_helpers/portone_stubbing"

# OutboundMail::DeliveryMethod — ActionMailer 커스텀 배달 방식 단위 테스트(F-EMAIL — AUTH-8·
# AUTH-7.3/7.4/7.6·SEC-5·P4). settings 주입(stub client·발신자)이 정규 검증 경로다(03 §6).
# 멱등 키 파생(① 잡 헤더 우선 → ② 내용 해시 폴백), payload 조립(text/html 파트·from/reply_to
# 강제·nil compact), 폴백 분기(구성 전 로그 기록 — 본문·수신자 전체 미노출), 성공 기록 1행(P4),
# 본문 없는 메일 fail-fast를 검증한다. API 실호출은 0건이다.
class OutboundMail::DeliveryMethodTest < ActiveSupport::TestCase
  include OutboundMailStubbing
  include PortOneStubbing

  FROM_EMAIL = "no-reply@veloloop.kr"
  FROM_NAME = "받을돈"
  REPLY_TO = "contact@veloloop.kr"

  # ── payload 조립·발신 강제(지시 4·T-4) ─────────────────────────────────

  test "multipart 메일은 text+html 파트로 조립되고 from·reply_to는 설정값으로 강제된다 (메일러 지정 무시)" do
    message = PasswordsMailer.reset(users(:alpha)).message
    # 메일러·봉투가 다른 발신자를 지정해도 페이로드에서 정책 주소로 교체된다(SENDER_NOT_ALLOWED 403 방어).
    message.from = [ "attacker@example.com" ]
    message.reply_to = "attacker@example.com"

    payload = deliver_with_settings(message)

    assert_equal({ email: FROM_EMAIL, name: FROM_NAME }, payload[:from])
    assert_equal({ email: REPLY_TO }, payload[:reply_to])
    assert_equal [ { email: users(:alpha).email } ], payload[:to]
    assert_equal [], payload[:cc]
    assert_equal [], payload[:bcc]
    assert_equal "[받을돈] 비밀번호 재설정 안내", payload[:subject]
    assert_includes payload[:text_body], "이 링크는 15분 후 만료되며,"
    assert_includes payload[:html_body], "15분"
    assert_match %r{/passwords/}, payload[:text_body]
  end

  test "단일 text 파트 메일은 text_body만 조립하고 html_body 키가 없다 (nil compact)" do
    message = Mail.new
    message.to = [ "user@example.com" ]
    message.subject = "텍스트 안내"
    message.body = "텍스트 본문"

    # reply_to·from_name 미설정 — 키가 사라진다(compact). credentials 부재를 밀봉해 검증한다
    # (ambient credentials에 reply_to·from_name이 등록된 환경에서는 폴백으로 키가 생겨난다).
    client = FakeOutboundMailClient.new
    with_sealed_outbound_mail_credentials do
      OutboundMail::DeliveryMethod.new(client: client, from_email: FROM_EMAIL).deliver!(message)
    end
    payload = client.calls.sole

    assert_equal "텍스트 본문", payload[:text_body]
    assert_not_includes payload.keys, :html_body
    assert_not_includes payload.keys, :reply_to, "reply_to 미설정 시 키가 사라진다(compact)"
    assert_not_includes payload[:from], :name, "from_name 미설정 시 name 키가 사라진다"
  end

  test "단일 text/html 메일은 html_body만 조립한다" do
    message = Mail.new
    message.to = [ "user@example.com" ]
    message.subject = "HTML 안내"
    message.content_type = "text/html"
    message.body = "<p>HTML 본문</p>"

    payload = deliver_with_settings(message)

    assert_equal "<p>HTML 본문</p>", payload[:html_body]
    assert_not_includes payload.keys, :text_body
  end

  test "from_email 누락은 구성 오류로 fail-fast하고 전송 시도가 없다 (조용한 통과 금지)" do
    client = FakeOutboundMailClient.new
    message = PasswordsMailer.reset(users(:alpha)).message

    # credentials를 밀봉해 from_email 부재를 환경과 무관하게 강제한다(초기화 시점 폴백 읽기).
    error = with_sealed_outbound_mail_credentials do
      method = OutboundMail::DeliveryMethod.new(client: client)
      assert_raises(OutboundMail::ApiError) { method.deliver!(message) }
    end

    assert_nil error.status
    assert_equal "MISSING_CREDENTIALS", error.code
    assert_empty client.calls
  end

  # ── 본문 없는 메일 fail-fast(지시 5) ───────────────────────────────────

  test "본문 파트가 없는 메일은 네트워크 왕복 없이 INVALID_REQUEST로 fail-fast한다" do
    client = FakeOutboundMailClient.new
    method = OutboundMail::DeliveryMethod.new(
      client: client, from_email: FROM_EMAIL, from_name: FROM_NAME, reply_to: REPLY_TO
    )
    message = Mail.new
    message.to = [ "user@example.com" ]
    message.subject = "본문 없음"

    error = assert_raises(OutboundMail::ApiError) { method.deliver!(message) }

    assert_equal "INVALID_REQUEST", error.code
    assert_empty client.calls
  end

  # ── 멱등 키 — 잡 헤더 우선 → 내용 해시 폴백(SEC-5·지시 1) ────────────────

  test "X-BD-Outbound-Idempotency 헤더가 있으면 그 값이 키로 우선한다 (잡 경로)" do
    message = PasswordsMailer.reset(users(:alpha)).message
    message[OutboundMail::DeliveryMethod::IDEMPOTENCY_KEY_HEADER] = "job.9f0e8d7c-1"

    payload = deliver_with_settings(message)

    assert_equal "job.9f0e8d7c-1", payload[:idempotency_key]
  end

  test "헤더가 없으면 bd.+SHA256 내용 해시 폴백 키를 파생하고 결정적이다 (직접 경로·테스트)" do
    # freeze_time — reset 토큰의 exp 타임스탬프도 고정돼야 같은 순간 두 렌더는 같은 내용이다.
    freeze_time do
      message = PasswordsMailer.reset(users(:alpha)).message

      payload = deliver_with_settings(message)
      key = payload[:idempotency_key]

      assert_match(/\Abd\.[0-9a-f]{64}\z/, key)
      assert_equal 67, key.length, "API 규격 8~128자·[A-Za-z0-9._-] 충족(OUTBOUND_MAIL_API.md §2)"
      assert_equal key, deliver_with_settings(PasswordsMailer.reset(users(:alpha)).message)[:idempotency_key],
                   "같은 내용(수신자·제목·본문)은 같은 키 — 재시도 멱등"
      assert_not_equal key, deliver_with_settings(AdminMailer.locked_out(admins(:ops)))[:idempotency_key],
                       "다른 메일(수신자·제목·본문)은 다른 키"
    end
  end

  test "정적 본문 통보(locked_out 재렌더)는 시간이 흘러도 동일 키이고 reset 재렌더는 로테이션으로 상이 키다 (지시 1)" do
    freeze_time do
      locked_key_1 = deliver_with_settings(AdminMailer.locked_out(admins(:ops)))[:idempotency_key]
      reset_key_1 = deliver_with_settings(PasswordsMailer.reset(users(:alpha)).message)[:idempotency_key]

      travel 2.seconds
      locked_key_2 = deliver_with_settings(AdminMailer.locked_out(admins(:ops)))[:idempotency_key]
      # reset 토큰은 exp 타임스탬프 포함 서명(generates_token_for expires_in)이라 재렌더마다 로테이션
      reset_key_2 = deliver_with_settings(PasswordsMailer.reset(users(:alpha)).message)[:idempotency_key]

      assert_equal locked_key_1, locked_key_2, "정적 본문(수신자·제목·문구)은 재렌더 시에도 동일 키"
      assert_not_equal reset_key_1, reset_key_2, "재설정 링크 로테이션은 재렌더 시 새 키 = 새 메일"
    end
  end

  # ── 폴백 분기(지시 3·W-3 마스킹) ────────────────────────────────────────

  test "credentials 미구성 client는 실호출 없이 폴백 로그 1행으로 정상 복귀한다" do
    client = FakeOutboundMailClient.new(configured: false)
    method = OutboundMail::DeliveryMethod.new(
      client: client, from_email: FROM_EMAIL, from_name: FROM_NAME, reply_to: REPLY_TO
    )
    message = PasswordsMailer.reset(users(:alpha)).message

    with_outbound_mail_logger do |io|
      result = method.deliver!(message)

      assert_nil result, "예외 없이 정상 복귀(production raise_delivery_errors=true와 무충돌)"
      assert_empty client.calls, "API 실호출 0건"
      lines = io.string.scan(/\[OUTBOUND_MAIL:fallback\].*/).select { |line| line.include?(users(:alpha).email) || line.include?("***") }
      assert_equal 1, lines.size, "폴백 로그는 정확히 1행"

      line = lines.first
      assert_includes line, users(:alpha).email[0, 2]
      assert_includes line, "subject"
      assert_not_includes line, users(:alpha).email, "수신자 전체 주소 미노출(W-3 마스킹)"
      assert_no_match %r{/passwords/}, line, "본문·링크는 어느 경로로도 기록하지 않는다(P4)"
    end
  end

  test "마스킹은 @ 없는 비정형 수신자를 원형으로 유지한다" do
    client = FakeOutboundMailClient.new(configured: false)
    method = OutboundMail::DeliveryMethod.new(client: client, from_email: FROM_EMAIL)
    message = Mail.new
    message.to = [ "ops-0823" ]
    message.subject = "비정형"
    message.body = "본문"

    with_outbound_mail_logger do |io|
      method.deliver!(message)
      assert_includes io.string, "ops-0823", "@ 없는 값은 마스킹할 로컬부가 없어 원형 유지"
    end
  end

  # ── 성공 기록 1행(W-4·P4 로그 수준) ────────────────────────────────────

  test "성공 발송은 sent 로그 1행(id·message_id·마스킹된 수신자)과 스냅샷을 남긴다" do
    client = FakeOutboundMailClient.new
    method = OutboundMail::DeliveryMethod.new(
      client: client, from_email: FROM_EMAIL, from_name: FROM_NAME, reply_to: REPLY_TO
    )
    message = PasswordsMailer.reset(users(:alpha)).message

    with_outbound_mail_logger do |io|
      snapshot = method.deliver!(message)

      assert_equal({ id: "mail_fake_1", message_id: "<fake@veloloop.kr>",
                     status: "accepted_by_postfix" }, snapshot, "202 스냅샷은 반환값으로 유지")
      lines = io.string.scan(/\[OUTBOUND_MAIL:sent\].*/)
      assert_equal 1, lines.size, "성공 발송 기록은 1행(P4 로그 수준)"
      line = lines.first
      assert_includes line, "mail_fake_1"
      assert_includes line, "<fake@veloloop.kr>"
      assert_includes line, "#{users(:alpha).email[0, 2]}***@"
      assert_not_includes line, users(:alpha).email, "수신자 전체 주소 미노출(W-3 기준 통일)"
      assert_not_includes io.string, "이 링크는", "본문 미기록"
    end
  end

  # ── 전체 체인 — DeliveryMethod→ClientService→전송 계층(지시 4의 헤더 승격 단정) ──

  test "체인 전체에서 멱등 키는 JSON 바디에 없고 Idempotency-Key 헤더로만 전달된다" do
    transport = FakeOutboundMailTransport.new(response: Net::HTTPAccepted.new("1.1", "202", "Accepted").tap do |response|
      response.instance_variable_set(:@read, true)
      response.body = { success: true, data: { id: "mail_x", message_id: "<x@veloloop.kr>",
                                               status: "accepted_by_postfix" } }.to_json
    end)
    real_client = OutboundMail::ClientService.new(base_url: "https://mail-api.example.test", token: "bd-test-token")
    method = OutboundMail::DeliveryMethod.new(
      client: real_client, from_email: FROM_EMAIL, from_name: FROM_NAME, reply_to: REPLY_TO
    )
    message = PasswordsMailer.reset(users(:alpha)).message

    with_http_transport(transport) { method.deliver!(message) }

    request = transport.requests.sole
    expected_key = "bd." + Digest::SHA256.hexdigest(
      JSON.generate([ [ users(:alpha).email ], message.subject.to_s,
                      message.text_part.body.to_s, message.html_part.body.to_s ])
    )
    assert_equal expected_key, request["Idempotency-Key"], "폴백 파생 키가 헤더로 승격된다"
    body = JSON.parse(request.body)
    assert_not_includes body.keys, "idempotency_key", "키는 JSON 바디에 없다(SEC-5 헤더 승격)"
    assert_equal FROM_EMAIL, body["from"]["email"]
  end

  private

  # settings 주입 정규 경로 — client stub + 발신자 3종(03 §6.1 테스트 시먼트).
  def deliver_with_settings(message)
    client = FakeOutboundMailClient.new
    OutboundMail::DeliveryMethod.new(
      client: client, from_email: FROM_EMAIL, from_name: FROM_NAME, reply_to: REPLY_TO
    ).deliver!(message)
    client.calls.sole
  end
end

require "test_helper"
require_relative "../test_helpers/fake_outbound_mail_client"
require_relative "../test_helpers/outbound_mail_stubbing"

# F-EMAIL 통합 계층 — 자체 메일 API 전환의 전역 배선 검증(AUTH-8·AUTH-7.3/7.4/7.6·지시 8~10).
# ① 부트 등록 스모크(initializer가 :outbound_mail_api를 등록하고 settings 접근자를 만든다 — T-6)
# ② U1 재설정 플로우의 deliver_later → 배달 경로 스모크(테스트 환경은 기본 잡 — 내용 해시 폴백 키)
# ③ 재설정 링크 host(badeuldon.kr https — production default_url_options)
# ④ production.rb 배달 설정 3종+delivery_job 단정(config 단일 소스)
# ⑤ 관리자 보안 통보 3종(AUTH-7.3/7.4/7.6)이 배달 방식 payload로 조립되는 회귀
# ⑥ 봉투 from 폴백(credentials 부재 환경 — ApplicationMailer DEFAULT_FROM_EMAIL)
# 기존 passwords·admin 세션 컨트롤러 테스트의 단정은 전체 스위트 실행으로 회귀 확인한다(지시 9).
class OutboundMailDeliveryIntegrationTest < ActionMailer::TestCase
  include OutboundMailStubbing

  DELIVERY_SETTINGS = { from_email: "no-reply@veloloop.kr", from_name: "받을돈",
                        reply_to: "contact@veloloop.kr" }.freeze

  # ── 부트 등록 스모크(지시 10·T-6 런타임 확인) ───────────────────────────

  test "부트 후 outbound_mail_api가 등록돼 있고 settings 접근자 주입 경로가 동작한다" do
    assert_equal OutboundMail::DeliveryMethod,
                 ActionMailer::Base.delivery_methods[:outbound_mail_api],
                 "initializer(after_initialize)가 등록한 배달 방식이 런타임에 존재한다"
    assert ActionMailer::Base.respond_to?(:outbound_mail_api_settings),
           "add_delivery_method가 생성한 settings 접근자(Railtie 공식 전달 경로)"

    fake = FakeOutboundMailClient.new
    with_outbound_mail_delivery({ client: fake, **DELIVERY_SETTINGS }) do
      # deliver(non-bang) — deliver_later→deliver_now가 쓰는 프로덕션 실제 경로(MessageDelivery#deliver_now).
      PasswordsMailer.reset(users(:alpha)).message.deliver
    end

    assert_equal 1, fake.calls.size, "등록 심볼+settings 주입으로 실제 배달이 수행된다"
    assert_equal({ email: "no-reply@veloloop.kr", name: "받을돈" }, fake.calls.sole[:from])
  end

  # ── U1 재설정 플로우 — deliver_later 배달 경로 스모크(지시 8 보완) ────────

  test "deliver_later 경유 발송이 배달 방식 payload로 도달하고 내용 해시 폴백 키를 쓴다 (테스트 환경 기본 잡)" do
    fake = FakeOutboundMailClient.new

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        perform_enqueued_jobs { PasswordsMailer.reset(users(:alpha)).deliver_later }
      end
    end

    payload = fake.calls.sole
    assert_equal [ { email: users(:alpha).email } ], payload[:to]
    assert_match %r{/passwords/}, payload[:text_body]
    # 테스트·개발 환경은 delivery_job 미지정(Rails 기본 MailDeliveryJob — 헤더 주입 없음)이므로
    # 잡 밖 경로의 내용 해시 폴백 키다. production은 OutboundMail::DeliveryJob —
    # job.<job_id> 키(잡 계층 테스트 검증).
    assert_match(/\Abd\.[0-9a-f]{64}\z/, payload[:idempotency_key])
  end

  # ── 재설정 링크 host(지시 8 — 프로토콜·host 단정 추가) ──────────────────

  test "production default_url_options에서 재설정 링크는 https://badeuldon.kr 이다 (T-7 회귀)" do
    original = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = { host: "badeuldon.kr", protocol: "https" }

    mail = PasswordsMailer.reset(users(:alpha)).message
    assert_match(%r{https://badeuldon\.kr/passwords/}, mail.text_part.body.to_s)
    assert_match(%r{https://badeuldon\.kr/passwords/}, mail.html_part.body.to_s)
  ensure
    ActionMailer::Base.default_url_options = original
  end

  test "production.rb는 배달 방식 3종·delivery_job·링크 host를 지정하고 example.com이 없다 (config 단일 소스)" do
    config = Rails.root.join("config/environments/production.rb").read

    assert_match(%r{config\.action_mailer\.raise_delivery_errors = true}, config,
                 "API 실패가 잡 실패로 가시 기록된다(W-5 재시도·버림 분기의 전제)")
    assert_match(%r{config\.action_mailer\.delivery_method = :outbound_mail_api}, config)
    assert_match(%r{config\.action_mailer\.delivery_job = "OutboundMail::DeliveryJob"}, config,
                 "deliver_later가 잡 식별자 멱등 키 잡으로 승격된다(C-1·SEC-5)")
    assert_match(%r{config\.action_mailer\.default_url_options = \{ host: "badeuldon\.kr", protocol: "https" \}}, config)
    active_lines = config.lines.reject { |line| line.strip.start_with?("#") }.join
    assert_not_includes active_lines, "example.com", "유효 설정에 재설정 링크 host 잔존 없음(주석 제외)"

    assert_equal OutboundMail::DeliveryJob, "OutboundMail::DeliveryJob".constantize
    assert_operator OutboundMail::DeliveryJob, :<, ActionMailer::MailDeliveryJob
  end

  # ── 관리자 보안 통보 3종 — 배달 방식 payload 조립 회귀(AUTH-7.3/7.4/7.6) ──

  test "관리자 3종 통보 메일이 배달 방식을 통과해 3건 발송된다 (AUTH-7.3·7.4·7.6)" do
    admin = admins(:ops)
    fake = FakeOutboundMailClient.new

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        AdminMailer.locked_out(admin).deliver_now
        AdminMailer.new_login(admin, "10.9.9.9").deliver_now
        AdminMailer.password_reset(admin, "https://badeuldon.kr/admin/password/edit/tok").deliver_now
      end
    end

    assert_equal 3, fake.calls.size
    assert_equal 3, fake.idempotency_keys.uniq.size, "3종은 서로 다른 내용 — 서로 다른 키"
  end

  test "관리자 3종 각각의 payload는 수신자·제목·본문 키워드를 유지한다 (AUTH-7.3·7.4·7.6)" do
    admin = admins(:ops)
    cases = {
      locked_out: [ AdminMailer.locked_out(admin), "[받을돈 관리자] 계정 잠금 통보", "잠금" ],
      new_login: [ AdminMailer.new_login(admin, "10.9.9.9"), "[받을돈 관리자] 신규 IP 로그인 통보", "10.9.9.9" ],
      password_reset: [ AdminMailer.password_reset(admin, "https://badeuldon.kr/admin/password/edit/tok"),
                        "[받을돈 관리자] 비밀번호 재설정 안내", "/admin/password/edit/tok" ]
    }

    cases.each_value do |(mail, subject, body_keyword)|
      payload = deliver_payload(mail)

      assert_equal [ { email: admin.email } ], payload[:to]
      assert_equal subject, payload[:subject]
      assert_includes payload[:text_body], body_keyword
      assert_match(/\Abd\.[0-9a-f]{64}\z/, payload[:idempotency_key])
    end
  end

  # ── 봉투 from 방어(지시 — credentials 유무와 무관하게 봉투 유효) ──────────

  test "봉투 from은 credentials 유무와 무관하게 항상 유효하고 부재 시 DEFAULT_FROM_EMAIL로 폴백한다" do
    # ambient(등록 여부 무관) — 봉투는 항상 유효한 이메일 주소다. 등록된 환경에서는 그 주소·
    # 표시명이 유지되므로 특정 값 의존 없이 유효성만 단정한다.
    assert_match(/\A[^<>\s]+@[^<>\s]+\z/,
                 ApplicationMailer.mailer_from_header[/([^<>\s]+@[^<>\s]+)/, 1].to_s,
                 "mailer_from_header는 유효한 발신 주소를 포함한다")
    [ PasswordsMailer.reset(users(:alpha)), AdminMailer.locked_out(admins(:ops)) ].each do |mail|
      assert_equal 1, mail.message.from.size
      assert_match(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/, mail.message.from.sole,
                   "봉투 from 파탄(Mail 2.9.1 SmtpEnvelope blank from) 방어")
    end

    # 부재(밀봉) — 폴백 상수로 격리 검증. class-level default은 부트 시점에 계산돼 있으므로
    # 밀봉한 뒤 재평가하고 원복한다.
    original = ApplicationMailer.default
    with_sealed_outbound_mail_credentials do
      ApplicationMailer.default from: ApplicationMailer.mailer_from_header
      assert_equal "badeuldon@veloloop.kr", ApplicationMailer.mailer_from_header
      assert_equal [ "badeuldon@veloloop.kr" ], PasswordsMailer.reset(users(:alpha)).message.from
      assert_equal [ "badeuldon@veloloop.kr" ], AdminMailer.locked_out(admins(:ops)).message.from
    end
  ensure
    ApplicationMailer.default original
  end

  private

  def deliver_payload(message_delivery)
    fake = FakeOutboundMailClient.new
    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) { message_delivery.deliver_now }
    end
    fake.calls.sole
  end
end

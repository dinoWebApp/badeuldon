require "test_helper"
require_relative "../../test_helpers/fake_outbound_mail_client"
require_relative "../../test_helpers/outbound_mail_stubbing"
require_relative "../../test_helpers/portone_stubbing"

# OutboundMail::DeliveryJob — deliver_later 전용 배달 잡(F-EMAIL Phase 6 — 05_review C-1·W-5).
# C-1 회귀가 본 파일의 핵심이다: 내용 해시 기반 키에서는 본문이 정적인 보안 통보(AUTH-7.4 신규
# IP·AUTH-7.3 잠금)의 반복 이벤트가 202 idempotent_replay로 무음 소멸했다. 잡 식별자 키 전환으로
# ① 새 이벤트(새 job_id)는 서로 다른 키로 실제 발송되고 ② 같은 잡의 재시도(retry_job이 job_id
# 보존)는 같은 키로 API 멱등 흡수(중복 발송 없음 — SEC-5)를 동시에 검증한다. retryable 재시도
# 5회·비재시도 버림·헤더의 payload 미유출도 함께 단정한다. 실호출은 0건이다.
# 잡→DeliveryMethod(:outbound_mail_api) 체인은 production 시뮬레이션
# (with_outbound_mail_delivery — 클래스 레벨 배달 설정 3종)으로 수행한다.
class OutboundMail::DeliveryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include OutboundMailStubbing
  include PortOneStubbing

  TIMEOUT_ERROR = OutboundMail::ApiError.new(status: nil, code: "TIMEOUT", message: "execution expired")
  REJECTED_ERROR = OutboundMail::ApiError.new(status: 400, code: "INVALID_REQUEST",
                                              message: "raw-response-body-must-not-appear")
  # production credentials(outbound_mail.from_email 등)에 해당하는 발신자 — 시뮬레이션 settings로 주입
  DELIVERY_SETTINGS = { from_email: "no-reply@veloloop.kr", from_name: "받을돈",
                        reply_to: "contact@veloloop.kr" }.freeze

  # ── C-1 회귀(최우선) — 이벤트별 유일 키(지시 2) ─────────────────────────

  test "같은 admin·같은 IP의 두 번째 new_login 이벤트는 서로 다른 키로 실제 2회 발송된다 (C-1)" do
    fake = FakeOutboundMailClient.new

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        perform_enqueued_jobs do
          OutboundMail::DeliveryJob.perform_later("AdminMailer", "new_login", "deliver_now",
                                                  args: [ admins(:ops), "10.9.9.9" ])
          OutboundMail::DeliveryJob.perform_later("AdminMailer", "new_login", "deliver_now",
                                                  args: [ admins(:ops), "10.9.9.9" ])
        end
      end
    end

    assert_equal 2, fake.calls.size, "반복 이벤트가 idempotent_replay로 흡수되지 않고 2회 발송된다"
    keys = fake.idempotency_keys
    assert_not_equal keys[0], keys[1], "본문이 정적이어도 새 이벤트(새 job_id)는 새 키다"
    keys.each do |key|
      assert_match(/\Ajob\.[A-Za-z0-9._-]+\z/, key, "잡 경로 키는 job.<정제 job_id>다")
      assert_includes 8..128, key.length, "API 규격 8~128자(OUTBOUND_MAIL_API.md §2)"
    end
  end

  test "잠금 통보(locked_out) 반복 이벤트도 잡 키로 이벤트별 실발송된다 (C-1 — AUTH-7.3)" do
    fake = FakeOutboundMailClient.new

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        perform_enqueued_jobs do
          OutboundMail::DeliveryJob.perform_later("AdminMailer", "locked_out", "deliver_now",
                                                  args: [ admins(:ops) ])
          OutboundMail::DeliveryJob.perform_later("AdminMailer", "locked_out", "deliver_now",
                                                  args: [ admins(:ops) ])
        end
      end
    end

    assert_equal 2, fake.calls.size
    assert_not_equal fake.idempotency_keys.first, fake.idempotency_keys.last
  end

  # ── 재시도 동일 키(SEC-5) ───────────────────────────────────────────────

  test "같은 job_id로 잡을 다시 수행하면 같은 키를 쓴다 (재시도 멱등의 근거)" do
    fake = FakeOutboundMailClient.new
    job = OutboundMail::DeliveryJob.new
    job.job_id = "bd-fixed-uuid-1"

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        job.perform("AdminMailer", "locked_out", "deliver_now", args: [ admins(:ops) ])
        job.perform("AdminMailer", "locked_out", "deliver_now", args: [ admins(:ops) ])
      end
    end

    assert_equal [ "job.bd-fixed-uuid-1", "job.bd-fixed-uuid-1" ], fake.idempotency_keys
  end

  test "retryable 오류는 같은 job_id·같은 키로 재시도되고 두 번째에 성공한다 (SEC-5·W-5)" do
    fake = FakeOutboundMailClient.new(raise_on: ->(_payload, call_count) { TIMEOUT_ERROR if call_count == 1 })

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        OutboundMail::DeliveryJob.perform_later("AdminMailer", "locked_out", "deliver_now",
                                                args: [ admins(:ops) ])
        original_job_id = queue_adapter.enqueued_jobs.sole["job_id"]

        perform_enqueued_jobs # 1차 시도 — TIMEOUT → retry_on이 재적재
        assert_equal 1, fake.calls.size, "1차 시도 후 재시도는 아직 대기 중이다"

        retried_payload = queue_adapter.enqueued_jobs.sole
        assert_equal original_job_id, retried_payload["job_id"],
                     "retry_job은 같은 job_id로 재적재된다(같은 키 재사용의 근거)"
        assert retried_payload["scheduled_at"], "재시도는 백오프(polynomially_longer)로 예약된다"

        travel 1.hour
        perform_enqueued_jobs # 재시도 — 성공
      end
    end

    assert_equal 2, fake.calls.size
    assert_equal fake.idempotency_keys.first, fake.idempotency_keys.last,
                 "재시도는 같은 키 — API 멱등 흡수(idempotent_replay)로 중복 발송 없음"
  end

  test "retryable 코드는 perform에서 재상승해 retry_on으로 전파된다 (버림되지 않는다)" do
    fake = FakeOutboundMailClient.new(raise_on: TIMEOUT_ERROR)
    job = OutboundMail::DeliveryJob.new
    job.job_id = "bd-retryable-uuid"

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        error = assert_raises(OutboundMail::ApiError) do
          job.perform("AdminMailer", "locked_out", "deliver_now", args: [ admins(:ops) ])
        end
        assert_predicate error, :retryable?
      end
    end
  end

  test "5회 소진 시 예외가 재상승해 잡 실패로 가시 기록된다 (attempts: 5)" do
    fake = FakeOutboundMailClient.new(raise_on: TIMEOUT_ERROR) # 항상 실패

    with_outbound_mail_client(fake) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        OutboundMail::DeliveryJob.perform_later("AdminMailer", "locked_out", "deliver_now",
                                                args: [ admins(:ops) ])

        assert_raises(OutboundMail::ApiError) do
          5.times do
            perform_enqueued_jobs
            travel 1.hour
          end
        end
      end
    end

    assert_equal 5, fake.calls.size, "5회 시도(1+재시도 4) 후 종결된다"
  end

  # ── 비재시도 버림(discard) ──────────────────────────────────────────────

  test "비재시도 코드(4xx)는 재시도 없이 버려지고 code·status만 로그에 남는다 (P4)" do
    fake = FakeOutboundMailClient.new(raise_on: REJECTED_ERROR)

    with_outbound_mail_client(fake) do
      OutboundMail::DeliveryJob.perform_later("AdminMailer", "locked_out", "deliver_now",
                                              args: [ admins(:ops) ])

      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        with_outbound_mail_logger do |io|
          perform_enqueued_jobs # 예외가 밖으로 나오지 않는다(잡 성공으로 종결 — 버림)

          assert_empty queue_adapter.enqueued_jobs, "재적재가 없다"
          line = io.string[/\[OUTBOUND_MAIL:discard\].*/]
          assert_not_nil line, "버림 기록이 있다"
          assert_includes line, "code=INVALID_REQUEST"
          assert_includes line, "status=400"
          assert_includes line, "job_id="
          assert_not_includes line, "raw-response-body-must-not-appear",
                              "message는 원문 응답 본문을 운반할 수 있어 기록하지 않는다"
          assert_not_includes line, admins(:ops).email, "수신자 미기록"
        end
      end
    end

    assert_equal 1, fake.calls.size, "1회 시도 후 종결(재시도 없음)"
  end

  test "retry_on이 OutboundMail::ApiError에 선언돼 있다 (W-5 — 01_plan 재시도 정책)" do
    assert_includes OutboundMail::DeliveryJob.rescue_handlers.map(&:first),
                    "OutboundMail::ApiError",
                    "부모 MailDeliveryJob(retry_on 부재 — Rails 8.1 실측)과 달리 재시도가 선언된다"
  end

  # ── 헤더·키 유출 방지(03 §1 헤더는 payload JSON으로 유출되지 않는다) ──────

  test "잡 키는 발송 payload JSON에 유출되지 않고 Idempotency-Key 헤더로만 전달된다" do
    transport = FakeOutboundMailTransport.new(response: ok_202)
    real_client = OutboundMail::ClientService.new(base_url: "https://mail-api.example.test",
                                                  token: "bd-test-token")

    with_outbound_mail_client(real_client) do
      with_outbound_mail_delivery(DELIVERY_SETTINGS) do
        with_http_transport(transport) do
          OutboundMail::DeliveryJob.perform_later("AdminMailer", "new_login", "deliver_now",
                                                  args: [ admins(:ops), "10.9.9.9" ])
          perform_enqueued_jobs
        end
      end
    end

    request = transport.requests.sole
    assert_match(/\Ajob\./, request["Idempotency-Key"], "잡 키가 헤더로 승격된다")
    body = JSON.parse(request.body)
    assert_not_includes body.keys, "idempotency_key", "키는 JSON 바디에 없다"
    assert_not_includes body["text_body"], "job.", "헤더·키가 메일 본문으로 유출되지 않는다"
    assert_not_includes body["html_body"], "job."
    assert_equal [ { "email" => admins(:ops).email } ], body["to"]
  end

  private

  def ok_202
    Net::HTTPAccepted.new("1.1", "202", "Accepted").tap do |response|
      response.instance_variable_set(:@read, true)
      response.body = { success: true, data: { id: "mail_job_1", message_id: "<job@veloloop.kr>",
                                               status: "accepted_by_postfix" } }.to_json
    end
  end
end

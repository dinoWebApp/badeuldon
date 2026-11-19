# F-EMAIL — deliver_later 전용 배달 잡(2026-11-20 Phase 6 — 05_review C-1·W-5).
# OutboundMail::DeliveryMethod의 멱등 키를 잡 식별자 기반으로 만든다: 렌더 후 배달 직전에
# X-BD-Outbound-Idempotency 헤더로 "job.<job_id>"를 심고, DeliveryMethod는 키 파생 시
# 이 헤더를 내용 해시보다 우선한다(delivery_method.rb 모듈 주석 참조).
#
# 잡 키의 성질(SEC-5 — 기존 내용 해시 키의 두 결함 해소):
#   · 이벤트마다 유일 — 새 deliver_later = 새 job_id = 새 키. 본문이 정적인 보안 통보
#     (AUTH-7.3 잠금·AUTH-7.4 신규 IP)도 이벤트마다 실제로 발송된다. 내용 해시 기반에서는
#     같은 (수신자, IP)의 두 번째 이벤트가 202 idempotent_replay로 영구 흡수돼 무음 소멸했다(C-1).
#   · 재시도마다 동일 — retry_job이 같은 인스턴스를 재 enqueue해 job_id가 보존된다(Rails 8.1
#     activejob/exceptions.rb 실측) → 같은 키 재사용 → API 멱등 흡수로 중복 발송 없음.
#   · 재시도 정책(W-5 — 01_plan "API 5xx/429 시 잡 재시도") — retryable?(타임아웃·접속 실패·
#     429·5xx 등 모호 실패·일시 장애)만 polynomially_longer 백오프로 5회 재시도한다. 비재시도
#     코드(4xx·IDEMPOTENCY_CONFLICT 등 구성·스펙 오류)는 재시도해도 동일하게 실패하므로 버린다.
#     5회 소진 시 예외가 재상승해 잡 실패로 가시 기록된다(Solid Queue). 잡 밖 경로(직접
#     deliver_now·deliver!)는 이 잡을 거치지 않아 재시도 없다 — 폴백 키·실패 가시는 기존대로.
#
# 헤더는 메모리상의 Mail 객체에만 존재한다 — DeliveryMethod#build_payload가 to·subject·본문 등
# 명시 필드로 API payload를 재조립하므로 헤더·키가 payload JSON이나 발송 이메일로 유출되지 않는다.
module OutboundMail
  class DeliveryJob < ActionMailer::MailDeliveryJob
    IDEMPOTENCY_KEY_HEADER = DeliveryMethod::IDEMPOTENCY_KEY_HEADER
    DISCARD_LOG_TAG = "[OUTBOUND_MAIL:discard]"

    retry_on OutboundMail::ApiError, wait: :polynomially_longer, attempts: 5

    # ActionMailer::MailDeliveryJob#perform의 렌더 단계와 배달 단계 사이에 헤더 주입을 끼운다.
    # 렌더 본문은 부모 perform을 그대로 복제해 kwargs·params 분기 등 상위 규약 변경을 따른다.
    def perform(mailer, mail_method, delivery_method, args:, kwargs: nil, params: nil)
      message = render_message(mailer, mail_method, args:, kwargs:, params:)
      inject_idempotency_key(message)
      message.send(delivery_method)
    rescue OutboundMail::ApiError => error
      raise if error.retryable? # retry_on으로 — 같은 job_id = 같은 키로 안전 재시도

      # 비재시도 코드는 버린다(discard). message는 오류 원문 응답 본문을 운반할 수 있어
      # code·status만 기록한다(본문·수신자 미노출 — P4).
      Rails.logger.error("#{DISCARD_LOG_TAG} 비재시도 ApiError 버림 code=#{error.code} " \
                         "status=#{error.status.inspect} job_id=#{job_id}")
    end

    private

    def render_message(mailer, mail_method, args:, kwargs:, params:)
      mailer_class = params ? mailer.constantize.with(params) : mailer.constantize
      if kwargs
        mailer_class.public_send(mail_method, *args, **kwargs)
      else
        mailer_class.public_send(mail_method, *args)
      end
    end

    def inject_idempotency_key(message)
      # job_id는 SecureRandom.uuid(Rails 8.1 activejob/core.rb 실측 — [a-f0-9-])라 문자셋 위반이
      # 없으나, 정제를 유지해 생성기 교체·미래 변경에도 API 규격(8~128자·[A-Za-z0-9._-])을 보장한다.
      sanitized = job_id.to_s.gsub(/[^A-Za-z0-9._-]/, "")
      return if sanitized.blank?

      message[IDEMPOTENCY_KEY_HEADER] = "job.#{sanitized}"
    end
  end
end

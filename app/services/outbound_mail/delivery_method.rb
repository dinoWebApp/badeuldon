# ActionMailer 커스텀 배달 방식(F-EMAIL — AUTH-8·AUTH-7.4/7.6·2026-11-20 구현 확정 PRD v0.43).
# 기존 메일러(PasswordsMailer.reset·AdminMailer 3종)와 deliver_later 호출부를 한 줄도 수정
# 없이 자체 Outbound Mail API로 전환하는 것이 이 설계의 목적이다 — 메일러는 렌더만 하고,
# 발신 채널 교체는 배달 방식 한 곳에서 일어난다.
#
# 등록·활성: config/initializers/outbound_mail.rb가 :outbound_mail_api로 등록하고,
# production.rb가 config.action_mailer.delivery_method = :outbound_mail_api로 지정한다.
# Rails 규약상 initialize(settings)는 config.action_mailer.outbound_mail_api_settings 해시를
# 받는다 — 테스트는 settings[:client](전송 계층 stub)와 settings[:from_email|from_name|reply_to]
# (발신자 주입)로 검증한다. 주입이 없으면 credentials(:outbound_mail)을 기본값으로 읽는다.
#
# Idempotency-Key(SEC-5 — 발송 멱등): 파생 순서는 ① 잡 헤더 우선 → ② 내용 해시 폴백이다
# (2026-11-20 Phase 6 — 05_review C-1·W-2 반영. message_id 기반이 불가능함은 기존 실측대로 —
# mail.message_id는 렌더 직후 nil이고 mail 2.9.1이 배달 중 난수로 채운다).
# ① 잡 경로 — deliver_later는 production.rb가 지정한 OutboundMail::DeliveryJob으로 배달되며,
#   렌더 후 X-BD-Outbound-Idempotency 헤더("job.<job_id>")를 심는다(잡 클래스 주석 참조).
#   이 키는 이벤트마다 유일(새 deliver_later = 새 job_id)·재시도마다 동일(retry_job이 job_id
#   보존 — Rails 8.1 실측)이라, 본문이 정적인 보안 통보(AUTH-7.3 잠금·AUTH-7.4 신규 IP)도
#   이벤트마다 실발송되고 재시도는 API 멱등 흡수(idempotent_replay)로 중복이 없다 — 내용 해시
#   기반의 "반복 이벤트 영구 흡수" 결함(C-1)을 해소한다. 재렌더로 본문이 바뀌는 재설정 메일
#   (AUTH-8·AUTH-7.6)은 렌더마다 새 링크가 나오며, 재시도가 409(같은 키+다른 payload)가 되는
#   유일한 경계는 1차 시도가 서버 접수 후 응답만 소실된 경우다 — 이때 1차 메일은 이미 발송된
#   상태이므로 DeliveryJob의 비재시도 버림이 정답이다(신규 이벤트는 어차피 새 job_id).
# ② 폴백 — 헤더 부재, 즉 잡 밖 경로(직접 deliver_now·deliver! 호출·테스트)는 렌더 결과의
#   결정적 필드(수신자·제목·본문)의 SHA-256으로 파생한다(기존 설계 유지). 이 키는 to·subject·
#   본문만 커버하므로 from.name·reply_to·cc·bcc가 바뀌면 같은 키+다른 payload(409)가 가능하고,
#   같은 내용의 새 이벤트는 흡수된다 — 기존 주석의 "같은 키 ↔ 같은 payload 구조적 보장" 주장은
#   성립하지 않으며(W-2), 잡 밖 1회성 경로 한정의 알려진 한계로 문서화한다.
# 재시도 정책은 DeliveryJob이 담당한다(retry_on ApiError — retryable? 코드만 5회·
# polynomially_longer 백오프, 비재시도 코드는 버림). 부모 ActionMailer::MailDeliveryJob에는
# retry_on이 없어(실측) 잡 밖 경로는 재시도 없이 실패로 가시 기록된다.
# 키 길이·문자셋: "bd."+SHA-256 hex 64자 = 67자·"job."+UUID = 40자 — API 규칙(8~128자·
# [A-Za-z0-9._-]) 충족. ClientService가 송신 직전 재검증한다.
#
# 폴백: client(credentials 기본값)가 configured? == false면 — 즉 outbound_mail.token 미등록 —
# 실호출 없이 로그 기록 후 정상 종료한다. NOTI-3(NO_TEMPLATE skip)과 같은 선례로, credentials
# 등록 전까지 기존 동작(로그 발송 대체)을 유지해 무중단 전환을 보장한다. API 호출 실패는
# ApiError 그대로 상승한다 — production의 raise_delivery_errors = true와 만나 잡 실패로 기록된다.
require "digest"
require "json"

module OutboundMail
  class DeliveryMethod
    IDEMPOTENCY_KEY_PREFIX = "bd."
    IDEMPOTENCY_KEY_HEADER = "X-BD-Outbound-Idempotency"
    FALLBACK_LOG_TAG = "[OUTBOUND_MAIL:fallback]"
    SENT_LOG_TAG = "[OUTBOUND_MAIL:sent]"

    # 표준 배달 방식 규격 — Mail 2.9.1의 Message#deliver!(bang)가 delivery_method.settings
    # [:return_response]를 참조한다. 현재 호출부는 non-bang 경로(do_delivery → deliver!)라
    # 무영향이나, 임의 경로의 message.deliver! 대비 Rails 관례 정합 방어(@settings는
    # initialize에서 저장 — settings 주입 seam은 그대로).
    attr_accessor :settings

    def initialize(settings = {})
      @settings = settings
      @from_email = settings[:from_email] || Rails.application.credentials.dig(:outbound_mail, :from_email)
      @from_name = settings[:from_name] || Rails.application.credentials.dig(:outbound_mail, :from_name)
      @reply_to = settings[:reply_to] || Rails.application.credentials.dig(:outbound_mail, :reply_to)
    end

    def deliver!(mail)
      client = @settings[:client] || ClientService.new
      unless client.configured?
        # 본문·개인정보는 기록하지 않는다(수신자는 마스킹·제목만 — W-3).
        Rails.logger.info("#{FALLBACK_LOG_TAG} outbound_mail credentials 미구성 — 발송 대신 로그 기록 " \
                          "to=#{masked_recipients(mail.to)} subject=#{mail.subject.to_s.inspect}")
        return
      end

      snapshot = client.send_email(build_payload(mail))
      # 성공 발송 기록(P4 로그 수준 — W-4): API 접수 식별자를 1행으로 남긴다. 수신자는
      # 폴백 로그와 같은 마스킹 기준을 통일해 적용한다(W-3).
      Rails.logger.info("#{SENT_LOG_TAG} 접수 id=#{snapshot[:id].inspect} " \
                        "message_id=#{snapshot[:message_id].inspect} status=#{snapshot[:status].inspect} " \
                        "to=#{masked_recipients(mail.to)}")
      snapshot
    end

    private

    # OUTBOUND_MAIL_API.md §2 요청 바디 조립 — text_body/html_body 중 하나 이상이 API 요건이라
    # 본문이 없으면 네트워크 왕복 없이 fail-fast한다. 첨부는 v1 미지원(재설정·보안 통보 메일에
    # 불요 — 추후 필요 시 attachments 필드로 확장).
    def build_payload(mail)
      text_body, html_body = extract_bodies(mail)
      if text_body.blank? && html_body.blank?
        raise ApiError.new(status: nil, code: "INVALID_REQUEST",
                           message: "메일 본문 파트가 없습니다(text_body/html_body 중 하나 이상 필요)")
      end

      {
        idempotency_key: idempotency_key(mail, text_body, html_body),
        from: { email: from_email, name: @from_name.presence }.compact,
        to: recipients(mail.to),
        cc: recipients(mail.cc),
        bcc: recipients(mail.bcc),
        reply_to: @reply_to.presence ? { email: @reply_to } : nil,
        subject: mail.subject.to_s,
        text_body: text_body,
        html_body: html_body
      }.compact
    end

    # from·reply_to는 credentials로 강제한다 — API는 클라이언트별 사전 허용 발신 주소만 수용
    # 한다(SENDER_NOT_ALLOWED 403). 메일러·default from이 지정한 주소는 표시 참고일 뿐이며
    # 페이로드에서 정책 주소로 교체된다. from_email 누락은 구성 오류로 fail-fast(폴백이 아니라
    # 보이게 — 토큰은 있는데 발신 주소 정책을 놓친 운영 실수를 조용히 통과시키지 않는다).
    def from_email
      email = @from_email.presence
      unless email
        raise ApiError.new(status: nil, code: "MISSING_CREDENTIALS",
                           message: "outbound_mail.from_email credentials가 누락되었습니다 — " \
                                    "allow_sender로 등록된 발신 주소를 설정하세요")
      end
      email
    end

    # multipart/alternative(우리 메일러 표준 — text+html 뷰 쌍)와 단일 파트 모두 지원.
    def extract_bodies(mail)
      if mail.multipart?
        [ mail.text_part&.body&.to_s, mail.html_part&.body&.to_s ]
      elsif mail.mime_type == "text/html"
        [ nil, mail.body.to_s ]
      else
        [ mail.body.to_s, nil ]
      end
    end

    def recipients(addresses)
      Array(addresses).map { |email| { email: email } }
    end

    # 수신자 이메일 마스킹(W-3) — 로컬부 앞 2자 + ***@도메인. 로그에 전체 주소를 남기지 않는다.
    def masked_recipients(addresses)
      Array(addresses).map { |email| masked_email(email) }.join(",")
    end

    def masked_email(email)
      local, delimiter, domain = email.to_s.partition("@")
      return email.to_s if delimiter.blank? # @ 없는 비정형 값 — 마스킹할 로컬부가 없어 원형 유지

      "#{local.slice(0, 2)}***@#{domain}"
    end

    # 모듈 주석의 Idempotency-Key 설계 참조 — ① 잡 헤더 우선 → ② 내용 해시 폴백(잡 밖 경로).
    def idempotency_key(mail, text_body, html_body)
      from_job = mail[IDEMPOTENCY_KEY_HEADER]&.value.to_s
      return from_job if from_job.present?

      IDEMPOTENCY_KEY_PREFIX + Digest::SHA256.hexdigest(
        JSON.generate([ Array(mail.to), mail.subject.to_s, text_body, html_body ])
      )
    end
  end
end

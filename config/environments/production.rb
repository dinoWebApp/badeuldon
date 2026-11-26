require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # CF Tunnel이 SSL을 종단하고 앱은 http 수신 — 요청을 https로 간주한다(force_ssl 전제).
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Rails 8.1에서 production 기본값이 아니므로 명시한다(assume_ssl과 짝 — CF 종단 구조 전제).
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # F-EMAIL — 자체 Outbound Mail API(OUTBOUND_MAIL_API.md)로 발송한다. credentials
  # outbound_mail.token 미등록 시 DeliveryMethod가 로그 폴백으로 흡수하므로
  # raise_delivery_errors = true는 안전하다(등록 전 무중단·등록 후 API 실패는 예외 상승).
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :outbound_mail_api

  # deliver_later 잡 클래스 전역 지정(F-EMAIL C-1·W-5) — 기존 4곳 deliver_later 호출부를
  # 수정 없이 OutboundMail::DeliveryJob으로 승격해 멱등 키를 잡 식별자 기반으로 만든다
  # (이벤트마다 유일·재시도 동일 키·retryable 5회 재시도 — SEC-5). 문자열 지정은 Action
  # Mailer railtie가 ActionMailer::Base 로드 시점(on_load — production은 eager load 중)에
  # constantize하므로 app/ 자동 로딩 확립 후 상수화돼 부트 순서 안전. 개발·테스트 환경은
  # 기존 잡(ActionMailer::MailDeliveryJob)을 유지해 기존 테스트 단정에 영향이 없다.
  config.action_mailer.delivery_job = "OutboundMail::DeliveryJob"

  # Set host to be used by links generated in mailer templates.
  # F-EMAIL — 재설정 링크가 실제 도메인(https)으로 생성되게 한다(기존 example.com).
  config.action_mailer.default_url_options = { host: "badeuldon.kr", protocol: "https" }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # PLAN-5 — 운영만 포트원 라이브 채널 키를 쓴다(규약 §9.4 — 환경 분기는 config 플래그로).
  # 다른 환경 설정 파일에는 정의하지 않는다 — 미정의 환경은 테스트 채널(fail-closed,
  # 판정은 PortOne::ChannelKey.live_channel? 단일).
  config.x.portone_live_channel = true

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

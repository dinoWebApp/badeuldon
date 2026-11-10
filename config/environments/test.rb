# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # CI는 master key 미주입(RAILS_MASTER_KEY 주석)으로 credentials 복호화 불가 —
  # Admin#otp_secret(encrypts) 테스트가 ActiveRecord::Encryption::Errors::Configuration으로
  # 전멸한 실측(GitHub Actions ea43919)에 따른 test 전용 고정 키. 테스트 데이터만 암호화하므로
  # 고정 상수로 충분하며, 운영·개발은 credentials.yml.enc의 active_record_encryption 키를 그대로 사용(무영향).
  # Rails 요건: primary_key 12자 이상 · key_derivation_salt 20자 이상 — 아래 문자열은 모두 충족.
  config.active_record.encryption.primary_key = "test_primary_key_#{Rails.application.class.name}"
  config.active_record.encryption.deterministic_key = "test_deterministic_key_#{Rails.application.class.name}"
  config.active_record.encryption.key_derivation_salt = "test_key_derivation_salt_#{Rails.application.class.name}"
end

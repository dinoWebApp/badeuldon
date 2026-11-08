require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Badeuldon
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # TIME-1: 모든 일정·발송 기준 시간대는 KST 고정 (PRD §6.17)
    config.time_zone = "Seoul"

    # ko locale: 한국 서비스 — 기본 로케일 ko, 헤더·날짜·속성명 기본번역은 rails-i18n 사전에 위임
    config.i18n.available_locales = [ :en, :ko ]
    config.i18n.default_locale = :ko
    # config.eager_load_paths << Rails.root.join("extras")
  end
end

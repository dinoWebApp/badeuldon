require "test_helper"

# 병렬 배치(2026-11-16) 3-S 통합 회귀 테스트 — 태스크 A(폰트 캐시 헤더·en.yml 잔존 정리·
# Stimulus 정리)와 공통 결선(마이그레이션 컬럼·routes·recurring·SURF-3 noindex)의
# 파일·스키마·I18n 존재 점검. JS 동작은 런타임 테스트 대상이 아니므로 존재 점검만 수행한다.
# 근거: _workspace/parallel/A/03_implementation.md·parallel/phase6/03_implementation.md.
class ParallelBatch3sRegressionTest < ActionDispatch::IntegrationTest
  fixtures :users
  # ── 태스크 A — 폰트 장기 캐시 헤더(W-3) ──

  test "deploy.yml은 Thruster CACHE_CONTROL을 갖는다 (폰트 장기 캐시)" do
    deploy = YAML.safe_load(File.read(Rails.root.join("config/deploy.yml")),
                            permitted_classes: [], aliases: true)
    cache_control = deploy.dig("env", "clear", "CACHE_CONTROL")
    assert_equal "public, max-age=31536000, immutable", cache_control,
                 "deploy.yml env.clear에 CACHE_CONTROL이 필요하다"
    assert File.exist?(Rails.root.join("public/fonts/PretendardVariable.woff2")),
           "셀프호스팅 폰트 파일이 public/fonts에 있어야 한다"
  end

  # ── 태스크 A — en.yml 잔존 정리 ──

  test "en.yml에는 한국어 문자열이 남아 있지 않다 (ko.yml 단일 소스 정리)" do
    content = File.read(Rails.root.join("config/locales/en.yml"))
    # 주석 행(문서 문자열)은 제외하고 키·값 본문만 검사한다
    body = content.lines.reject { |line| line.strip.start_with?("#") }.join
    assert_empty body.scan(/[가-힣]/),
                 "en.yml의 본문에 한국어가 남아 있다: #{body.lines.grep(/[가-힣]/).first}"
  end

  test "주요 모델 검증 키는 ko 로캘에서 해석 가능하다 (en.yml 정리 후 회귀)" do
    samples = [
      "activerecord.errors.models.user.attributes.email.blank",
      "activerecord.errors.models.user.attributes.password.blank",
      "activerecord.errors.models.invoice.attributes.due_on.blank",
      "activerecord.errors.models.invoice.attributes.base.total_amount_must_be_positive",
      "activerecord.errors.models.invoice_item.attributes.unit_price.greater_than_or_equal_to"
    ]
    samples.each do |key|
      assert I18n.exists?(key, :ko), "ko.yml에 #{key} 누락 — en.yml 정리 회귀"
    end
    assert_match(/[가-힣]/, I18n.t("activerecord.errors.models.user.attributes.email.blank", locale: :ko),
                 "ko 로캘 문구가 한국어로 해석되지 않았다")
  end

  # ── 태스크 A — Stimulus 정리 ──

  test "scaffold hello 컨트롤러는 제거됐고 portone 공통 모듈이 존재한다" do
    assert_not File.exist?(Rails.root.join("app/javascript/controllers/hello_controller.js"))
    assert File.exist?(Rails.root.join("app/javascript/controllers/portone_shared.js"))
  end

  # ── 3-S 통합 마이그레이션 컬럼 실측 ──

  test "3-S 마이그레이션 컬럼·인덱스가 스키마에 존재한다 (T3·T5·T6·T7)" do
    users_columns = User.column_names
    assert_includes users_columns, "remind_allowed_wdays"
    assert_includes users_columns, "remind_start_hour"
    assert_includes users_columns, "remind_end_hour"
    assert_includes users_columns, "noti2_digest_enabled"

    subscriptions_columns = Subscription.column_names
    assert_includes subscriptions_columns, "dunning_stage"
    assert_includes subscriptions_columns, "next_retry_at"
    assert_includes subscriptions_columns, "last_payment_failed_at"

    assert_includes MessageLog.column_names, "digest"

    index_names = ActiveRecord::Base.connection.indexes(:view_events).map(&:name)
    assert_includes index_names, "index_view_events_on_invoice_ip_viewed_at"
  end

  # ── 3-S routes·recurring 결선 ──

  test "NOTI-2 토글 경로(app_notification_settings_path)가 결선됐다" do
    assert_nothing_raised do
      path = Rails.application.routes.url_helpers.app_notification_settings_path
      assert_equal "/app/notification_settings", path
    end
  end

  test "recurring.yml에 주간 다이제스트 항목이 production·development 양쪽에 있다 (NOTI-2)" do
    recurring = YAML.safe_load(File.read(Rails.root.join("config/recurring.yml")),
                               permitted_classes: [], aliases: true)
    %w[production development].each do |env|
      entry = recurring.dig(env, "noti2_weekly_digest") || recurring["noti2_weekly_digest"]
      assert_not_nil entry, "recurring.yml #{env}에 noti2_weekly_digest 없음"
      assert_equal "Noti::WeeklyDigestJob", entry["class"]
      assert_match(/0 9 \* \* 1/, entry["schedule"])
    end
  end

  # ── SURF-3 — /app noindex(회귀) ──

  test "/app 응답은 noindex를 유지한다 (SURF-3)" do
    sign_in_as users(:gamma)
    get app_root_path
    assert_response :success
    assert_match(/noindex/, response.body)
  end
end

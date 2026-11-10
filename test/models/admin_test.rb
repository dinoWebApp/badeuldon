require "test_helper"

# Admin 모델 — AUTH-7.1(2FA TOTP·encrypts)·AUTH-7.3(5회 잠금 원자성 W-2)·ADMIN-1(role)
class AdminTest < ActiveSupport::TestCase
  setup { setup_admin_totp_secrets }

  test "role enum 기본값은 owner이고 staff를 지정할 수 있다 (ADMIN-1)" do
    assert_equal "owner", admins(:ops).role
    assert_equal "staff", admins(:staffuser).role
    admin = Admin.new(email: "x@example.com", password: "password1234")
    assert_equal "owner", admin.role
  end

  test "otp_secret은 DB에 암호문으로 저장되고 모델에서는 평문으로 복호화된다 (AUTH-7.1)" do
    admin = admins(:ops)
    raw = Admin.connection.select_value(
      Admin.where(id: admin.id).select(:otp_secret).to_sql
    )
    assert_not_equal admin.otp_secret, raw, "DB 원문이 평문이어서는 안 된다"
    assert_equal AdminSessionTestHelper::OPS_TOTP_SECRET, admin.reload.otp_secret
  end

  # ── verify_totp!(AUTH-7.1) ──────────────────────────────────────────────

  test "정상 코드 검증에 성공하고 스텝 카운터를 기록한다 (AUTH-7.1)" do
    admin = admins(:ops)
    travel_to Time.zone.at(Admin::OTP_STEP_SECONDS * 100_000) do
      code = totp_code(admin.otp_secret, Time.current)
      assert admin.verify_totp!(code, at: Time.current)
      assert_equal 100_000, admin.reload.otp_last_used_counter
    end
  end

  test "otp_secret이 없으면 검증은 항상 실패한다 (AUTH-7.1)" do
    assert_not admins(:newbie).verify_totp!("000000")
  end

  test "±1 스텝 경계 — 30초 전·후 코드는 수용하고 60초 전·후 코드는 거부한다 (AUTH-7.1)" do
    admin = admins(:ops)
    now = Time.zone.at(Admin::OTP_STEP_SECONDS * 100_000)
    travel_to now do
      # 뒤 1스텝(−30초) 수용
      assert admin.verify_totp!(totp_code(admin.otp_secret, now - 30), at: now),
             "−30초(1스텝 뒤) 코드는 drift 30초로 수용된다"
    end
    admin.update_column(:otp_last_used_counter, nil)

    travel_to now do
      # 앞 1스텝(+30초) 수용
      assert admin.verify_totp!(totp_code(admin.otp_secret, now + 30), at: now)
    end
    admin.update_column(:otp_last_used_counter, nil)

    travel_to now do
      assert_not admin.verify_totp!(totp_code(admin.otp_secret, now - 60), at: now)
      assert_not admin.verify_totp!(totp_code(admin.otp_secret, now + 60), at: now)
    end
  end

  test "동일 코드 재사용은 after 스텝 카운터로 차단한다 (AUTH-7.1)" do
    admin = admins(:ops)
    now = Time.zone.at(Admin::OTP_STEP_SECONDS * 100_000)
    travel_to now do
      code = totp_code(admin.otp_secret, now)
      assert admin.verify_totp!(code, at: now)
      # 리뷰어 제안 — 같은 시각에 동일 코드 2회차 검증은 재사용 방지로 항상 거부가 정상 동작이다
      assert_not admin.verify_totp!(code, at: now), "동일 스텝 코드 재제출은 차단된다"
      # 다음 스텝(+30초) 코드는 after 카운터보다 새 스텝이라 수용된다
      assert admin.verify_totp!(totp_code(admin.otp_secret, now + 30), at: now + 30)
    end
  end

  # ── record_failed_attempt!(AUTH-7.3 · W-2 원자성) ──────────────────────

  test "5회 실패에서 정확히 1회 잠금으로 전환한다 (AUTH-7.3)" do
    admin = admins(:ops)
    4.times do |i|
      assert_not admin.record_failed_attempt!, "#{i + 1}회차는 아직 잠금 아님"
    end
    assert admin.record_failed_attempt!, "5회차에 신규 잠금 true"
    assert admin.reload.locked?
    assert_not admin.record_failed_attempt!, "이미 잠긴 계정은 재전환하지 않는다"
  end

  test "동시 경합에서 잠금 전환·통보 근거는 단 1회이다 (W-2 재현)" do
    admin = admins(:ops)
    4.times { admin.record_failed_attempt! }
    # failed_attempts=4 시점의 stale 인스턴스 2개 — 동시 실패 경합 모사
    stale_a = Admin.find(admin.id)
    stale_b = Admin.find(admin.id)
    results = [ stale_a.record_failed_attempt!, stale_b.record_failed_attempt! ]
    assert_equal 1, results.count(true), "신규 잠금 전환은 정확히 1회만 true"
    assert_equal 1, Admin.locked.where(id: admin.id).count
  end

  test "reset_failed_attempts!와 unlock!은 잠금 상태를 원복한다 (AUTH-7.3)" do
    admin = admins(:ops)
    5.times { admin.record_failed_attempt! }
    assert admin.reload.locked?

    admin.unlock!
    assert_not admin.reload.locked?
    assert_equal 0, admin.failed_attempts

    admin.record_failed_attempt!
    admin.reload.reset_failed_attempts!
    assert_equal 0, admin.reload.failed_attempts
    assert_not admin.locked?
  end

  test "generate_otp_secret!은 최초 1회만 발급하고 재호출 시 유지된다 (AUTH-7.1)" do
    admin = admins(:newbie)
    assert_nil admin.otp_secret
    admin.generate_otp_secret!
    secret = admin.reload.otp_secret
    assert_not_nil secret
    admin.generate_otp_secret!
    assert_equal secret, admin.reload.otp_secret
  end

  test "provisioning_uri에 시크릿과 issuer가 포함된다 (AUTH-7.1)" do
    uri = admins(:ops).provisioning_uri
    assert_includes uri, "secret=#{AdminSessionTestHelper::OPS_TOTP_SECRET}"
    assert_includes uri, "issuer="
  end

  private

  def totp_code(secret, at)
    ROTP::TOTP.new(secret).at(at.to_i)
  end
end

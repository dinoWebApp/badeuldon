require "test_helper"

module AuditLogs
  class RecordServiceTest < ActiveSupport::TestCase
    test "action·ip를 기록한다 (ADMIN-2 단일 진입점)" do
      log = RecordService.call(admin: admins(:ops), action: "login_success", ip: "127.0.0.1")
      assert_equal "login_success", log.action
      assert_equal "127.0.0.1", log.ip
      assert_equal admins(:ops).id, log.admin_id
    end

    test "target을 다형 참조로 기록한다 (ADMIN-2)" do
      log = RecordService.call(admin: admins(:ops), action: "login_failed", target: admins(:staffuser))
      assert_equal "Admin", log.target_type
      assert_equal admins(:staffuser).id, log.target_id
    end
  end
end

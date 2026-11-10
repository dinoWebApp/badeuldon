User.where("email LIKE ?", "tb2-verify-%@example.com").destroy_all
user = User.create!(email: "tb2-verify-#{Time.current.to_i}@example.com", password: "password12345")
sub = user.subscription
ok = ->(label, cond) { puts(cond ? "PASS #{label}" : "FAIL #{label}") }

# 1) 활성 Plus 보유 시 grant_trial 금지
sub.update!(plan: :plus, status: :active, current_period_end: 3.days.from_now)
r1 = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "grant_trial" })
ok.("active_plus_grant_trial_denied", !r1.success? && r1.errors.first.include?("활성 Plus"))

# 2) trialing에서 extend_trial — current_period_end 연장
sub.update!(plan: :plus, status: :trialing, trial_ends_at: 5.days.from_now, current_period_end: 5.days.from_now)
before = sub.reload.current_period_end
r2 = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "extend_trial", months: "2" })
after = sub.reload.current_period_end
ok.("extend_trial_extends_period", r2.success? && after > before && sub.trial_ends_at == after)

# 3) cancel_subscription
r3 = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "cancel_subscription" })
ok.("cancel_subscription", r3.success? && sub.reload.cancelled?)

# 4) used_trial이면 grant_trial 재금지 — 1회 체험 후 재요청은 거부된다
r4a = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "grant_trial" })
ok.("first_grant_trial_ok", r4a.success? && sub.reload.trialing?)
r4 = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "grant_trial" })
ok.("used_trial_denied", !r4.success? && sub.reload.plus?)

# 5) toggle_suspension — 정지+세션 파기+감사 기록, 해제
user.sessions.create!(ip_address: "127.0.0.1", user_agent: "runner")
r5 = Admins::MemberAdminService.toggle_suspension!(admin: Admin.first, user:)
ok.("suspend_destroys_sessions_and_audits", r5.success? && user.reload.suspended? && user.sessions.count.zero? &&
  AuditLog.exists?(action: "member_suspend", target_type: "User", target_id: user.id))
r6 = Admins::MemberAdminService.toggle_suspension!(admin: Admin.first, user:)
ok.("unsuspend", r6.success? && user.reload.active? && AuditLog.exists?(action: "member_unsuspend"))

# 6) 알 수 없는 action → errors 반환
r7 = Admins::MemberAdminService.change_plan!(admin: Admin.first, user:, plan_params: { action: "haha" })
ok.("unknown_action_rejected", !r7.success?)

# 감사 로그 스코프
ok.("scopes", AuditLog.recent.limit(1).size == 1 && AuditLog.by_action("member_suspend").exists? &&
  AuditLog.by_admin(Admin.first.id).exists? && AuditLog.by_period(1.day.ago.strftime("%F"), nil).exists?)

user.destroy!
puts "done"

class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # F-ADMIN — 관리자 세션(U1 세션과 별도, AUTH-7.5). delegate는 Admin::BaseController에서만 쓴다.
  attribute :admin_session
  delegate :user, to: :session, allow_nil: true
  delegate :admin, to: :admin_session, allow_nil: true
end

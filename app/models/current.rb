class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # F-ADMIN — 관리자 세션(U1 세션과 별도, AUTH-7.5). delegate는 Admin::BaseController에서만 쓴다.
  attribute :admin_session
  # F-SALES — 영업 직원 세션(SALES-7 — U1·관리자와 별도). delegate는 Sales::BaseController에서만 쓴다.
  attribute :sales_rep_session
  delegate :user, to: :session, allow_nil: true
  delegate :admin, to: :admin_session, allow_nil: true
  delegate :sales_rep, to: :sales_rep_session, allow_nil: true
end

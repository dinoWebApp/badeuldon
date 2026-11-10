# ADMIN-3(Run B 확정) — 회원 계정 상태(active/suspended). 정지 시 로그인 차단+기존 세션
# 전부 파기. 기존 회원 전부 active로 시딩되는 default 0.
class AddStatusToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :status, :integer, default: 0, null: false
  end
end

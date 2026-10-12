# AUTH-1.3 — 최초 프로필 설정: 표시명/상호, 사업자 유형, 입금 계좌 3종(은행·계좌번호·예금주), 연락처.
# 전 컬럼 null 허용 — 가입 시점엔 미설정이 원칙이며, 프로필 저장(:profile 컨텍스트)에서 필수·형식 검증.
class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :display_name, :string
    add_column :users, :business_type, :integer
    add_column :users, :bank_name, :string
    add_column :users, :account_number, :string
    add_column :users, :account_holder, :string
    add_column :users, :phone, :string
  end
end

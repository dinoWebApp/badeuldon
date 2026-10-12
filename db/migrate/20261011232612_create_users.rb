class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    # U1 계정 — AUTH-1(이메일/비밀번호), AUTH-1.4(이메일 = 로그인 아이디, 필수·고유)
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end

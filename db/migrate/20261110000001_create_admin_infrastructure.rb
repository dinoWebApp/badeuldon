# F-ADMIN Run A — 관리자 기반 인프라 3테이블(AUTH-7·ADMIN-1·ADMIN-2).
# admins(전용 계정 — U1 users와 분리) · admin_sessions(12h 절대+2h 비활동 만료, AUTH-7.5) ·
# audit_logs(운영 감사, ADMIN-2 — action은 자유 문자열, RecordService 단일 진입점).
class CreateAdminInfrastructure < ActiveRecord::Migration[8.1]
  def change
    create_table :admins do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      # ADMIN-1 롤 — owner:1(최고 관리자, 기본) / staff:0(운영자). 숫자는 열거 안정성용.
      t.integer :role, null: false, default: 1
      # AUTH-7.1 — TOTP 시크릿(AES 암호화 저장 — encrypts). nil = 2FA 미등록.
      t.text :otp_secret
      t.datetime :otp_confirmed_at           # 2FA 활성화 판정(등록 완료 시각)
      t.integer :otp_last_used_counter       # 마지막 성공 TOTP 스텝 — 동일 코드 재사용 방지
      t.integer :failed_attempts, null: false, default: 0
      t.datetime :locked_at                  # AUTH-7.3 — 5회 연속 실패 시 잠금
      t.datetime :last_login_at
      t.string :last_login_ip               # AUTH-7.4 신규 IP 판정용(직전 로그인 IP)
      t.timestamps
    end
    add_index :admins, :email, unique: true

    create_table :admin_sessions do |t|
      t.references :admin, null: false, foreign_key: { on_delete: :cascade }
      t.string :token, null: false           # SecureRandom.urlsafe_base64(32) — 추측 불가
      t.datetime :expires_at, null: false    # 12시간 절대 만료(AUTH-7.5)
      t.datetime :last_activity_at, null: false  # 요청마다 갱신 — 2시간 무활동 만료
      t.string :ip
      t.timestamps
    end
    add_index :admin_sessions, :token, unique: true

    create_table :audit_logs do |t|
      t.references :admin, null: false, foreign_key: { on_delete: :cascade }
      # ADMIN-2 — action 값 확정(02 확정 해석 4): login_success · login_failed · lockout ·
      # new_ip_login · password_reset (+unlock 등 runner 절차)
      t.string :action, null: false
      t.string :target_type
      t.integer :target_id
      t.text :detail
      t.string :ip, limit: 45                # IPv6 최대 길이
      t.timestamps
    end
    add_index :audit_logs, :action
  end
end

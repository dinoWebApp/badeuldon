# F-SALES(SALES-1~7·AUTH-9·Q24) — 영업 도메인 통합 마이그레이션.
# ① sales_reps(영업 직원·감투 임원 — role 이원화·별도 계정 AUTH-7 준용 격리)
# ② sales_rep_sessions(별도 세션 — U1 Session·AdminSession과 분리)
# ③ sales_referral_codes(추천 코드 이력 — 주간 로테이션 SALES-2·P4 보존)
# ④ phone_verifications(휴대폰 SMS 인증 — AUTH-9)
# ⑤ users 확장(phone 부분 유니크 + 추천 어트리뷰션 SALES-3)
# ⑥ sales_commissions(월 정산 스냅샷 — SALES-5·Q24)
class CreateSalesDomainTables < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_reps do |t|
      t.string :email, null: false                       # 로그인 아이디(U1·admins와 별도 네임스페이스)
      t.string :password_digest, null: false             # has_secure_password
      t.string :name, null: false                        # 대시보드 표시 실명
      t.string :title                                    # 표시용 자유 텍스트(SALES-1 — CEO·영업 이사 등)
      t.integer :role, null: false, default: 0           # sales: 0(20%·12개월 캡) / officer: 1(15%·무기한)
      t.integer :commission_rate                         # 개별 요율 오버라이드 — null이면 역할 기본값
      t.integer :status, null: false, default: 0         # active: 0 / suspended: 1(정지 — 로그인 차단)
      t.integer :failed_attempts, null: false, default: 0 # AUTH-7.3 준용 — 연속 실패 잠금
      t.datetime :locked_at                              # 5회 도달 시 잠금 시각
      t.timestamps
    end
    add_index :sales_reps, :email, unique: true

    create_table :sales_rep_sessions do |t|
      t.string :token, null: false                       # SecureRandom.urlsafe_base64(32) — 추측 불가
      t.references :sales_rep, null: false, foreign_key: true
      t.datetime :expires_at, null: false                # 절대 만료(12시간)
      t.datetime :last_activity_at, null: false          # 비활동 만료 기준점(2시간)
      t.string :ip                                       # 발급 시점 접속 IP(기록 최소)
      t.timestamps
    end
    add_index :sales_rep_sessions, :token, unique: true

    # 추천 코드 이력 테이블(SALES-2) — 로테이션마다 새 행 발급·기존 행 valid_until 조기 종료.
    # 과거 어트리뷰션 감사는 이력 행으로 추적한다(P4).
    create_table :sales_referral_codes do |t|
      t.references :sales_rep, null: false, foreign_key: true
      t.string :code, null: false                        # 8자 안전 문자열 — 전역 유니크
      t.date :valid_from, null: false                    # 유효 시작일(KST 날짜)
      t.date :valid_until, null: false                   # 유효 종료일(포함) — 로테이션 시 조기 종료
      t.timestamps
    end
    add_index :sales_referral_codes, :code, unique: true
    add_index :sales_referral_codes, [ :sales_rep_id, :valid_until ]

    # 휴대폰 SMS 인증(AUTH-9) — 발송 이력 자체가 rate limit(1분 1회·1시간 3회) 판정 근거다.
    # code는 6자리 숫자·5분 만료·검증 시도 5회 제한·성공 시 consumed(1회용).
    create_table :phone_verifications do |t|
      t.string :phone, null: false                       # 하이픈 제거 숫자만(솔라피 규격과 동일 정규화)
      t.string :code, null: false
      t.datetime :expires_at, null: false
      t.integer :attempts, null: false, default: 0
      t.datetime :consumed_at                            # 성공 마킹 — 1회용 보장
      t.timestamps
    end
    add_index :phone_verifications, [ :phone, :created_at ]

    # users 확장 — SALES-3 어트리뷰션 + AUTH-9 번호 유일(신규 가입 한정 소급 없음 → null 허용).
    change_table :users, bulk: true do |t|
      t.string :referral_code_snapshot                   # 가입 시점 사용 코드 스냅샷(P4)
    end
    add_reference :users, :referred_by_sales_rep, foreign_key: { to_table: :sales_reps }
    # AUTH-9 — 번호 유일은 "값이 있을 때만"(부분 유니크). 기존 유저 phone null 다수 허용.
    # 인덱스 생성 전 레거시 데이터 정리(2026-11-19 운영 배포 실패 2회 실측 — 실제 중복: '' 2건·번호 1그룹·하이픈 1건).
    # 스캔 조건은 인덱스 조건(phone IS NOT NULL)과 정확히 일치시킨다 — 빈 문자열은 인덱스에 포함되므로 NULL로 정규화 필수.
    # ① 하이픈 정규화(User 모델과 동일 형태)·빈 문자열 → NULL ② 남은 중복은 첫 가입자(id 최소) 유지·나머지 NULL.
    say_with_time "phone 정규화(하이픈 제거·빈 문자열 NULL)" do
      exec_update("UPDATE users SET phone = REPLACE(phone, '-', '') WHERE phone LIKE '%-%'") +
        exec_update("UPDATE users SET phone = NULL WHERE phone = ''")
    end
    say_with_time "중복 phone 정리(첫 가입자 유지)" do
      dupes = select_rows(
        "SELECT phone, MIN(id) FROM users " \
        "WHERE phone IS NOT NULL GROUP BY phone HAVING COUNT(*) > 1"
      )
      dupes.each do |normalized, keep_id|
        exec_update(
          "UPDATE users SET phone = NULL " \
          "WHERE phone = '#{normalized}' AND id != #{keep_id}"
        )
      end
      dupes.size
    end
    add_index :users, :phone, unique: true, where: "phone IS NOT NULL",
              name: "index_users_on_phone_when_present"
    # 비고: down에서 데이터(정규화·NULL화)는 복구하지 않는다 — 원본은 마이그레이션 로그로만 추적.

    # 월 정산 스냅샷(SALES-5·Q24) — rep·연월 1행(복합 유니크). 지급 처리(mark paid) 후에는
    # 집계 재실행으로도 금액을 다시 쓰지 않는다(스냅샷 고정 — 서비스 가드).
    create_table :sales_commissions do |t|
      t.references :sales_rep, null: false, foreign_key: true
      t.integer :year, null: false                       # 대상 결제월(직전월 — KST)
      t.integer :month, null: false
      t.integer :base_amount, null: false, default: 0    # 기준 결제액 = 실차감액 합계(환불 제외)
      t.integer :rate, null: false                       # 스냅샷 시점 요율(rep.effective_rate 고정)
      t.integer :amount, null: false, default: 0         # 수수료 = base_amount × rate / 100 (절사)
      t.integer :status, null: false, default: 0         # pending: 0 / paid: 1
      t.datetime :paid_at                                # admin mark_paid 시각
      t.datetime :settled_at                             # 집계 실행 시각
      t.timestamps
    end
    add_index :sales_commissions, [ :sales_rep_id, :year, :month ], unique: true,
              name: "index_sales_commissions_on_rep_year_month"
  end
end

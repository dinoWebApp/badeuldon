# U1 사용자 — AUTH-1(이메일/비밀번호 인증만 제공), AUTH-1.4(이메일 = 로그인 아이디), AUTH-1.3(프로필)
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  # INV-7 — 반복 청구 스케줄(탈퇴 시 삭제). **invoices보다 먼저 선언 필수** — 연관 선언 순서가
  # 곧 dependent: :destroy 실행 순서라, recurring_invoices.last_invoice_id가 invoices FK
  # (on_delete: :restrict — P4 발행 기록 보존)를 참조한다. 스케줄이 invoices보다 늦게 파괴되면
  # restrict가 발화해 계정 삭제(ADMIN-3·AUTH-1.5)가 InvalidForeignKey로 파탄한다(B-1 교정).
  # 참조되는 쪽(invoices)보다 참조하는 자식(스케줄)이 먼저 선언돼야 한다 — 순서 변경 금지.
  has_many :recurring_invoices, dependent: :destroy
  # AUTH-1.5 — 연관 선언 순서가 곧 dependent: :destroy 실행 순서다. invoices는 clients를
  # 참조하므로 자식(청구서)을 손자·부모(거래처·품목)보다 먼저 선언해 탈퇴 연쇄 삭제 시
  # invoices.client_id 외래 키 위반(ActiveRecord::InvalidForeignKey)을 방지한다. 순서 변경 금지.
  has_many :invoices, dependent: :destroy # INV — 탈퇴 시 청구서 데이터 삭제(AUTH-1.5)
  has_many :clients, dependent: :destroy  # CLIENT-1 — 탈퇴 시 거래처 데이터 삭제(AUTH-1.5)
  has_many :items, dependent: :destroy    # CLIENT-2 — 탈퇴 시 품목 라이브러리 삭제(AUTH-1.5)
  # F-PLAN — 구독(1인 1행)·주문·수금 패스. 자식 참조가 없어 연쇄 순서 영향이 없다.
  has_one :subscription, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :payment_passes, dependent: :destroy
  # F-ADMIN Run C(ADMIN-7) — 공지 읽음 기록. 자식 참조가 없어 연쇄 순서 영향이 없다.
  has_many :notice_reads, dependent: :destroy
  # F-ADMIN Run C(ADMIN-8) — 1:1 문의 티켓. ticket_messages는 tickets의 dependent로 연쇄 삭제.
  has_many :tickets, dependent: :destroy
  # TAX-1 — 전자세금계산서 발행 기록(invoices보다 뒤 파괴돼도 FK 제약 없음 — tax_invoices가
  # invoices를 참조하므로 Rails dependent: :destroy는 부모 기준 역순 파괴로 안전하다).
  has_many :tax_invoices, dependent: :destroy
  # SALES-3 — 추천 어트리뷰션(가입 시 유효 코드로 귀속). optional — 추천 없는 가입이 기본.
  # rep 측(referred_users)이 restrict_with_error라 탈퇴 연쇄 삭제에 영향이 없다(자식이 아님).
  belongs_to :referred_by_sales_rep, class_name: "SalesRep", optional: true,
                                     inverse_of: :referred_users

  # AUTH-1.3 사업자 유형 — 사업자(business)·프리랜서(freelancer, 3.3% 원천징수 해당).
  # 미선택 허용: 가입 시점엔 결정하지 않고, 프로필 설정(:profile 컨텍스트)에서 필수가 된다.
  enum :business_type, { business: 0, freelancer: 1 }

  # TAX-1 — 과세유형(세금계산서 TaxType 매핑: 일반과세→과세(1)·간이과세→영세(2)·면세→면세(3)).
  # 기본값 일반과세(general) — 발행 설정 저장 시 U1이 명시 선택한다.
  enum :tax_type, { general: 0, simplified: 1, exempt: 2 }, default: :general

  # ADMIN-3(Run B 확정) — 계정 상태. suspended면 로그인 차단(SessionsController)이며
  # 정지 전환 시 기존 세션을 전부 파기한다(Admins::MemberAdminService). 해제 가능.
  # 탈퇴·데이터 파기(AUTH-1.5)는 Run C 재검토 대상 — 본 배치는 정지까지만.
  enum :status, { active: 0, suspended: 1 }, default: :active

  # AUTH-1.4 — 이메일 필수·고유(DB 고유 인덱스 위반을 500이 아닌 422 검증 실패로 처리)
  validates :email, presence: true, uniqueness: true

  # AUTH-1.3 — 프로필 저장 시 표시명·사업자 유형은 필수, 계좌 3종·연락처는 선택 입력(이후 수정 가능).
  # 가입(register/save)에는 적용되지 않는 컨텍스트 검증 — 미설정은 "프로필 미완료" 판정 근거.
  # (phone 형식 검증은 AUTH-9 단일 소스로 아래에서 전 컨텍스트 적용 — 프로필 중복 제거)
  validates :display_name, presence: true, on: :profile
  validates :business_type, presence: true, on: :profile
  validates :account_number, allow_blank: true, format: { with: /\A\d[\d-]{4,19}\z/ }, on: :profile

  # AUTH-1.4 — 이메일 대소문자·공백 정규화(로그인 아이디로서 동일 취급)
  normalizes :email, with: ->(e) { e.strip.downcase }
  # AUTH-1.3 — 표시명 앞뒤 공백 제거
  normalizes :display_name, with: ->(d) { d.strip }
  # AUTH-9 — 휴대폰 번호는 하이픈 제거 숫자만 저장(솔라피 규격과 동일 정규화·표시는 헬퍼).
  # 빈 입력은 nil로 — 부분 유니크 인덱스는 phone IS NOT NULL 조건이라 ''가 다수 저장되면 유일 위반.
  normalizes :phone, with: ->(p) { p.presence&.gsub(/\D/, "") }

  # AUTH-9 — 전화번호 유일(값 있을 때만 — null 다수 허용). DB 부분 유니크 인덱스와 이중 방어.
  # 형식은 하이픈 허용(정규화 이전 저장분 레거시 호환 — 신규 저장은 하이픈 제거 숫자만).
  validates :phone, uniqueness: { allow_blank: true },
                    format: { with: /\A\d{2,3}-?\d{3,4}-?\d{4}\z/,
                              message: "은(는) 휴대폰 번호 형식이어야 합니다" },
                    if: -> { phone.present? }
  # TAX-1 — 사업자번호는 하이픈 제외 숫자만 저장(바로빌 CorpNum 규격 — 정규화는
  # TaxInvoices::RegisterCorpService가 수행하고 여기선 저장 정합 검증만).
  validates :corp_num, allow_blank: true, format: { with: /\A\d{10}\z/,
                                                    message: "은(는) 하이픈 없는 10자리 숫자여야 합니다" }

  # F-PLAN(PLAN-1) — 가입 시 Free 구독 행을 보장한다. RegistrationsController뿐 아니라
  # 모든 생성 경로(콘솔·러너)에서 1인 1구독 불변식을 유지하기 위해 모델 콜백으로 둔다.
  after_create :create_free_subscription

  # ── PLAN-1 한도 판정 위임 ────────────────────────────────────────────────
  # Client·Invoice 검증과 컨트롤러 UI 분기(@limit_reached)가 공유하는 단일 판정점.
  # 구독 행이 없는 기존 사용자(기능 도입 이전 가입)는 Free 상수를 그대로 적용한다
  # (하위 호환 폴백 — 상수는 유지된다).

  def client_limit_reached?(current_count)
    return subscription.client_limit_reached?(current_count) if subscription

    current_count >= Client::FREE_CLIENT_LIMIT
  end

  def monthly_invoice_limit_reached?(current_count)
    return subscription.monthly_invoice_limit_reached?(current_count) if subscription

    # 폴백(Free 상수)에서도 수금 패스로 발행 가능 — 구독 판정점과 동일 기준(이슈 #7)
    return false if payment_passes.usable.exists?

    current_count >= Invoice::FREE_MONTHLY_INVOICE_LIMIT
  end

  # REM-8·PLAN-4 — 자동 리마인더 자격의 단일 판정점: Plus 구독 또는 사용 가능한 수금 패스 보유.
  # Reminders::SendService의 INELIGIBLE_PLAN 가드와 PrenoticeService의 사전통보 대상 필터가
  # 공유한다. 패스는 발행 시점에 소비되며 이 판정에서 재소비하지 않는다.
  def reminder_eligible?
    return true if subscription&.plus?

    payment_passes.usable.exists?
  end

  # ── REM-3 발송 요일·시간대 설정(2026-11-16 확정) ─────────────────────────
  # 고정 경계(평일 09:00~18:00) **내에서만 축소** 가능 — 확장(야간·주말)은 정책상 불허.
  # remind_allowed_wdays는 요일 정수 csv(1=월…5=금 — 0=일·6=토는 상시 불허) 저장.
  # Reminders::SendService의 outside_window?·next_window_at이 이 판정점을 공유한다.
  REMIND_ALLOWED_WDAYS = [ 1, 2, 3, 4, 5 ].freeze
  REMIND_MIN_HOUR = 9   # REM-3 고정 경계 하한
  REMIND_MAX_HOUR = 18  # REM-3 고정 경계 상한(종료 시각 — 이 시각 이후 발송 불가)

  validates :remind_start_hour, presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: REMIND_MIN_HOUR,
                            less_than: REMIND_MAX_HOUR }
  validates :remind_end_hour, presence: true,
            numericality: { only_integer: true, greater_than: REMIND_MIN_HOUR,
                            less_than_or_equal_to: REMIND_MAX_HOUR }
  validate :remind_wdays_within_fixed_boundary
  validate :remind_start_before_end

  # csv 문자열 → 요일 정수 목록(1~5만 유효 — 나머지는 저장 시점에 무시된다). 기본값 "1,2,3,4,5".
  def remind_allowed_wday_list
    remind_allowed_wdays.to_s.split(",").map(&:to_i).select { |d| REMIND_ALLOWED_WDAYS.include?(d) }.uniq.sort
  end

  # 시각이 사용자 설정 허용 요일·시간대 안인가(REM-3 고정 경계는 검증으로 이미 보장).
  def remind_window_open?(time)
    remind_allowed_wday?(time) && time.hour >= remind_start_hour && time.hour < remind_end_hour
  end

  def remind_allowed_wday?(time)
    remind_allowed_wday_list.include?(time.wday)
  end

  # TAX-1 — 전자세금계산서 발행 설정 완료 판정(단일 출처 — 발행 버튼 가드·설정 화면 공유).
  # 사업자 정보(회원사 가입에 필요한 최소 세트) + 공동인증서 등록 마킹이 모두 있어야 완료다.
  # 사용자 확정 전제 — 인증서 미등록 시 발행 버튼 비활성·안내 분기.
  def tax_invoice_ready?
    corp_num.present? && corp_name.present? && ceo_name.present? &&
      corp_addr.present? && contact_name.present? && barobill_id.present? &&
      barobill_cert_registered?
  end

  # 다음 발송 가능 슬롯 — 허용 창 안이면 그대로, 밖이면 다음 허용 슬롯으로 이월.
  #   · 허용 요일 + 개방 전 → 당일 시작 시각
  #   · 그 외(종료 경계 이후·비허용 요일) → 다음 허용 요일의 시작 시각
  # 순수 로직(Time.current 등 글로벌 의존 없음) — 시퀀스 D+1/D+7 계산 의미는 불변, 슬롯 이월만.
  # 설정상 허용 요일이 최소 1개 보장(검증)되므로 루프는 반드시 종료한다.
  def next_remind_slot(from)
    return from if remind_window_open?(from)

    if remind_allowed_wday?(from) && from.hour < remind_start_hour
      remind_slot_on(from.to_date)
    else
      date = from.to_date + 1.day
      date += 1.day until remind_allowed_wday?(date)
      remind_slot_on(date)
    end
  end

  private

  # 해당 날짜의 시작 시각(KST — TIME-1)으로 창 개방 시각을 만든다.
  def remind_slot_on(date)
    Time.zone.local(date.year, date.month, date.day, remind_start_hour, 0, 0)
  end

  def remind_wdays_within_fixed_boundary
    list = remind_allowed_wdays.to_s.split(",").map(&:to_i)
    return if list.any? && list.all? { |d| REMIND_ALLOWED_WDAYS.include?(d) }

    errors.add(:remind_allowed_wdays, "은(는) 월~금 중 최소 1일 이상 선택해야 합니다")
  end

  def remind_start_before_end
    return if remind_start_hour.blank? || remind_end_hour.blank?
    return if remind_start_hour < remind_end_hour

    errors.add(:remind_end_hour, "은(는) 시작 시각보다 늦어야 합니다")
  end

  def create_free_subscription
    Subscription.create!(user: self, plan: :free)
  end
end

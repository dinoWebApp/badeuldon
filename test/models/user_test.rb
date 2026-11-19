require "test_helper"

# U1 사용자 모델 — AUTH-1(이메일/비밀번호), AUTH-1.4(이메일 필수·고유·정규화)
# 오류 문구는 가입 폼에 노출되는 en.yml 한글 문구 그대로 검증한다(리뷰 이슈 #3 회귀).
class UserTest < ActiveSupport::TestCase
  test "이메일은 대소문자와 앞뒤 공백을 정규화한다 (AUTH-1.4)" do
    user = User.new(email: " DOWNCASED@EXAMPLE.COM ")
    assert_equal "downcased@example.com", user.email
  end

  test "이메일이 비면 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: "", password: "secret-123", password_confirmation: "secret-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이메일을 입력해 주세요."
  end

  test "동일 이메일은 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: users(:alpha).email, password: "secret-123", password_confirmation: "secret-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이미 등록된 이메일입니다"
  end

  test "대소문자·공백 변형 이메일도 중복으로 유효하지 않다 (AUTH-1.4)" do
    user = User.new(email: "  Alpha@Example.COM ")
    assert_equal "alpha@example.com", user.email
    assert_predicate user, :invalid?
    assert_includes user.errors[:email], "이미 등록된 이메일입니다"
  end

  test "새 레코드에 비밀번호가 없으면 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com")
    assert_predicate user, :invalid?
    assert_includes user.errors[:password], "비밀번호를 입력해 주세요."
  end

  test "72바이트를 초과하는 비밀번호는 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com", password: "a" * 73, password_confirmation: "a" * 73)
    assert_predicate user, :invalid?
    assert_includes user.errors[:password], "비밀번호가 너무 깁니다. 72자 이내로 입력해 주세요."
  end

  test "비밀번호 확인이 일치하지 않으면 유효하지 않다 (has_secure_password 기본)" do
    user = User.new(email: "fresh@example.com", password: "secret-123", password_confirmation: "different-123")
    assert_predicate user, :invalid?
    assert_includes user.errors[:password_confirmation], "비밀번호 확인이 일치하지 않습니다."
  end

  test "올바른 비밀번호로 인증하고 틀린 비밀번호는 거부한다 (AUTH-1)" do
    assert users(:alpha).authenticate("password")
    refute users(:alpha).authenticate("wrong-password")
  end

  # ── AUTH-1.3 프로필 컨텍스트 검증 ──

  test "가입 컨텍스트는 프로필 미설정을 통과시킨다 (AUTH-1.3 — 가입 시점 자유)" do
    user = User.new(email: "fresh@example.com", password: "secret-123", password_confirmation: "secret-123")
    assert_predicate user, :valid?
  end

  test "프로필 컨텍스트는 표시명·사업자 유형 누락을 한글 오류로 거부한다 (AUTH-1.3)" do
    user = users(:beta)
    assert_not user.valid?(:profile)
    assert_includes user.errors[:display_name], "표시명(또는 상호)을 입력해 주세요."
    assert_includes user.errors[:business_type], "사업자 유형을 선택해 주세요."
  end

  test "프로필 완료 사용자는 프로필 컨텍스트를 통과한다 (AUTH-1.3)" do
    assert users(:gamma).valid?(:profile)
  end

  test "전화번호 형식 위반은 ko.yml 문언으로 거부되고 하이픈 입력은 정규화 저장된다 (AUTH-9 — 2026-11-19 정책 갱신)" do
    user = users(:gamma)
    # normalizes(AUTH-9)가 "abc"를 공백화하므로 형식 위반 표본은 숫자 과잉값을 쓴다.
    # 노출 문언은 ko.yml(user.phone.invalid)이 단일 소스다 — 모델 inline message는
    # Rails 8 i18n 키 우선 참조로 shadowed(07_test_report 관찰 참조).
    user.phone = "010123456789"
    assert_not user.valid?
    assert_includes user.errors[:phone], "연락처 형식이 올바르지 않습니다. 예) 010-1234-5678"

    user.phone = "010-9876-0001"
    assert user.valid?, "하이픈 입력은 형식 검증을 통과한다(레거시 호환)"
    assert_equal "01098760001", user.phone, "저장값은 하이픈 제거 숫자만(정규화)"
  end

  test "전화번호는 값이 있을 때만 유일하다 — null 다수 허용 (AUTH-9 소급 없음)" do
    # 비교 표본은 정규화 저장된 신규 유저 — fixture 레거시(하이픈 저장) 값과의 비교는
    # "소급 없음" 영역이라 단정하지 않는다(07_test_report 관찰 참조).
    taken = User.create!(email: "phone-taken@example.com", password: "password123",
                         phone: "01055500011")
    user = users(:alpha)
    user.phone = taken.phone # 정규화 저장값 그대로
    assert_not user.valid?
    assert user.errors[:phone].present?, "동일 번호 재사용은 거부된다"

    user.phone = nil
    assert user.valid?, "null은 유일성 판정 제외(기존 유저 소급 없음 — AUTH-9)"
  end

  test "프로필 컨텍스트는 잘못된 형식의 계좌번호를 거부한다 (AUTH-1.3 — 기존 커버 유지)" do
    user = users(:gamma)
    user.account_number = "12"
    assert_not user.valid?(:profile)
    assert_includes user.errors[:account_number],
      "계좌번호 형식을 확인해 주세요. 숫자와 하이픈(-)으로 5자 이상 입력해 주세요."
  end

  test "표시명은 앞뒤 공백이 정규화된다 (AUTH-1.3)" do
    user = users(:alpha)
    user.display_name = "  감마랩  "
    assert_equal "감마랩", user.display_name
  end

  # ── AUTH-1.5 탈퇴 연쇄 삭제 ──

  # BUG-1 회귀 — dependent: :destroy는 연관 선언 순서대로 실행된다. clients·items가
  # invoices보다 먼저 선언될 경우 거래처 삭제 시점에 invoices.client_id 외래 키 제약
  # (ActiveRecord::InvalidForeignKey)으로 탈퇴 자체가 실패했다. 자식→부모 순서를 보장한다.
  test "청구서·거래처·품목을 보유한 사용자 삭제가 전부 연쇄 삭제된다 (AUTH-1.5)" do
    user = User.create!(email: "cascade@example.com",
                        password: "secret-123", password_confirmation: "secret-123")
    client = user.clients.create!(name: "연쇄삭제거래처", contact_name: "김연쇄", phone: "010-1234-5678")
    user.items.create!(name: "연쇄삭제품목", unit_price: 10_000)
    invoice = user.invoices.create!(
      client: client, due_on: Date.current + 30, tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "테스트발행자", bank_name: "국민은행",
      account_number: "123-45-678901", account_holder: "테스트예금주",
      items_attributes: { "0" => { description: "품목1", quantity: "1", unit_price: "10000" } }
    )

    user.destroy

    # 사용자·청구서·거래처·품목·청구서 품목 행 — 삭제된 사용자 소유 행이 전 테이블에서 0건이다.
    assert_equal 0, User.where(id: user.id).count, "사용자 행이 삭제된다"
    assert_equal 0, Invoice.where(user_id: user.id).count, "청구서가 거래처보다 먼저 연쇄 삭제된다"
    assert_equal 0, Client.where(user_id: user.id).count, "거래처가 연쇄 삭제된다"
    assert_equal 0, Item.where(user_id: user.id).count, "품목 라이브러리가 연쇄 삭제된다"
    assert_equal 0, InvoiceItem.where(invoice_id: invoice.id).count, "청구서 품목 행이 연쇄 삭제된다"
  end

  # ── ADMIN-3(Run B) — 계정 상태 enum ──

  test "status enum은 active·suspended 2값이고 기본값은 active다 (ADMIN-3)" do
    assert_equal({ "active" => 0, "suspended" => 1 }, User.statuses)
    assert_predicate users(:alpha), :active?, "fixture 사용자는 기본 active"
  end

  test "suspended?는 정지 계정에서만 참이다 (ADMIN-3·로그인 차단 판정점)" do
    user = users(:alpha)
    user.update!(status: :suspended)

    assert_predicate user, :suspended?
    assert_not_predicate user, :active?

    user.update!(status: :active)
    assert_not_predicate user.reload, :suspended?, "해제 가능(ADMIN-3 정지↔활성 왕복)"
  end
end

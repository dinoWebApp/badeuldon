require "test_helper"

# 거래처(CLIENT-1) 모델 — 필수·선택 필드, 연락처·이메일 형식, 정규화, PLAN-1 Free 한도.
# 시나리오 기준: PRD §6.3 CLIENT-1·§6.10 PLAN-1·LP-12, _workspace/05_review.md 「Tester 중점」
class ClientTest < ActiveSupport::TestCase
  test "필수 3종 누락은 필드별 한글 오류로 무효다 (CLIENT-1)" do
    client = Client.new(user: users(:gamma))
    assert_predicate client, :invalid?
    assert_includes client.errors[:name], "거래처명을 입력해 주세요."
    assert_includes client.errors[:contact_name], "담당자명을 입력해 주세요."
    assert_includes client.errors[:phone], "휴대폰 번호를 입력해 주세요."
  end

  test "선택 3종은 공백으로도 유효하다 (CLIENT-1 — 선택 입력 허용)" do
    client = Client.new(
      user: users(:gamma),
      name: "주식회사 감마파트너스", contact_name: "감과장", phone: "010-7777-8888",
      email: "", business_number: "", memo: ""
    )
    assert_predicate client, :valid?
  end

  test "phone은 숫자만·하이픈·지역번호 형식을 허용한다 (CLIENT-1 — user.rb 관례 동일)" do
    %w[01012345678 010-1234-5678 02-1234-5678 070-9999-8888].each do |phone|
      client = new_valid_client(users(:gamma))
      client.phone = phone
      assert_predicate client, :valid?, "#{phone}은 허용 형식이다"
    end
  end

  test "phone은 +82·0505·자릿수 미달 번호를 거부한다 (CLIENT-1 — 알림톡 발송 번호 품질)" do
    [ "+82-10-1234-5678", "0505-123-4567", "010-12-3456" ].each do |phone|
      client = new_valid_client(users(:gamma))
      client.phone = phone
      assert_predicate client, :invalid?
      assert_includes client.errors[:phone],
        "휴대폰 번호 형식이 올바르지 않습니다. 예) 010-1234-5678"
    end
  end

  test "이메일 형식 오류는 한글 오류로 거부된다 (CLIENT-1)" do
    client = new_valid_client(users(:gamma))
    client.email = "잘못된-이메일"
    assert_predicate client, :invalid?
    assert_includes client.errors[:email], "이메일 형식이 올바르지 않습니다. 예) name@example.com"
  end

  test "name·contact_name·phone·business_number는 앞뒤 공백이 strip된다 (Phase 6 #5 — F-TAX 매칭 대비)" do
    client = Client.new(
      user: users(:gamma),
      name: "  주식회사 감마파트너스  ", contact_name: "  감과장  ", phone: " 010-7777-8888 ",
      business_number: "  777-77-77777  "
    )
    assert_predicate client, :valid?
    assert_equal "주식회사 감마파트너스", client.name
    assert_equal "감과장", client.contact_name
    assert_equal "010-7777-8888", client.phone
    assert_equal "777-77-77777", client.business_number
  end

  test "email은 strip·소문자 정규화된다 (CLIENT-1)" do
    client = new_valid_client(users(:gamma))
    client.email = "  PARTNER@GammaPartners.CO.KR "
    assert_equal "partner@gammapartners.co.kr", client.email
  end

  # ── PLAN-1 Free 거래처 한도 ──

  test "5개 보유 사용자의 6번째 등록은 base 한글 오류로 무효다 (PLAN-1)" do
    assert_equal 5, users(:alpha).clients.count
    client = new_valid_client(users(:alpha))
    assert_predicate client, :invalid?
    assert_includes client.errors[:base],
      "Free 플랜은 거래처 5개까지입니다. Plus로 무제한 이용할 수 있습니다"
  end

  test "4개 보유 사용자의 5번째 등록은 유효하다 (PLAN-1 — 경계값 이내)" do
    3.times do |i|
      users(:gamma).clients.create!(name: "경계거래처#{i + 2}", contact_name: "담당자",
        phone: "010-0000-#{format('%04d', i + 2)}")
    end
    assert_equal 4, users(:gamma).clients.count
    client = new_valid_client(users(:gamma))
    assert_predicate client, :valid?
    assert client.save
    assert_equal 5, users(:gamma).clients.count
  end

  test "한도 검사는 등록 시에만 적용된다 — 한도 도달 사용자의 수정은 유효하다 (PLAN-1, on: :create)" do
    client = clients(:alpha_client_1)
    client.contact_name = "수정된 담당자"
    assert_predicate client, :valid?
    assert client.save
    assert_equal "수정된 담당자", client.reload.contact_name
    assert_equal 5, users(:alpha).clients.count
  end

  test "한도 도달 후 삭제하면 슬롯이 회수되어 재등록할 수 있다 (PLAN-1)" do
    users(:alpha).clients.first.destroy
    assert_equal 4, users(:alpha).clients.count
    assert_predicate new_valid_client(users(:alpha)), :valid?
  end

  test "한도 오류 문구는 Plus 이용 가능성만 안내하고 확정 보장을 하지 않는다 (LP-12)" do
    client = new_valid_client(users(:alpha))
    client.valid?
    message = client.errors[:base].join
    assert_includes message, "Plus로 무제한 이용할 수 있습니다"
    assert_no_match(/보장|100%/, message)
  end

  test "사용자 삭제 시 소유 거래처가 연쇄 삭제된다 (AUTH-1.5)" do
    assert_equal 1, users(:beta).clients.count
    assert_difference -> { Client.count }, -1 do
      users(:beta).destroy
    end
  end

  private

  def new_valid_client(user)
    Client.new(user:, name: "신규 거래처", contact_name: "김신규", phone: "010-1111-0000")
  end
end

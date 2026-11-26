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

  # ── F-REM — 발송 상태 접근자·스코프(REM-7 보류·VIEW-7 수신거부) ──

  test "refused?·reminders_suspended?·reminders_active?는 마킹 유무로 판정한다 (REM-7·VIEW-7)" do
    client = clients(:gamma_main)
    assert_not client.refused?
    assert_not client.reminders_suspended?
    assert_predicate client, :reminders_active?

    mark_refused(client, at: Time.zone.parse("2026-10-12 09:00"))
    assert client.reload.refused?
    assert_not client.reload.reminders_active?          # 수신거부 — 재개 경로 없다(VIEW-7·P1)

    client.update_column(:refused_at, nil)
    client.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))
    assert client.reload.reminders_suspended?
    assert_not client.reload.reminders_active?          # 보류 — 재개 가능(REM-7)
  end

  test "reminders_active 스코프는 수신거부·보류 거래처를 제외한다 (REM 스캔 필터)" do
    refused = clients(:gamma_main)
    suspended = users(:gamma).clients.create!(name: "보류거래처", contact_name: "김보류",
                                              phone: "010-5555-0001")
    mark_refused(refused, at: Time.zone.parse("2026-10-12 09:00"))
    suspended.update_column(:reminders_suspended_at, Time.zone.parse("2026-10-12 09:00"))

    active_ids = Client.reminders_active.ids
    assert_includes active_ids, clients(:alpha_client_1).id
    assert_not_includes active_ids, refused.id
    assert_not_includes active_ids, suspended.id
  end

  # ── VIEW-7(Q30) — 수신 거부 상속(같은 회원·같은 번호) ──

  test "하이픈 형식이 달라도 숫자가 같은 거부 이력이 있으면 등록 시 거부를 상속한다 (VIEW-7·Q30)" do
    refused_at = Time.zone.parse("2026-10-12 09:00")
    mark_refused(clients(:gamma_main), at: refused_at)         # 010-7777-8888

    client = Client.new(user: users(:gamma), name: "재등록 거래처", contact_name: "김재등록",
                        phone: "01077778888")                   # 하이픈 없는 같은 번호
    assert client.save
    assert client.reload.refused?
    assert_equal refused_at, client.reload.refused_at           # 원 접수 시각을 물려받는다
    assert client.refusal_inherited
  end

  test "다른 회원·다른 번호의 거부 이력은 상속하지 않는다 (VIEW-7·Q30 — 회원 간 결합 금지)" do
    mark_refused(clients(:gamma_main), at: Time.zone.parse("2026-10-12 09:00"))

    # 다른 회원(beta)의 같은 번호 거래처 — 상속 대상 아님
    stranger = Client.new(user: users(:beta), name: "베타재등록", contact_name: "김베타",
                          phone: "010-7777-8888")
    assert stranger.save
    assert_not stranger.reload.refused?
    assert_not stranger.refusal_inherited

    # 같은 회원(gamma)의 다른 번호 거래처 — 상속 대상 아님
    other_number = Client.new(user: users(:gamma), name: "감마새번호", contact_name: "김감마",
                              phone: "010-1234-5678")
    assert other_number.save
    assert_not other_number.reload.refused?
    assert_not other_number.refusal_inherited
  end

  test "번호를 거부 이력이 있는 번호로 바꾸는 수정에서 거부를 상속한다 (VIEW-7·Q30)" do
    refused_at = Time.zone.parse("2026-10-12 09:00")
    mark_refused(clients(:gamma_main), at: refused_at)

    changer = users(:gamma).clients.create!(name: "번호변경 거래처", contact_name: "김변경",
                                            phone: "010-1212-3434")
    assert_not changer.reload.refused?

    changer.phone = "01077778888"                               # 거부된 번호로 변경
    assert changer.save
    assert changer.reload.refused?
    assert_equal refused_at, changer.reload.refused_at
    assert changer.refusal_inherited
  end

  test "번호 변경 없는 저장(메모 수정)에서도 거부를 상속한다 (VIEW-7·Q30 — 콜백은 모든 저장, 리뷰 W-3)" do
    refused_at = Time.zone.parse("2026-10-12 09:00")
    # 행 단위 시절 데이터 재현 — 같은 번호 거래처를 먼저 만든 뒤 원본을 거부 마킹(전파 우회)
    sibling = users(:gamma).clients.create!(name: "같은번호 거래처", contact_name: "김동일",
                                            phone: "010-7777-8888")
    assert_not sibling.reload.refused?
    mark_refused(clients(:gamma_main), at: refused_at)

    sibling.update!(memo: "메모만 수정")                        # 번호 무변경 저장
    assert sibling.reload.refused?
    assert_equal refused_at, sibling.reload.refused_at
    assert sibling.refusal_inherited
  end

  test "이미 거부된 거래처는 번호를 바꿔도 거부 마킹을 유지한다 (VIEW-7·Q30 — 되돌림 없음)" do
    refused_at = Time.zone.parse("2026-10-12 09:00")
    client = clients(:gamma_main)
    mark_refused(client, at: refused_at)

    client.phone = "010-9999-1234"                              # 거부 없는 다른 번호로 변경
    assert client.save
    assert_equal refused_at, client.reload.refused_at           # 마킹은 유지 — 지우지 않는다
    assert_equal "01077778888", client.reload.refused_phone     # 거부 시점 번호도 불변
    assert client.reload.refused?
    assert_not client.refusal_inherited                         # 상속 아님 — 기존 마킹
  end

  test "하이픈 조합(없음→있음·있음→있음·없음→없음)도 모두 상속한다 (VIEW-7·Q30 — 리뷰 제안 3)" do
    # 있음→없음 조합은 위 "하이픈 형식이 달라도" 테스트가 담당 — 나머지 3종을 조합 순회로 고정
    refused_at = Time.zone.parse("2026-10-12 09:00")
    combos = [ %w[01043434343 010-4343-4343],   # 원본 없음 → 신규 있음
               %w[010-4343-4343 010-4343-4343], # 원본 있음 → 신규 있음
               %w[01043434343 01043434343] ]    # 원본 없음 → 신규 없음
    combos.each_with_index do |(source_phone, new_phone), index|
      sibling = users(:gamma).clients.create!(name: "조합원본#{index}", contact_name: "김조합",
                                              phone: source_phone)
      mark_refused(sibling, at: refused_at)

      client = Client.new(user: users(:gamma), name: "조합신규#{index}", contact_name: "김신규",
                          phone: new_phone)
      assert client.save, "조합 #{source_phone} → #{new_phone} 저장 실패"
      assert client.reload.refused?, "조합 #{source_phone} → #{new_phone} 상속 실패"
      assert_equal refused_at, client.reload.refused_at
      assert client.refusal_inherited
      sibling.destroy                                     # 다음 조합 후보 오염 방지(청구 이력 없음)
    end
  end

  test "검증 실패로 저장되지 않으면 상속하지 않는다 — 검증 통과 저장에서만 상속 (VIEW-7·Q30 — 리뷰 W-5③)" do
    mark_refused(clients(:gamma_main), at: Time.zone.parse("2026-10-12 09:00"))

    client = Client.new(user: users(:gamma), name: "검증실패 거래처", contact_name: "김검증",
                        phone: "01077778888", email: "잘못된-이메일")
    assert_not client.save                                # before_save는 검증 통과 저장에서만 실행
    assert_not client.persisted?
    assert_nil client.refused_at                          # 거부 번호로 등록 시도했지만 마킹 없음
    assert_not client.refusal_inherited

    client.email = "valid@example.com"
    assert client.save                                    # 같은 인스턴스가 통과해 저장되면 상속한다
    assert client.reload.refused?
    assert client.refusal_inherited
  end

  test "거부된 행이 번호를 바꾸면 옛 번호 등록분은 상속하고 새 번호 등록분은 상속하지 않는다 (VIEW-7·Q30 — refused_phone 고정, 2026-11-26)" do
    # 옛 한계(거부된 행의 현재 번호를 상속 원천으로 봄)를 고정하던 테스트를 올바른 동작으로 교체 —
    # 상속 원천은 거부 시점 번호(refused_phone)이며 행의 번호 변경을 따라가지 않는다.
    refused_at = Time.zone.parse("2026-10-12 09:00")
    client = clients(:gamma_main)
    mark_refused(client, at: refused_at)
    client.update_column(:phone, "010-1212-9999")          # 거부 상태로 새 번호로 이동

    # 새 번호(010-1212-9999)로 등록 — 거부한 적 없는 번호라 상속받지 않는다
    moved = Client.new(user: users(:gamma), name: "새번호 거래처", contact_name: "김새번호",
                       phone: "01012129999")
    assert moved.save
    assert_not moved.reload.refused?
    assert_not moved.refusal_inherited

    # 옛 번호(010-7777-8888 = refused_phone)로 등록 — 원 접수 행이 원천이라 상속받는다
    reentered = Client.new(user: users(:gamma), name: "옛번호 거래처", contact_name: "김옛번호",
                           phone: "010-7777-8888")
    assert reentered.save
    assert reentered.reload.refused?
    assert_equal refused_at, reentered.reload.refused_at
    assert_equal "01077778888", reentered.reload.refused_phone
    assert reentered.refusal_inherited
  end

  test "refused_phone이 없는 단독 마킹 행은 상속의 원천이 되지 않는다 (VIEW-7·Q30 — 폴백 제거 확인)" do
    # 레거시 nil 폴백 제거(2026-11-26) 후 고정 — refused_at만 찍힌 거부 행(우회 마킹 상정)은
    # 같은 회원·같은 번호의 새 거래처에 거부를 상속시키지 않는다. 행 자체는 거부 상태로
    # 발송이 막힌다(refused?는 행 단위) — 상속만 하지 않는, 더 적게 차단하는 안전한 방향.
    # 운영 데이터에는 refused_phone이 없는 거부 행이 없다(마이그레이션 소급·단일 쓰기 지점).
    refused_at = Time.zone.parse("2026-10-12 09:00")
    clients(:gamma_main).update_column(:refused_at, refused_at)  # refused_phone 미마킹 — 레거시 상태
    assert_nil clients(:gamma_main).reload.refused_phone

    client = Client.new(user: users(:gamma), name: "폴백 제거 확인 거래처", contact_name: "김폴백",
                        phone: "010-7777-8888")
    assert client.save
    assert_not client.reload.refused?                            # 상속 없음 — 정상 등록
    assert_nil client.reload.refused_at
    assert_not client.refusal_inherited
    assert clients(:gamma_main).reload.refused?                  # 원천 행 자체는 여전히 거부 상태
  end

  test "정상 행이 번호를 바꾸면 옛 번호의 상속 대상에서 빠진다 (VIEW-7·Q30 — refused_phone 고정)" do
    refused_at = Time.zone.parse("2026-10-12 09:00")
    sibling = users(:gamma).clients.create!(name: "번호이동 거래처", contact_name: "김이동",
                                            phone: "010-7777-8888")
    mark_refused(users(:gamma).clients.create!(name: "원천 거래처", contact_name: "김원천",
                                               phone: "010-7777-8888"), at: refused_at)

    sibling.phone = "010-5555-4321"                        # 상속받은 적 없는 정상 행이 번호를 이동
    assert sibling.save
    assert_not sibling.reload.refused?                     # 이동 자체는 상속 없이 통과

    moved_number = Client.new(user: users(:gamma), name: "이동번호 거래처", contact_name: "김이동번호",
                              phone: "010-5555-4321")
    assert moved_number.save
    assert_not moved_number.reload.refused?                # 옛 번호가 아니게 됐으므로 원천이 없다
    assert_not moved_number.refusal_inherited
  end

  test "사용자 삭제 시 소유 거래처가 연쇄 삭제된다 (AUTH-1.5)" do
    assert_equal 1, users(:beta).clients.count
    assert_difference -> { Client.count }, -1 do
      users(:beta).destroy
    end
  end

  # ── CLIENT-1(P4·REM-6) — 발행 이력 보유 거래처 삭제 차단 ──

  test "발행 계열 청구(draft 이외)가 있는 거래처 삭제는 base 오류로 차단된다 (P4·REM-6)" do
    client = clients(:gamma_main)
    create_issued_invoice_for(client)
    assert_no_difference -> { Client.count } do
      assert_not client.destroy
    end
    assert_includes client.errors[:base],
      "발행 이력이 있는 거래처는 삭제할 수 없습니다. 기록 보존을 위해 삭제가 차단됩니다"
    assert Client.exists?(client.id)
  end

  test "초안만 보유한 거래처는 기존대로 삭제된다 (P4 가드 — 발송 이력 없음, 연쇄 삭제 무해)" do
    client = clients(:gamma_main)
    create_draft_invoice_for(client)
    assert client.destroy
    assert_not Client.exists?(client.id)
  end

  test "청구서가 없는 거래처 삭제는 차단되지 않는다 (P4 가드 — 정상 경로 유지)" do
    client = clients(:gamma_main)
    assert client.destroy
    assert_not Client.exists?(client.id)
  end

  test "사용자 탈퇴 연쇄(invoices 먼저 삭제)는 거래처 삭제 가드와 충돌하지 않는다 (AUTH-1.5)" do
    create_issued_invoice_for(clients(:gamma_main))
    # user.rb의 연관 선언 순서로 invoices가 clients보다 먼저 삭제되어 가드 조건이 충족되지 않는다
    users(:gamma).destroy
    assert_not Client.exists?(clients(:gamma_main).id)
  end

  # P4 가드 검증용 헬퍼 — issued/draft 청구서를 gamma 스코프로 최소 생성한다
  # (fixtures는 gamma를 0건 유지 정책이므로 테스트 내에서 생성).
  def create_issued_invoice_for(client)
    create_invoice_for(client, status: :issued)
  end

  def create_draft_invoice_for(client)
    create_invoice_for(client, status: :draft)
  end

  def create_invoice_for(client, status:)
    invoice = Invoice.new(
      user: client.user, client: client, status: status,
      issue_number: "BD-20261012-099", issued_at: Time.zone.parse("2026-10-12 09:00"),
      due_on: Date.parse("2026-11-11"), tax_mode: :separate, withholding_enabled: false,
      issuer_display_name: "감발행자", bank_name: "국민은행",
      account_number: "123-45-678901", account_holder: "감발행자",
      token: SecureRandom.urlsafe_base64(32),
      token_expires_at: Time.zone.parse("2026-12-11 23:59")
    )
    invoice.items.build(description: "디자인 작업", quantity: 1, unit_price: 300000)
    invoice.save!
    invoice
  end

  private

  def new_valid_client(user)
    Client.new(user:, name: "신규 거래처", contact_name: "김신규", phone: "010-1111-0000")
  end
end

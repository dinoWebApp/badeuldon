require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"

# AUTH-1.5 회원 자진 탈퇴(Q29) — 시나리오:
# ① 이메일 확인 불일치 거부(무변화)·AUTH-1.4 정규화 허용 ② 정상 탈퇴 — 연쇄 삭제 전수 +
# 감사 로그 1건(admin nil·이메일 스냅샷·IP·탈퇴 시점 요약) ③ 미수 청구 있어도 성공(관리자
# 삭제 Q13 차단과의 의도적 차이) ④ 유료 Plus 이용 중에도 성공(Q29 — 즉시 종료·이후 결제 없음)
# ⑤ 삭제 실패(RecordNotDestroyed) — 트랜잭션 롤백으로 감사 로그까지 원복·계정 유지
# ⑥ 감사 detail 요약(W-8) — 부분입금 잔액·Plus 상태(유료·해지 예약)·잔여 수금 패스.
# ⑦ 풍부한 데이터(입금·약속·문의 응답·열람·발송 이력·예약 슬롯·반복 청구·티켓 첨부·세금계산서)
#   의 연쇄 삭제 전수 + user_id 보유 테이블 전수 조사(감사 로그만 보존 allowlist)
# ⑧ 예약 발송 잡(DeliverJob) 흡수 — 삭제 뒤 수행돼도 예외 밖 노출 없음·발송 0건
# ⑨ 적대 시나리오 — InvalidForeignKey 흡수+롤백·정지 회원 탈퇴(현재 동작)·재가입(유니크 해제)·
#   phone_verifications 미연계(현재 동작 — 보고용).
class Users::WithdrawalServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include SolapiStubbing
  setup do
    @user = users(:alpha) # fixture는 after_create 우회 — Free 구독 행 수동 보장(1인 1구독)
    @subscription = @user.subscription || Subscription.create!(user: @user, plan: :free)
    # alpha fixture는 거래처 5개(PLAN-1 Free 한도) — 신규 생성을 위해 1개를 정리한다.
    @user.clients.first&.destroy!
    @client = Client.create!(user: @user, name: "탈퇴전용거래처", contact_name: "담당자", phone: "010-0000-0000")
  end

  test "이메일 확인이 불일치하면 거부되고 아무것도 삭제되지 않는다 (AUTH-1.5)" do
    result = Users::WithdrawalService.call(user: @user, confirm_email: "wrong@example.com", ip: "127.0.0.1")

    assert_not result.success?
    assert_match(/이메일이 일치하지 않습니다/, result.message)
    assert_predicate @user.reload, :present?
    assert_predicate @subscription.reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
  end

  test "공백·대소문자 차이 이메일은 AUTH-1.4 정규화 기준으로 일치 판정한다 (AUTH-1.5)" do
    result = Users::WithdrawalService.call(user: @user, confirm_email: "  ALPHA@example.com ", ip: "127.0.0.1")

    assert result.success?, result.message
    assert_not User.exists?(@user.id)
  end

  test "정상 탈퇴 — 회원과 연쇄 대상이 전부 삭제되고 감사 로그 1건이 남는다 (AUTH-1.5·ADMIN-2·P4)" do
    invoice = create_invoice! { |inv| inv.issue! }
    Order.create!(user: @user, product: :collection_pass, amount: 4_000, status: :paid,
                  pg_order_id: "order-withdrawal-0001", paid_at: Time.current)
    Order.create!(user: @user, product: :plus_monthly, amount: 9_900, status: :cancelled,
                  pg_order_id: "order-withdrawal-0002")
    PaymentPass.create!(user: @user, total_uses: 10, remaining_uses: 7, expires_at: 90.days.from_now)
    NoticeRead.create!(user: @user, notice: notices(:general_active))
    Ticket.create!(user: @user, title: "탈퇴 전 문의", status: :closed)
    Session.create!(user: @user)

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "203.0.113.10")

    assert result.success?, result.message
    assert_equal "탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다.", result.message
    assert_not User.exists?(@user.id)
    # 연쇄 삭제 전수 실측 — dependent: :destroy + DB FK cascade(관리자 삭제 서비스와 같은 구조)
    assert_equal 0, Client.where(user_id: @user.id).count
    assert_equal 0, Invoice.where(user_id: @user.id).count
    assert_equal 0, Item.where(user_id: @user.id).count
    assert_equal 0, Subscription.where(user_id: @user.id).count
    assert_equal 0, Order.where(user_id: @user.id).count
    # Q33 — 주문은 삭제돼도 식별 불가능한 사본이 탈퇴 시각과 함께 보관된다(AUTH-1.5 5년 보존)
    assert_equal 2, WithdrawnPaymentRecord.count
    archived = WithdrawnPaymentRecord.find_by!(pg_order_id: "order-withdrawal-0001")
    assert_equal "collection_pass", archived.read_attribute(:product)
    assert_equal "pass", archived.read_attribute(:item_type)
    assert_equal 4_000, archived.amount
    assert_equal "paid", archived.read_attribute(:status)
    assert_not_nil archived.withdrawn_at
    assert WithdrawnPaymentRecord.exists?(pg_order_id: "order-withdrawal-0002")
    assert_empty WithdrawnPaymentRecord.column_names &
                 %w[user_id pg_billing_key metadata refund_reason]
    assert_equal 0, PaymentPass.where(user_id: @user.id).count
    assert_equal 0, NoticeRead.where(user_id: @user.id).count
    assert_equal 0, Ticket.where(user_id: @user.id).count
    assert_equal 0, Session.where(user_id: @user.id).count
    assert_equal 0, MessageLog.where(user_id: @user.id).count
    # 감사 로그 — 실행자는 회원 본인(admin nil)·이메일 스냅샷·IP·탈퇴 시점 요약(W-8) 기록(ADMIN-2)
    logs = AuditLog.where(action: "member_withdrawal")
    assert_equal 1, logs.count
    log = logs.first
    assert_nil log.admin_id
    assert_equal "User", log.target_type
    assert_equal @user.id, log.target_id
    assert_match(@user.email, log.detail)
    assert_match "미수 1건(잔액 #{invoice.total_amount}원)", log.detail
    assert_match "Plus: 없음", log.detail # setup의 Free 구독 행
    assert_match "수금 패스 7건", log.detail
    assert_equal "203.0.113.10", log.ip
  end

  test "미수 청구가 있어도 탈퇴할 수 있다 (Q29 — 관리자 삭제 Q13 차단과의 의도적 차이)" do
    create_invoice! { |inv| inv.issue! }
    assert_predicate @user.invoices.unsettled, :any?

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert result.success?, result.message
    assert_not User.exists?(@user.id)
    assert_equal 0, Invoice.where(user_id: @user.id).count
  end

  test "유료 Plus 이용 중에도 탈퇴한다 (Q29 — 즉시 종료·이후 결제 없음)" do
    @user.subscription.update!(
      plan: :plus, status: :active, pg_billing_key: "tok_billing_withdrawal_0001",
      current_period_start: Time.current, current_period_end: 20.days.from_now
    )

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert result.success?, result.message
    assert_not User.exists?(@user.id)
    assert_equal 0, Subscription.where(user_id: @user.id).count
  end

  test "감사 detail에 탈퇴 시점 요약(미수·부분입금 잔액·Plus·수금 패스)이 기록된다 (ADMIN-2·W-8)" do
    invoice = create_invoice! { |inv| inv.issue! }
    Payment.create!(invoice: invoice, amount: 100_000, paid_on: Time.current.to_date) # 부분입금 — 잔액 차감 반영
    @user.subscription.update!(plan: :plus, status: :active,
                               pg_billing_key: "tok_billing_withdrawal_0002",
                               current_period_end: Time.zone.parse("2026-12-31 23:59:59"))
    PaymentPass.create!(user: @user, total_uses: 10, remaining_uses: 3, expires_at: 90.days.from_now)
    balance = invoice.reload.total_amount - 100_000 # 서비스 호출 전 계산 — 호출 뒤엔 연쇄 삭제됨

    Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    log = AuditLog.find_by!(action: "member_withdrawal")
    assert_match "미수 1건(잔액 #{balance}원)", log.detail
    assert_match "Plus: 유료(종료 12-31)", log.detail
    assert_match "수금 패스 3건", log.detail
  end

  test "해지 예약(cancelled) 상태의 Plus는 감사 detail에 해지 예약으로 기록된다 (ADMIN-2·W-8)" do
    @user.subscription.update!(plan: :plus, status: :cancelled, current_period_end: 20.days.from_now)

    Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert_match "Plus: 유료(해지 예약)", AuditLog.find_by!(action: "member_withdrawal").detail
  end

  test "풍부한 데이터의 회원이 탈퇴하면 연쇄 대상·부속 기록·첨부 파일까지 전부 0건이 된다 (AUTH-1.5·C-2 범위)" do
    invoice = create_invoice! { |inv| inv.issue! }
    # 입금 2건(부분입금)·약속+문의 응답 2건·열람 기록 2건
    Payment.create!(invoice: invoice, amount: 100_000, paid_on: Time.current.to_date)
    Payment.create!(invoice: invoice, amount: 50_000, paid_on: Time.current.to_date)
    invoice.promises.create!(kind: :date_selected, promised_on: 10.days.from_now.to_date)
    inquiry = invoice.promises.create!(kind: :inquiry, memo: "다음 달에 입금 가능할까요?")
    assert_predicate inquiry.answer!("다음 달 10일에 입금드리겠습니다"), :present? # 문의 응답(U1 답변)
    invoice.view_events.create!(first: true, device: "mobile", ip: "203.0.113.10", viewed_at: Time.current)
    invoice.view_events.create!(first: false, device: "pc", ip: "203.0.113.11", viewed_at: Time.current)
    # 발송 이력(sent — 전화번호·제공자 ID 포함) + 예약 슬롯(pending·scheduled_at 미래)
    MessageLog.create!(invoice: invoice, user: @user, template_key: "confirm_d1",
                       recipient_role: :debtor, status: :sent, phone: "01011112222",
                       provider_message_id: "msg_rich_1", scheduled_at: 1.hour.ago, sent_at: 50.minutes.ago)
    MessageLog.create!(invoice: invoice, user: @user, template_key: "d7",
                       recipient_role: :debtor, status: :pending, phone: "01011112222",
                       scheduled_at: 1.day.from_now)
    # 반복 청구 일정(+품목·발행 이력 참조 — last_invoice FK restrict 해소 경로)
    schedule = RecurringInvoice.new(user: @user, client: @client, day_of_month: 10)
    schedule.items.build(name: "월정액", quantity: 1, unit_price: 100_000)
    schedule.save!
    schedule.update!(last_invoice: invoice)
    items_before = Item.where(user_id: @user.id).count # alpha fixture 품목이 함께 있다
    Item.create!(user: @user, name: "탈퇴 품목", unit_price: 20_000)
    # 유료 구독·결제 주문·수금 패스·공지 읽음
    @user.subscription.update!(plan: :plus, status: :active, pg_billing_key: "tok_billing_rich_0001",
                               current_period_start: Time.current, current_period_end: 20.days.from_now)
    Order.create!(user: @user, product: :collection_pass, amount: 4_000, status: :paid,
                  pg_order_id: "order-withdrawal-rich-1", paid_at: Time.current)
    PaymentPass.create!(user: @user, total_uses: 10, remaining_uses: 10, expires_at: 90.days.from_now)
    NoticeRead.create!(user: @user, notice: notices(:general_active))
    # 문의 티켓(+메시지·Active Storage 첨부 1장)
    ticket = Ticket.create!(user: @user, title: "첨부 문의", status: :open)
    message = ticket.ticket_messages.create!(sender: :user, body: "첨부 파일 확인 부탁드립니다")
    File.open(Rails.root.join("test/fixtures/files/sample.png")) do |file|
      message.image.attach(io: file, filename: "sample.png", content_type: "image/png")
    end
    assert_predicate message.image, :attached?
    blob_id = message.image.blob.id
    # 세금계산서 발행 기록
    TaxInvoice.create!(invoice: invoice, user: @user, mgt_num: "TI-WITHDRAW-1",
                       supply_total: 300_000, tax_total: 30_000, grand_total: 330_000)
    Session.create!(user: @user)

    # 공허 단언 방지 — 만든 데이터가 실제로 존재하는지 먼저 고정한다
    assert_equal 1, Invoice.where(user_id: @user.id).count
    assert_equal 2, Payment.where(invoice_id: invoice.id).count
    assert_equal 2, Promise.where(invoice_id: invoice.id).count
    assert_equal 2, ViewEvent.where(invoice_id: invoice.id).count
    assert_equal 1, InvoiceItem.where(invoice_id: invoice.id).count
    assert_equal 2, MessageLog.where(user_id: @user.id).count
    assert_equal 1, RecurringInvoice.where(user_id: @user.id).count
    assert_equal 1, RecurringInvoiceItem.where(recurring_invoice_id: schedule.id).count
    assert_equal items_before + 1, Item.where(user_id: @user.id).count
    assert_equal 1, Subscription.where(user_id: @user.id).count
    assert_equal 1, Order.where(user_id: @user.id).count
    assert_equal 1, PaymentPass.where(user_id: @user.id).count
    assert_equal 1, NoticeRead.where(user_id: @user.id).count
    assert_equal 1, Ticket.where(user_id: @user.id).count
    assert_equal 1, TicketMessage.where(ticket_id: ticket.id).count
    assert_equal 1, ActiveStorage::Attachment.where(record_type: "TicketMessage").count
    assert_predicate ActiveStorage::Blob.exists?(blob_id), :present?
    assert_equal 1, TaxInvoice.where(user_id: @user.id).count
    assert_equal 1, Session.where(user_id: @user.id).count

    # 첨부 blob 정리는 purge_later(ActiveStorage::PurgeJob) — 인라인 수행으로 검증한다
    perform_enqueued_jobs do
      result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")
      assert result.success?, result.message
    end

    assert_not User.exists?(@user.id)
    # 청구서 + 부속 기록(입금·약속·문의 응답·열람) — invoices 연쇄로 소멸
    assert_equal 0, Invoice.where(user_id: @user.id).count
    assert_equal 0, Payment.where(invoice_id: invoice.id).count
    assert_equal 0, Promise.where(invoice_id: invoice.id).count
    assert_equal 0, ViewEvent.where(invoice_id: invoice.id).count
    assert_equal 0, InvoiceItem.where(invoice_id: invoice.id).count
    # 발송 이력·예약 슬롯(전화번호 포함) — message_logs DB FK on_delete: :cascade
    assert_equal 0, MessageLog.where(user_id: @user.id).count
    assert_equal 0, RecurringInvoice.where(user_id: @user.id).count
    assert_equal 0, RecurringInvoiceItem.where(recurring_invoice_id: schedule.id).count
    assert_equal 0, Client.where(user_id: @user.id).count
    assert_equal 0, Item.where(user_id: @user.id).count
    assert_equal 0, Subscription.where(user_id: @user.id).count
    assert_equal 0, Order.where(user_id: @user.id).count
    assert_equal 0, PaymentPass.where(user_id: @user.id).count
    assert_equal 0, NoticeRead.where(user_id: @user.id).count
    assert_equal 0, Ticket.where(user_id: @user.id).count
    assert_equal 0, TicketMessage.where(ticket_id: ticket.id).count
    assert_equal 0, TaxInvoice.where(user_id: @user.id).count
    assert_equal 0, Session.where(user_id: @user.id).count
    # Active Storage — 첨부 행은 즉시, blob은 PurgeJob 수행으로 정리된다
    assert_equal 0, ActiveStorage::Attachment.where(record_type: "TicketMessage", record_id: message.id).count
    assert_not ActiveStorage::Blob.exists?(blob_id), "첨부 blob도 purge_later로 정리된다"
    # 감사 로그만 보존(ADMIN-2 — Q13 선례 allowlist)
    assert_equal 1, AuditLog.where(action: "member_withdrawal", target_type: "User", target_id: @user.id).count
  end

  test "user_id 컬럼을 가진 모든 테이블에서 탈퇴 회원의 행이 남지 않는다 — 감사 로그만 보존 (B-6 전수 조사)" do
    invoice = create_invoice! { |inv| inv.issue! }
    Payment.create!(invoice: invoice, amount: 10_000, paid_on: Time.current.to_date)
    MessageLog.create!(invoice: invoice, user: @user, template_key: "final_d14",
                       recipient_role: :debtor, status: :sent, scheduled_at: 1.hour.ago, sent_at: Time.current)
    PaymentPass.create!(user: @user, total_uses: 5, remaining_uses: 5, expires_at: 90.days.from_now)
    TaxInvoice.create!(invoice: invoice, user: @user, mgt_num: "TI-WITHDRAW-2",
                       supply_total: 100_000, tax_total: 10_000, grand_total: 110_000)
    Session.create!(user: @user)

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")
    assert result.success?, result.message

    # 전수 조사 — 스키마의 user_id 컬럼 보유 테이블 전부를 대상으로 탈퇴 회원 행 잔존을 검사한다.
    # 감사 로그(audit_logs)는 보존이 목적(ADMIN-2·Q13 선례 — detail에 이메일 스냅샷)인 유일한
    # allowlist다. 회원을 식별하는 user_id 외 컬럼(phone_verifications.phone 등)은 별도 테스트.
    tables_with_user_id = ActiveRecord::Base.connection.tables.select do |table|
      ActiveRecord::Base.connection.column_exists?(table, :user_id)
    end
    tables_with_user_id.each do |table|
      next if table == "audit_logs" # allowlist — 보존이 목적인 감사 기록

      model = table.classify.constantize
      assert_equal 0, model.where(user_id: @user.id).count,
                   "#{table}에 탈퇴 회원(#{@user.id})의 행이 남아 있다"
    end
    # allowlist 확인 — 감사 로그는 보존되고 이메일 스냅샷으로 대상을 식별한다(P4)
    log = AuditLog.find_by!(action: "member_withdrawal", target_type: "User", target_id: @user.id)
    assert_match(@user.email, log.detail)
  end

  test "탈퇴 뒤에 실행되는 예약 발송 잡은 흡수되고 발송이 0건이다 (AUTH-1.5 파생 — discard_on RecordNotFound)" do
    invoice = create_invoice! { |inv| inv.issue! }
    MessageLog.create!(invoice: invoice, user: @user, template_key: "confirm_d1",
                       recipient_role: :debtor, status: :pending, phone: "01033334444",
                       scheduled_at: 1.hour.from_now)
    # 탈퇴 전에 큐에 예약된 잡 — 삭제된 청구 id를 바라본다
    Reminders::DeliverJob.perform_later(invoice.id, "confirm_d1", "debtor")

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")
    assert result.success?, result.message
    assert_not User.exists?(@user.id)

    # 나중에 잡 프로세스가 수행해도 RecordNotFound가 discard_on으로 흡수돼 예외가 밖으로
    # 새지 않고 솔라피 호출(발송)도 0건이다(외부 API — with_solapi_client 방어선).
    fake = FakeSolapiClient.new
    assert_nothing_raised do
      with_solapi_client(fake) do
        perform_enqueued_jobs
      end
    end
    assert_empty fake.calls, "삭제된 청구로의 발송이 있어서는 안 된다"
    assert_equal 0, MessageLog.where(user_id: @user.id).count
  end

  test "회원 삭제가 실패하면(RecordNotDestroyed) 트랜잭션이 원복돼 감사 로그 없이 계정이 유지된다" do
    # destroy! 실패 경로 재현 — 인스턴스 단일 스텁으로 destroy 콜백 abort를 흉내 낸다(외부 호출 없음).
    @user.define_singleton_method(:destroy!) do
      errors.add(:base, "삭제가 거부되었습니다")
      raise ActiveRecord::RecordNotDestroyed.new("삭제가 거부되었습니다", self)
    end

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert_not result.success?
    assert_match(/삭제가 거부되었습니다/, result.message)
    assert_predicate @user.reload, :present?
    # 감사 기록은 삭제 트랜잭션 내부에서 먼저 남겨진다 — 롤백으로 함께 원복(감사 없는 삭제 방지)
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count
  end

  test "연쇄 삭제 중 참조 제약(InvalidForeignKey)이 나면 안내로 흡수되고 감사·계정이 원복된다 (적대 — 마지막 방어)" do
    # destroy!에서 FK 제약 위반을 재현(단일 인스턴스 스텁 — 외부 호출 없음). 서비스는 500 대신
    # 회원 안내 오류로 변환하고, 트랜잭션 롤백으로 감사 로그와 계정이 그대로 유지돼야 한다.
    clients_before = Client.where(user_id: @user.id).count # alpha fixture 거래처 포함
    @user.define_singleton_method(:destroy!) do
      raise ActiveRecord::InvalidForeignKey.new("FK 제약 위반 재현")
    end

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert_not result.success?
    assert_match(/탈퇴 처리 중 오류가 발생했습니다/, result.message)
    assert_predicate @user.reload, :present?
    assert_equal 0, AuditLog.where(action: "member_withdrawal").count, "실패 시 감사 로그도 롤백된다"
    assert_equal clients_before, Client.where(user_id: @user.id).count, "연쇄 삭제도 전부 원복된다"
  end

  test "정지(suspended) 상태의 회원도 탈퇴할 수 있다 — 정지는 가역 상태라 탈퇴를 막지 않는다(현재 동작)" do
    # 확인된 현재 동작: 서비스에 상태 가드가 없다. 정지는 로그인 차단용 가역 상태(status enum
    # 주석 — user.rb)이고 PRD AUTH-1.5·Q29에 탈퇴 차단 근거가 없어 허용이 의도적 판단으로 보인다.
    # 정책 변경 여지는 오케스트레이터 판단 대상이므로 여기서는 동작을 고정만 한다.
    @user.update!(status: :suspended)

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert result.success?, result.message
    assert_not User.exists?(@user.id)
    assert_equal 1, AuditLog.where(action: "member_withdrawal").count
  end

  test "탈퇴 직후 같은 이메일·휴대폰으로 재가입하면 유니크 제약이 해제돼 가입할 수 있다 (Q29·AUTH-1.5)" do
    @user.update!(phone: "01055550000")
    email = @user.email

    result = Users::WithdrawalService.call(user: @user, confirm_email: email, ip: "127.0.0.1")
    assert result.success?, result.message

    reborn = User.create!(email: email, password: "new-password-123", phone: "01055550000",
                          display_name: "재가입자", business_type: :freelancer)
    assert_predicate reborn, :persisted?
    assert_predicate reborn.subscription, :present?, "재가입 회원에 Free 구독 행이 생성된다(1인 1구독)"
    assert_equal "01055550000", reborn.phone
  end

  test "phone_verifications는 user_id가 없어 탈퇴 대상이 아니다 — 만료 전 행은 남는다(현재 동작 — 보고용)" do
    # 확인된 현재 동작: 휴대폰 인증 행(AUTH-9)은 회원과 외래키 연결이 없어(user_id 없음 —
    # phone_verifications 스키마) 탈퇴 연쇄가 닿지 않는다. 행은 5분 만료·1회용 소비로 수명이
    # 통제되지만 탈퇴 시점에 즉시 지워지지는 않는다. 결함 분류는 오케스트레이터 판단 대상.
    PhoneVerification.create!(phone: "01055550000", code: "123456", expires_at: 5.minutes.from_now)

    result = Users::WithdrawalService.call(user: @user, confirm_email: @user.email, ip: "127.0.0.1")

    assert result.success?, result.message
    assert_predicate PhoneVerification.find_by(phone: "01055550000"), :present?,
                     "user_id가 없어 탈퇴 연쇄가 닿지 않는다(5분 만료는 별도 수명)"
  end

  private

  # 품목 1행 초안 생성(검증 통과) — 상태 전이는 블록에서 수행(issue! 등). 관리자 삭제 서비스
  # 테스트와 같은 형태(Admins::AccountPurgeServiceTest 선례).
  def create_invoice!(due_on: 30.days.from_now.to_date, &)
    invoice = Invoice.new(user: @user, client: @client, status: :draft, due_on:,
                          tax_mode: :separate, withholding_enabled: false,
                          issuer_display_name: "테스트발행자", bank_name: "신한은행",
                          account_number: "110-234-567890", account_holder: "김알파",
                          items_attributes: [ { description: "디자인 작업", quantity: 1, unit_price: 300_000 } ])
    invoice.save!
    yield(invoice) if block_given?
    invoice.reload
  end
end

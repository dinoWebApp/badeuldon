require "test_helper"

# 발송 이력 모델(F-REM — REM-6·P4·SEC-5·PLAN-3) — enum 3종·소유자 일치 검증·상한 카운트·
# pending 슬롯 부분 유니크 인덱스(origin 무관 — C-1 회귀 방지). 시나리오 기준:
# _workspace/03_implementation.md Rule ID 매핑표, _workspace/05_review.md §Tester 6·7.
class MessageLogTest < ActiveSupport::TestCase
  fixtures :invoices

  # ── enum·기본값 ──

  test "신규 이력은 채무자·자동·pending이 기본값이다 (REM-6)" do
    log = MessageLog.new(invoice: invoices(:delta_issued), user: users(:delta),
                         template_key: "confirm_d1")

    assert_predicate log, :debtor?
    assert_predicate log, :auto?
    assert_predicate log, :pending?
  end

  test "recipient_role·origin·status enum은 채무자/사용자·자동/수동·4상태를 갖는다 (REM-6·REM-8)" do
    assert_equal({ "debtor" => 0, "user" => 1 }, MessageLog.recipient_roles)
    assert_equal({ "auto" => 0, "manual" => 1 }, MessageLog.origins)
    assert_equal({ "pending" => 0, "sent" => 1, "failed" => 2, "skipped" => 3 },
                 MessageLog.statuses)
  end

  # ── PLAN-3 상한 산정 기준 ──

  test "시퀀스성 템플릿 키는 7종이며 1회성·U1 알림은 제외다 (PLAN-3·Q10)" do
    expected = %w[
      invoice_notice confirm_d1 confirm_d1_opened requeue_d7 final_d14
      promise_d1 promise_overdue
    ]
    assert_equal expected.sort, MessageLog::SEQUENCE_TEMPLATE_KEYS.sort
    assert_not_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "issue_notice"
    assert_not_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "partial_paid"
    assert_not_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "paid_thanks"
    assert_not_includes MessageLog::SEQUENCE_TEMPLATE_KEYS, "noti_prenotice"
  end

  test "시퀀스 상한은 5통이다 (PLAN-3·REM-12 하드리밋)" do
    assert_equal 5, MessageLog::SEQUENCE_CAP
  end

  test "sequence_sent_count는 채무자 향 sent 시퀀스성만 세고 origin을 합산한다 (PLAN-3)" do
    invoice = invoices(:delta_issued)
    debtor_log = MessageLog.create!(invoice: invoice, user: users(:delta),
                                    template_key: "confirm_d1", status: :sent)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "requeue_d7", status: :sent, origin: :manual)
    # 집계 밖 4종 — U1 향·1회성·미발송(skipped)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "noti_prenotice", recipient_role: :user, status: :sent)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "paid_thanks", status: :sent)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "final_d14", status: :skipped, error_code: "PAST_WINDOW")

    assert_equal 2, MessageLog.sequence_sent_count(invoice.id)
    assert_equal [ debtor_log.id ], MessageLog.sent_sequence(invoice.id).where(origin: :auto).ids
  end

  test "상한 카운트는 청구서별로 격리된다 (PLAN-3)" do
    other = invoices(:delta_viewed)
    MessageLog.create!(invoice: other, user: users(:delta),
                       template_key: "confirm_d1", status: :sent)

    assert_equal 0, MessageLog.sequence_sent_count(invoices(:delta_issued).id)
    assert_equal 1, MessageLog.sequence_sent_count(other.id)
  end

  # ── 검증 ──

  test "template_key는 필수다 (REM-6)" do
    log = MessageLog.new(invoice: invoices(:delta_issued), user: users(:delta))
    assert_not_predicate log, :valid?
    assert log.errors.of_kind?(:template_key, :blank)
  end

  test "이력 소유자는 청구서 소유자와 일치해야 한다 (데이터 무결성)" do
    forged = MessageLog.new(invoice: invoices(:delta_issued), user: users(:gamma),
                            template_key: "confirm_d1")
    assert_not_predicate forged, :valid?
    assert forged.errors[:user_id].any?

    owned = MessageLog.new(invoice: invoices(:delta_issued), user: users(:delta),
                           template_key: "confirm_d1")
    assert_predicate owned, :valid?
  end

  # ── SEC-5 pending 슬롯 유니크 인덱스(C-1 — origin 무관 1개) ──

  test "동일 청구·동일 단계의 pending 슬롯은 origin이 달라도 1개다 (SEC-5·C-1 회귀)" do
    invoice = invoices(:delta_issued)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "confirm_d1", origin: :manual, status: :pending)

    assert_raises(ActiveRecord::RecordNotUnique) do
      MessageLog.create!(invoice: invoice, user: users(:delta),
                         template_key: "confirm_d1", origin: :auto, status: :pending)
    end
  end

  test "sent·failed·skipped 이력은 pending 인덱스 밖이라 이력 누적이 허용된다 (C-1·REM-6)" do
    invoice = invoices(:delta_issued)
    MessageLog.create!(invoice: invoice, user: users(:delta),
                       template_key: "confirm_d1", status: :sent)

    assert_nothing_raised do
      MessageLog.create!(invoice: invoice, user: users(:delta),
                         template_key: "confirm_d1", status: :sent, origin: :manual)
    end
    assert_equal 2, MessageLog.where(invoice_id: invoice.id).count
  end

  test "다른 단계의 pending 슬롯은 동시에 존재할 수 있다 (SEC-5 — 슬롯은 단계별)" do
    invoice = invoices(:delta_issued)

    assert_nothing_raised do
      MessageLog.create!(invoice: invoice, user: users(:delta),
                         template_key: "confirm_d1", status: :pending)
      MessageLog.create!(invoice: invoice, user: users(:delta),
                         template_key: "requeue_d7", status: :pending)
    end
  end

  test "U1 향 pending은 pending 인덱스 밖이라 반복 기록이 허용된다 (SEC-5 — 단계별 반복 정상)" do
    invoice = invoices(:delta_issued)

    assert_nothing_raised do
      2.times do
        MessageLog.create!(invoice: invoice, user: users(:delta),
                           template_key: "noti_prenotice", recipient_role: :user,
                           status: :pending, scheduled_at: Time.current)
      end
    end
  end

  test "variables는 JSON으로 직렬화·복원된다 (REM-6 변수 스냅샷)" do
    invoice = invoices(:delta_issued)
    log = MessageLog.create!(invoice: invoice, user: users(:delta), template_key: "confirm_d1",
                             status: :sent, variables: { "금액" => "220,000" })

    assert_equal({ "금액" => "220,000" }, log.reload.variables)
  end
end

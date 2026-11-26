require "test_helper"

module WithdrawnPaymentRecords
  # AUTH-1.5·Q33 — 탈퇴 회원 결제 기록 비식별 사본 파기 잡. 5년(RETENTION 단일 출처) 경과
  # 행만 삭제하고 경계 이전 행은 유지. delete_all이라 재실행 멱등. 로그는 건수만 남긴다.
  class PurgeJobTest < ActiveSupport::TestCase
    def create_record!(withdrawn_at:, pg_order_id:)
      WithdrawnPaymentRecord.create!(product: :collection_pass, item_type: :pass,
                                     amount: 4_000, status: :paid,
                                     pg_order_id: pg_order_id, withdrawn_at: withdrawn_at)
    end

    test "5년 경과 행만 삭제하고 미만료 행은 유지한다" do
      travel_to Time.current do
        @expired = create_record!(withdrawn_at: 5.years.ago - 1.day, pg_order_id: "order-purge-expired")
        @recent = create_record!(withdrawn_at: 4.years.ago, pg_order_id: "order-purge-recent")

        WithdrawnPaymentRecords::PurgeJob.perform_now

        assert_not WithdrawnPaymentRecord.exists?(@expired.id), "5년 경과 행은 삭제된다"
        assert WithdrawnPaymentRecord.exists?(@recent.id), "5년 미만 행은 유지된다"
      end
    end

    test "5년 경계 — 경과 행만 삭제하고 경과 전 행은 유지한다 (withdrawn_at < 5.years.ago)" do
      travel_to Time.current do
        @just_past = create_record!(withdrawn_at: 5.years.ago - 1.second, pg_order_id: "order-purge-past")
        @just_before = create_record!(withdrawn_at: 5.years.ago + 1.second, pg_order_id: "order-purge-before")

        WithdrawnPaymentRecords::PurgeJob.perform_now

        assert_not WithdrawnPaymentRecord.exists?(@just_past.id), "5년+1초 행은 삭제된다"
        assert WithdrawnPaymentRecord.exists?(@just_before.id), "5년-1초 행은 유지된다"
      end
    end

    test "재실행 멱등 — 두 번 수행해도 오류 없고 두 번째 삭제는 0건이다" do
      travel_to Time.current do
        create_record!(withdrawn_at: 5.years.ago - 1.day, pg_order_id: "order-purge-idem")

        assert_equal 1, WithdrawnPaymentRecords::PurgeJob.perform_now
        assert_equal 0, WithdrawnPaymentRecord.expired.count

        assert_nothing_raised { WithdrawnPaymentRecords::PurgeJob.perform_now }
        assert_equal 0, WithdrawnPaymentRecord.expired.count, "두 번째 수행에서 추가 삭제는 없다"
      end
    end

    test "로그에는 삭제 건수만 남고 개인정보·주문번호 값은 남지 않는다" do
      travel_to Time.current do
        create_record!(withdrawn_at: 5.years.ago - 1.day, pg_order_id: "order-purge-log-secret")

        logs = StringIO.new
        original_logger = Rails.logger
        # BroadcastLogger는 stub 불가 — 캡처용 단일 로거로 교체했다가 복원한다.
        Rails.logger = ActiveSupport::Logger.new(logs)
        WithdrawnPaymentRecords::PurgeJob.perform_now
        Rails.logger = original_logger

        assert logs.string.include?("purged=1"), "삭제 건수가 기록된다"
        assert_not logs.string.include?("order-purge-log-secret"),
                   "로그에 주문번호 값이 남으면 안 된다"
      end
    end
  end
end

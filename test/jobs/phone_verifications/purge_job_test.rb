require "test_helper"

module PhoneVerifications
  # AUTH-9 — 휴대폰 인증 기록 파기 잡. 생성 24시간 경과 행만 삭제(PURGE_AFTER 단일 출처),
  # 그 이전 행(23시간·방금·consumed 30분 창 내)은 유지. delete_all이라 재실행 멱등.
  class PurgeJobTest < ActiveSupport::TestCase
    test "생성 24시간 경과 행만 삭제하고 나머지는 유지한다" do
      travel_to Time.current do
        @old = PhoneVerification.create!(phone: "01011111111", code: "111111",
                                         created_at: 25.hours.ago, expires_at: 25.hours.ago + 5.minutes)
        @recent = PhoneVerification.create!(phone: "01022222222", code: "222222",
                                            created_at: 23.hours.ago, expires_at: 23.hours.ago + 5.minutes)
        @fresh = PhoneVerification.create!(phone: "01033333333", code: "333333",
                                           created_at: Time.current, expires_at: 5.minutes.from_now)
        @consumed = PhoneVerification.create!(phone: "01044444444", code: "444444",
                                              created_at: 20.minutes.ago, expires_at: 20.minutes.ago + 5.minutes,
                                              consumed_at: 10.minutes.ago)

        PhoneVerifications::PurgeJob.perform_now

        assert_not PhoneVerification.exists?(@old.id), "24시간 경과 행은 삭제된다"
        assert PhoneVerification.exists?(@recent.id), "23시간 행은 유지된다"
        assert PhoneVerification.exists?(@fresh.id), "방금 생성 행은 유지된다"
        assert PhoneVerification.exists?(@consumed.id), "consumed(30분 창 내) 행은 유지된다"
      end
    end

    test "24시간 경계 — 경과 행만 삭제하고 경과 전 행은 유지한다 (created_at < 24.hours.ago)" do
      travel_to Time.current do
        @just_past = PhoneVerification.create!(phone: "01055555555", code: "555555",
                                               created_at: 24.hours.ago - 1.second,
                                               expires_at: 24.hours.ago - 1.second + 5.minutes)
        @just_before = PhoneVerification.create!(phone: "01066666666", code: "666666",
                                                 created_at: 24.hours.ago + 1.second,
                                                 expires_at: 24.hours.ago + 1.second + 5.minutes)

        PhoneVerifications::PurgeJob.perform_now

        assert_not PhoneVerification.exists?(@just_past.id), "24시간+1초 행은 삭제된다"
        assert PhoneVerification.exists?(@just_before.id), "24시간-1초 행은 유지된다"
      end
    end

    test "perform 뒤에도 방금 생성·consumed 행이 남아 가입 이중 검증(consumed_recently)이 통과한다 (AUTH-9)" do
      travel_to Time.current do
        fresh = PhoneVerification.create!(phone: "01088888888", code: "888888",
                                          created_at: Time.current, expires_at: 5.minutes.from_now)
        consumed = PhoneVerification.create!(phone: "01099999999", code: "999999",
                                             created_at: 10.minutes.ago, expires_at: 10.minutes.ago + 5.minutes,
                                             consumed_at: 5.minutes.ago)

        PhoneVerifications::PurgeJob.perform_now

        assert PhoneVerification.exists?(fresh.id), "방금 생성 행은 파기되면 안 된다"
        assert PhoneVerification.exists?(consumed.id), "consumed(30분 창 내) 행은 파기되면 안 된다"
        assert PhoneVerification.consumed_recently.where(phone: "01099999999").exists?,
               "파기 잡이 consumed_recently 창을 침해하면 가입 이중 검증이 깨진다"
      end
    end

    test "재실행 멱등 — 두 번 수행해도 오류 없고 두 번째 삭제는 0건이다" do
      travel_to Time.current do
        PhoneVerification.create!(phone: "01077777777", code: "777777",
                                  created_at: 25.hours.ago, expires_at: 25.hours.ago + 5.minutes)

        PhoneVerifications::PurgeJob.perform_now
        assert_equal 0, PhoneVerification.purgeable.count

        assert_nothing_raised { PhoneVerifications::PurgeJob.perform_now }
        assert_equal 0, PhoneVerification.purgeable.count, "두 번째 수행에서 추가 삭제는 없다"
      end
    end
  end
end

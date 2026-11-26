require "test_helper"

# AUTH-9 — 휴대폰 인증 기록 파기 잡의 recurring.yml 등록 대조(설정 드리프트 방지).
# production·development 양쪽 블록에 phone_verifications_purge가 같은 클래스·스케줄로
# 등록돼 있는지 단언한다(선례: dashboards/reminder_actions_service_test의 recurring 대조).
# test 블록은 파일에 없는 것이 기존 관례다.
module PhoneVerifications
  class RecurringRegistrationTest < ActiveSupport::TestCase
    test "recurring.yml에 파기 잡이 production·development 양쪽에 04:30 KST로 등록돼 있다 (AUTH-9)" do
      config = YAML.load_file(Rails.root.join("config/recurring.yml"))
      %w[production development].each do |env|
        entry = config.fetch(env).fetch("phone_verifications_purge")
        assert_equal "PhoneVerifications::PurgeJob", entry.fetch("class"), "#{env} 잡 클래스"

        fields = entry.fetch("schedule").split
        assert_equal "30", fields[0], "#{env} 분 필드(30분)"
        assert_equal "4", fields[1], "#{env} 시 필드(04시)"
        assert_equal "*", fields[2], "#{env} 매일(일)"
        assert_equal "*", fields[3], "#{env} 매월(월)"
        assert_equal "*", fields[4], "#{env} 모든 요일"
        assert_equal "Asia/Seoul", fields[5], "#{env} 시간대(TIME-1 — KST fugit 접미사)"
      end
    end
  end
end

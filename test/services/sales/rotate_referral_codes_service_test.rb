require "test_helper"

# 추천 코드 로테이션(SALES-2 — F-SALES). 주간 재생성·기존 코드 조기 종료(P4 이력 보존)·
# 당일 발급분 멱등 가드(SEC-5)·정지 rep 제외·주간 경계(일요일→월요일) 끊김 없음 검증.
# 시나리오 기준: PRD §6.20 SALES-2·_workspace/05_review.md §4 Tester 중점 10번.
#
# [날짜 폭탄 수정 — 2026-11-25 Tester 실측] fixture의 유효 창은 적재 시점(Date.current)
# 상대값(valid_from = 적재일-2)이라 고정 travel 일자와 어긋난다. 적재일과 travel일(11-23)의
# 간격이 2일이 되는 날에는 fixture valid_from이 travel Date.current와 겹쳐 서비스의 당일
# 발급분 멱등 가드(SEC-5)가 회전을 막아 5건이 깨졌다(작성일 11-19에는 통과). fixtures 파일
# 헤더의 규칙("travel하는 테스트는 이 fixtures를 경계 판정에 쓰지 않는다")에 따라,
# fixture 행의 창을 travel 기준 상대값으로 재설정(pin)한 뒤 사용한다.
class Sales::RotateReferralCodesServiceTest < ActiveSupport::TestCase
  TRAVEL_MONDAY = Date.new(2026, 11, 23) # 실제 월요일(TIME-1 — KST)

  test "활동 rep 전체에 새 코드를 발급하고 기존 유효 코드를 어제로 조기 종료한다 (SALES-2)" do
    travel_to(TRAVEL_MONDAY) do
      old_kim = pinned_current_code(:sales_kim_current)
      old_park = pinned_current_code(:officer_park_current)

      results = Sales::RotateReferralCodesService.call

      assert_equal [ old_kim.sales_rep, old_park.sales_rep ].map(&:id),
                   results.map(&:sales_rep_id), "활동 rep만 대상(정지 제외)"

      new_kim = old_kim.sales_rep.current_referral_code
      assert_equal Date.current, new_kim.valid_from
      assert_equal Date.current + Sales::RotateReferralCodesService::VALIDITY_DAYS, new_kim.valid_until
      assert_not_equal old_kim.code, new_kim.code
      assert_equal Date.current - 1.day, old_kim.reload.valid_until, "기존 코드는 어제까지 유효(조기 종료)"

      new_park = old_park.sales_rep.reload.current_referral_code
      assert_not_equal old_park.code, new_park.code
      assert_equal Date.current, new_park.valid_from
    end
  end

  test "기존 코드 행은 삭제되지 않고 이력으로 보존된다 (P4)" do
    travel_to(TRAVEL_MONDAY) do
      pinned_current_code(:sales_kim_current)
      rep = sales_reps(:sales_kim)
      before = rep.sales_referral_codes.count

      Sales::RotateReferralCodesService.call(rep:)

      assert_equal before + 1, rep.sales_referral_codes.count, "이력 행 추가 — 삭제 없음"
      assert SalesReferralCode.exists?(code: "KIM2026A"), "구 코드 행 보존(P4 감사 근거)"
    end
  end

  test "재실행(같은 날)은 멱등으로 무변경이다 — 활동 rep마다 유효 코드 1개 (SEC-5)" do
    travel_to(TRAVEL_MONDAY) do
      pinned_current_code(:sales_kim_current)
      rep = sales_reps(:sales_kim)
      first = Sales::RotateReferralCodesService.call(rep:).sole

      assert_no_difference -> { rep.sales_referral_codes.count } do
        second_run = Sales::RotateReferralCodesService.call(rep:)
        assert_empty second_run, "당일 발급분 존재 — nil(무변경)"
      end

      assert_equal first.code, rep.reload.current_referral_code.code
      assert_equal 1, rep.sales_referral_codes.current_valid.count
      assert_equal first.id, rep.current_referral_code.id
    end
  end

  test "정지 rep은 전체 로테이션 대상에서 제외된다 (SALES-2)" do
    travel_to(TRAVEL_MONDAY) do
      suspended = sales_reps(:suspended_choi)
      old = suspended.sales_referral_codes.create!(code: "SUSPEND1", valid_from: Date.current - 2,
                                                   valid_until: Date.current + 4)

      Sales::RotateReferralCodesService.call

      assert_equal old.reload.valid_until, Date.current + 4, "정지 rep 코드는 조기 종료되지 않는다"
      assert_not_includes suspended.sales_referral_codes.reload.map(&:valid_from), Date.current,
                          "정지 rep는 새 코드가 발급되지 않는다"
    end
  end

  test "rep 단독 지정 시 해당 rep만 회전한다 (SALES-1 콘솔 수동 재생성 경로)" do
    travel_to(TRAVEL_MONDAY) do
      pinned_current_code(:sales_kim_current)
      pinned_current_code(:officer_park_current)
      kim = sales_reps(:sales_kim)
      park = sales_reps(:officer_park)
      park_code_before = park.current_referral_code.id

      results = Sales::RotateReferralCodesService.call(rep: kim)

      assert_equal [ kim.id ], results.map(&:sales_rep_id)
      assert_equal park_code_before, park.reload.current_referral_code.id, "미지정 rep는 무변경"
    end
  end

  test "주간 경계 — 일요일까지 유효한 코드는 월요일 로테이션 후 끊김 없이 교체된다 (SALES-2·TIME-1)" do
    monday_at = Time.zone.local(TRAVEL_MONDAY.year, TRAVEL_MONDAY.month, TRAVEL_MONDAY.day, 0, 0)

    # 월요일 00:00 로테이션 — 발급분: 월요일~+6일(=다음 일요일) 유효
    travel_to(monday_at) do
      pinned_current_code(:sales_kim_current) # 회전이 실제로 일어나게 한다(멱등 가드 우회 없음)
      Sales::RotateReferralCodesService.call(rep: sales_reps(:sales_kim))
      @issued = sales_reps(:sales_kim).current_referral_code
      assert_equal TRAVEL_MONDAY, @issued.valid_from
      assert_equal TRAVEL_MONDAY + 6.days, @issued.valid_until, "다음 주간 로테이션 전날(일요일)까지 유효"
    end

    # 일요일 — 구 코드 유효(양끝 포함)
    travel_to(monday_at + 6.days) do
      assert_includes SalesReferralCode.current_valid, @issued.reload
    end

    # 다음 월요일 00:00 로테이션 — 구 코드 만료·신규 코드 즉시 유효(끊김 없음)
    travel_to(monday_at + 7.days) do
      assert_not_includes SalesReferralCode.current_valid, @issued, "어제(일요일)부로 만료"
      Sales::RotateReferralCodesService.call(rep: sales_reps(:sales_kim))
      next_code = sales_reps(:sales_kim).current_referral_code
      assert_not_equal @issued.code, next_code.code
      assert_equal Date.current, next_code.valid_from, "월요일 0시부터 새 코드 유효"
      assert_equal @issued.valid_until, next_code.valid_from - 1.day, "만료일과 발급일이 맞닿는다"
    end
  end

  test "발급 코드는 8자 안전 문자열 규격을 충족한다 (SALES-2)" do
    travel_to(TRAVEL_MONDAY) do
      pinned_current_code(:sales_kim_current)
      code = Sales::RotateReferralCodesService.call(rep: sales_reps(:sales_kim)).sole
      assert_equal 8, code.code.length
      code.code.each_char { |ch| assert_includes SalesReferralCode::SAFE_ALPHABET, ch }
    end
  end

  private

  # fixture 코드 행의 유효 창을 travel 기준 상대값으로 재설정한다(헤더 주석 참조).
  # travel 블록 안에서 호출한다(날짜 폭탄 방지 — 고정 날짜를 블록 밖에서 만들지 않는다).
  def pinned_current_code(fixture_name)
    code = sales_referral_codes(fixture_name)
    code.update!(valid_from: Date.current - 2, valid_until: Date.current + 4)
    code
  end
end

module App
  # 프로필 설정 화면(AUTH-1.3) 보조 — 필드 오류 상태 클래스와 은행 선택 목록 제공
  module ProfilesHelper
    # 국내 주요 은행·금융기관(발행인 입금 계좌 선택용) — 대략 가나다순
    BANKS = [
      "경남은행", "광주은행", "국민은행", "기업은행", "농협은행", "대구은행",
      "부산은행", "산업은행", "새마을금고", "수협은행", "SC제일은행", "씨티은행",
      "우리은행", "우체국", "전북은행", "제주은행", "카카오뱅크", "케이뱅크",
      "토스뱅크", "하나은행"
    ].freeze

    def bank_options
      BANKS
    end

    # AUTH-1.3 — 필드별 오류 상태를 반영한 입력 필드 공통 클래스(DESIGN 준수: 트랜지션·포커스 링)
    def profile_input_classes(user, attribute)
      base = "mt-1 block w-full rounded-xl border bg-white px-3.5 py-2.5 text-stone-800 shadow-sm " \
             "transition placeholder:text-stone-400 focus:outline-none focus:ring-2"
      if user.errors.key?(attribute)
        base + " border-red-400 hover:border-red-400 focus:border-red-500 focus:ring-red-400/30"
      else
        base + " border-stone-300 hover:border-stone-400 focus:border-emerald-700 focus:ring-emerald-700/30"
      end
    end

    def profile_error_message(user, attribute)
      user.errors[attribute].first
    end

    # REM-3 — 발송 가능 요일(월~금 고정 — 주말은 정책상 상시 불허)
    REMIND_WDAY_OPTIONS = [
      [ "월", 1 ], [ "화", 2 ], [ "수", 3 ], [ "목", 4 ], [ "금", 5 ]
    ].freeze

    # 뷰는 헬퍼 상수를 직접 참조할 수 없다(ERB 컴파일 모듈 lookup 불가) — bank_options 선례.
    def remind_wday_options
      REMIND_WDAY_OPTIONS
    end

    # REM-3 — 시작 시각 선택 목록(09~17시 — 종료 18시 고정 상한 내). 고정 경계 내 축소만 허용.
    def remind_start_hour_options
      (User::REMIND_MIN_HOUR...User::REMIND_MAX_HOUR).map { |h| [ "%02d시" % h, h ] }
    end

    # REM-3 — 종료 시각 선택 목록(10~18시 — 시작보다 늦어야 함)
    def remind_end_hour_options
      ((User::REMIND_MIN_HOUR + 1)..User::REMIND_MAX_HOUR).map { |h| [ "%02d시" % h, h ] }
    end

    # 요일 체크박스 공통 클래스(DESIGN — 터치 타깃·포커스 링)
    def remind_wday_checkbox_classes
      "h-4 w-4 rounded border-stone-300 text-emerald-700 focus:ring-2 focus:ring-emerald-700/30 cursor-pointer"
    end
  end
end

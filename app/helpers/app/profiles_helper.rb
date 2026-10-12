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
  end
end

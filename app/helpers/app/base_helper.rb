module App
  # 표면 ②(/app) 공통 뷰 헬퍼 — 사이드바 내비 구성·대시보드 카드 데이터·입력 필드 공통 클래스.
  module BaseHelper
    # 사이드바 메뉴 — 대시보드·청구서(INV)·거래처(CLIENT-1)·품목(CLIENT-2)·요금제(F-PLAN)·설정 활성.
    # 활성 판정은 요청 경로 기준. 미구현 메뉴는 링크 없이 구조만 안내한다(플랜 결정 #2).
    # locked: 프로필 미완료(AUTH-1.3) 동안 잠금 표시 — 클릭은 가능하되 가드가 플래시와 함께 안내한다.
    def app_nav_items
      locked = Current.user.display_name.blank?
      [
        { label: "대시보드", path: app_root_path, active: request.path == app_root_path,
          disabled: false, locked: },
        { label: "청구서", path: app_invoices_path, active: request.path.start_with?(app_invoices_path),
          disabled: false, locked: },
        { label: "거래처", path: app_clients_path, active: request.path.start_with?(app_clients_path),
          disabled: false, locked: },
        { label: "품목", path: app_items_path, active: request.path.start_with?(app_items_path),
          disabled: false, locked: },
        { label: "요금제", path: app_billing_path, active: request.path.start_with?(app_billing_path),
          disabled: false, locked: },
        { label: "설정", path: edit_app_profile_path, active: request.path.start_with?(app_profile_path),
          disabled: false, locked: false }
      ]
    end

    # 거래처·품목 폼 입력 필드 공통 클래스 — 필드 오류 상태를 반영한다(DESIGN 트랜지션·포커스 링).
    def form_input_classes(record, attribute)
      base = "mt-1 block w-full rounded-xl border bg-white px-3.5 py-2.5 text-stone-800 shadow-sm " \
             "transition placeholder:text-stone-400 focus:outline-none focus:ring-2"
      if record.errors.key?(attribute)
        base + " border-red-400 hover:border-red-400 focus:border-red-500 focus:ring-red-400/30"
      else
        base + " border-stone-300 hover:border-stone-400 focus:border-emerald-700 focus:ring-emerald-700/30"
      end
    end

    def form_error_message(record, attribute)
      record.errors[attribute].first
    end

    # DESIGN-2·DESIGN-8 — 활성 메뉴는 딥 그린 배경 + 좌측 인디케이터 바로 강조,
    # 터치 타깃 최소 높이(DESIGN-6)·focus-visible 링·150ms 트랜지션(3a 랜딩과 동일 문법).
    def app_nav_link_classes(active:)
      base = "relative flex min-h-11 items-center rounded-lg px-3 text-sm font-semibold transition duration-150 " \
             "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-700"
      if active
        "#{base} bg-emerald-800/10 text-emerald-900 " \
          "before:absolute before:inset-y-2 before:left-0 before:w-1 before:rounded-full before:bg-emerald-700"
      else
        "#{base} text-stone-600 hover:bg-stone-100 hover:text-stone-900"
      end
    end

    # DASH-2 — 오늘의 액션 유형별 상태 뱃지(DESIGN-2 상태색 3종: 마감 대기 녹색·답변 대기 주황).
    def dash_action_badge(kind)
      spec = {
        "closure" => [ "마감 대기", "bg-green-50 text-green-700 ring-1 ring-inset ring-green-200" ],
        "answer" => [ "답변 대기", "bg-orange-50 text-orange-600 ring-1 ring-inset ring-orange-200" ]
      }.fetch(kind)
      content_tag :span, spec.first,
                  class: "inline-flex items-center rounded-full px-2.5 py-1 text-xs font-bold #{spec.last}"
    end

    # DASH-2 — 액션 유형별 인라인 SVG 아이콘 경로(장식용, aria-hidden으로 접근성 트리 제외).
    def dash_action_icon_path(kind)
      {
        "closure" => "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",                 # 마감(체크)
        "answer" => "M20.25 8.511c.884.284 1.5 1.128 1.5 2.097v4.286c0 1.136-.847 2.1-1.98 2.193-.34.027-.68.052-1.02.072v3.091l-3-3c-1.354 0-2.694-.055-4.02-.163a2.115 2.115 0 0 1-.825-.242m9.345-8.334a2.126 2.126 0 0 0-.476-.095 48.64 48.64 0 0 0-8.048 0c-1.131.094-1.976 1.057-1.976 2.192v4.286c0 .837.46 1.58 1.155 1.951m9.345-8.334V6.637c0-1.621-1.152-3.026-2.76-3.235A48.455 48.455 0 0 0 11.25 3c-2.115 0-4.198.137-6.24.402-1.608.209-2.76 1.614-2.76 3.235v6.226c0 1.621 1.152 3.026 2.76 3.235.577.075 1.157.14 1.74.194V21l4.155-4.155", # 문의(대화)
        "empty" => "M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" # 빈 상태(종이비행기)
      }.fetch(kind)
    end

    # DESIGN-3 — 금액 표기: 원 단위 3자리 콤마. 수치 슬롯은 tabular-nums와 짝을 이룬다.
    def won(amount)
      "#{number_with_delimiter(amount)}원"
    end

    # 날짜 표기 — ISO 서식(목록·상세 공통)
    def display_date(date)
      date&.strftime("%Y-%m-%d")
    end

    # 일시 표기 — 분 단위(KST, TIME-1). 열람 이력(SHARE-3) 등 정확한 시각 안내에 쓴다.
    def display_datetime(datetime)
      datetime&.strftime("%Y-%m-%d %H:%M")
    end
  end
end

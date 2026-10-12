module App
  # 표면 ②(/app) 공통 뷰 헬퍼 — 사이드바 내비 구성·대시보드 카드 데이터·입력 필드 공통 클래스.
  module BaseHelper
    # 사이드바 메뉴 — 대시보드·거래처(CLIENT-1)·품목(CLIENT-2)·설정 활성, 청구서만 준비 중 배지.
    # 활성 판정은 요청 경로 기준. 미구현 메뉴는 링크 없이 구조만 안내한다(플랜 결정 #2).
    def app_nav_items
      [
        { label: "대시보드", path: app_root_path, active: request.path == app_root_path, disabled: false },
        { label: "청구서", path: nil, active: false, disabled: true },
        { label: "거래처", path: app_clients_path, active: request.path.start_with?(app_clients_path), disabled: false },
        { label: "품목", path: app_items_path, active: request.path.start_with?(app_items_path), disabled: false },
        { label: "설정", path: edit_app_profile_path, active: request.path.start_with?(app_profile_path), disabled: false }
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

    # DESIGN-2 — 활성 메뉴는 딥 그린 배경으로 강조, 터치 타깃 최소 높이 유지(DESIGN-6).
    def app_nav_link_classes(active:)
      base = "flex min-h-11 items-center rounded-lg px-3 text-sm font-semibold transition"
      if active
        "#{base} bg-emerald-800/10 text-emerald-900"
      else
        "#{base} text-stone-600 hover:bg-stone-100 hover:text-stone-900"
      end
    end

    # DASH-1 요약 카드 3종(미수 총액·연체 건수·금액·7일 내 만기) — 상태색 점으로 카드 브랜딩(DESIGN-2).
    # 수치 슬롯은 F-INV 데이터 확보 전까지 채우지 않는다(거짓 0원 금지 — 02_prd_update 결정).
    def dash_summary_cards
      [
        { label: "미수 총액", dot_class: "bg-stone-400" },
        { label: "연체 건수·금액", dot_class: "bg-orange-500" },
        { label: "7일 내 만기", dot_class: "bg-stone-400" }
      ]
    end
  end
end

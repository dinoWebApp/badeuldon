module App
  # 표면 ②(/app) 공통 뷰 헬퍼 — 사이드바 내비 구성·대시보드 카드 데이터.
  module BaseHelper
    # 사이드바 메뉴 — 대시보드(활성)·청구서·거래처(미구현: 준비 중 배지)·설정(AUTH-1.3 프로필).
    # 활성 판정은 요청 경로 기준. 미구현 메뉴는 링크 없이 구조만 안내한다(플랜 결정 #2).
    def app_nav_items
      [
        { label: "대시보드", path: app_root_path, active: request.path == app_root_path, disabled: false },
        { label: "청구서", path: nil, active: false, disabled: true },
        { label: "거래처", path: nil, active: false, disabled: true },
        { label: "설정", path: edit_app_profile_path, active: request.path.start_with?(app_profile_path), disabled: false }
      ]
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

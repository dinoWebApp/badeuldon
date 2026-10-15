Rails.application.routes.draw do
  # ── 인증(표면 ② 진입 전) — AUTH-1 이메일/비밀번호, AUTH-8 비밀번호 재설정 ──
  resource :session, only: %i[ new create destroy ]                    # 로그인/로그아웃
  resource :registration, only: %i[ new create ]                       # 회원가입(SURF-4 가입 단일 진입)
  resources :passwords, param: :token, only: %i[ new create edit update ]  # 비밀번호 재설정(AUTH-8)

  # ── 표면 ② 대시보드(/app) — 로그인 U1 전용. require_authentication 기본 가드 적용(공개 예외 없음) ──
  namespace :app do
    root to: "dashboards#show"                  # DASH-1/2/4 — /app 진입 셸
    resource :profile, only: %i[ edit update ]  # AUTH-1.3 최초 프로필 설정(/app/profile)
    resources :clients                          # CLIENT-1 — 거래처 CRUD
    resources :items                            # CLIENT-2 — 품목 라이브러리 CRUD
    resources :invoices do                      # INV — 초안 CRUD + 상태 전환(member)
      member do
        patch :issue             # 초안 → 발행(INV-4)
        patch :void              # 발행 계열 → 무효(INV-6)
        patch :regenerate_token  # 링크 재발급(SHARE-2 — 기존 링크 즉시 무효·유효기간 유지)
      end
      # F-PAY — 입금 기록·마감(PAY-1 원클릭·PAY-2 부분입금 겸용 create). 청구서 하위 자원으로
      # 소유권을 스코프하며 전이 처리는 Payments::RecordService가 담당한다.
      resources :payments, only: :create
    end
    # F-PROMISE — 문의 답변 등록(PROMISE-6). 응답 자원의 상태 전이(무답변→답변·1문의 1답변)라
    # member 액션으로 정당화하며, 소유권은 App::PromisesController가 청구서 스코프로 격리한다.
    resources :promises, only: [] do
      member { patch :answer }
    end

    # ── F-PLAN 구독·과금(PLAN-1~5) ──
    resource :billing, only: :show           # 요금제 페이지(/app/billing)
    resource :subscription, only: %i[ create update ] do
      # 카드 인증 위젯 successUrl(토스가 GET 리다이렉트) — authKey 수신 전용(이슈 #5).
      # GET은 CSRF 검증 대상이 아니므로 해지 같은 상태 변경을 이 경로에 두지 않는다.
      get :card_callback, to: "subscriptions#update"
      # 해지 — PATCH 전용(CSRF 토큰 검증 대상 — 이슈 #5)
      patch :cancel
    end
    resources :orders, only: :create do
      collection { get :callback }           # 수금 패스 결제 위젯 성공/실패 리다이렉트 수신
    end
  end

  # ── 토스페이먼츠 웹훅(PLAN-5) — 토스 서버 → 우리 서버(비인증 서버 간 호출) ──
  post "/webhooks/toss", to: "webhooks/toss#create"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ── 표면 ③ 청구서 뷰어(/b/:token) ───────────────
  # 비로그인 U2(VIEW-1·P3), 토큰으로만 조회(SHARE-1). noindex·robots 차단(SURF-3 —
  # NOINDEX_PATH_PREFIXES "/b/" + public/robots.txt), ③→① 링크 없음(SURF-4).
  # F-PROMISE — 응답 접수는 비인증 POST(토큰=권한·PROMISE-2), 완료 화면은 GET으로 PRG 전환해
  # 재제출·이중 접수를 막는다. 두 경로 모두 뷰어와 동일 토큰 가드(만료·폐기 404)를 공유한다.
  scope "/b" do
    get "/:token", to: "viewer#show", as: :viewer
    post "/:token/promises", to: "viewer#create", as: :viewer_promises
    get "/:token/promises/thanks", to: "viewer#promise_thanks", as: :viewer_promise_thanks
  end

  # ── 표면 ① 랜딩 ───────────────────────────────
  # 비로그인 공개(SURF-1) — 색인 허용(SURF-3), ①→② 진입은 가입 CTA 단일(SURF-4)
  root "landing#index"
end

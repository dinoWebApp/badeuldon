Rails.application.routes.draw do
  # ── 인증(표면 ② 진입 전) — AUTH-1 이메일/비밀번호, AUTH-8 비밀번호 재설정 ──
  resource :session, only: %i[ new create destroy ]                    # 로그인/로그아웃
  resource :registration, only: %i[ new create ]                       # 회원가입(SURF-4 가입 단일 진입)
  get "welcome", to: "registrations#welcome"                           # 가입 직후 임시 안내(/app 대시보드 후속 작업)
  resources :passwords, param: :token, only: %i[ new create edit update ]  # 비밀번호 재설정(AUTH-8)

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # ── 표면 ① 랜딩 ───────────────────────────────
  # 비로그인 공개(SURF-1) — 색인 허용(SURF-3), ①→② 진입은 가입 CTA 단일(SURF-4)
  root "landing#index"
end

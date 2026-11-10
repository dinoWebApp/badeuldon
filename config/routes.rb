Rails.application.routes.draw do
  # ── 인증(표면 ② 진입 전) — AUTH-1 이메일/비밀번호, AUTH-8 비밀번호 재설정 ──
  resource :session, only: %i[ new create destroy ]                    # 로그인/로그아웃
  resource :registration, only: %i[ new create ]                       # 회원가입(SURF-4 가입 단일 진입)
  resources :passwords, param: :token, only: %i[ new create edit update ]  # 비밀번호 재설정(AUTH-8)

  # ── 표면 ② 대시보드(/app) — 로그인 U1 전용. require_authentication 기본 가드 적용(공개 예외 없음) ──
  namespace :app do
    root to: "dashboards#show"                  # DASH-1/2/4 — /app 진입 셸
    resource :profile, only: %i[ edit update ]  # AUTH-1.3 최초 프로필 설정(/app/profile)
    resources :clients do                       # CLIENT-1 — 거래처 CRUD
      member do
        patch :suspend_reminders  # REM-7 — 거래처 단위 발송 보류(전 청구 일시정지)
        patch :resume_reminders   # REM-7 — 보류 재개(수신거부는 재개 경로가 없다 — VIEW-7)
      end
    end
    resources :items                            # CLIENT-2 — 품목 라이브러리 CRUD
    resources :invoices do                      # INV — 초안 CRUD + 상태 전환(member)
      member do
        patch :issue             # 초안 → 발행(INV-4)
        patch :void              # 발행 계열 → 무효(INV-6)
        patch :regenerate_token  # 링크 재발급(SHARE-2 — 기존 링크 즉시 무효·유효기간 유지)
        patch :suspend_reminders # REM-7 — 청구 건 단위 발송 보류(REM-11 「보류하기」과 동일 동작)
        patch :resume_reminders  # REM-7 — 청구 건 단위 보류 재개
        post :remind             # REM-8 — 수동 발송(현재 상황에 맞는 다음 1통·플랜 무관)
        post :restart_reminders  # REM-12/13 — 시퀀스 수동 재개(U1의 수동 재요청 — 자동 재개 없음)
        get :payment_pdf         # PAY-6 — 수금완료 증빙 PDF(paid 한정·본인 소유 — Invoices::ReceiptPdfService)
      end
      # F-PAY — 입금 기록·마감(PAY-1 원클릭·PAY-2 부분입금 겸용 create). 청구서 하위 자원으로
      # 소유권을 스코프하며 전이 처리는 Payments::RecordService가 담당한다.
      resources :payments, only: :create
      # CLIENT-4 — 발행 직전 거래처 지급 성적표 요약(폼 거래처 선택 시 Turbo fetch).
      # 거래처 성적의 읽기라 collection GET으로 정당화 — 소유권은 컨트롤러가 격리한다.
      collection { get :scorecard }
    end
    # F-PROMISE — 문의 답변 등록(PROMISE-6). 응답 자원의 상태 전이(무답변→답변·1문의 1답변)라
    # member 액션으로 정당화하며, 소유권은 App::PromisesController가 청구서 스코프로 격리한다.
    resources :promises, only: [] do
      member { patch :answer }
    end

    # ── INV-7 반복 청구 — 스케줄 CRUD(부분: 열람·생성만, 수정 화면 없음) + 일시정지·재개·
    # 종료(member PATCH — 스케줄 상태 전이라 예외적 동사로 정당화). 발행 자체는 매일
    # RecurringInvoices::IssueJob(06:30 KST)이 스캔하며 이 리소스는 U1 관리 화면이다.
    resources :recurring_invoices, only: %i[ index new create show ] do
      member do
        patch :pause
        patch :resume
        patch :cancel
      end
    end

    # ── F-ADMIN Run C — 운영 공지 U1 노출(ADMIN-7). PRD 문언의 경로 `/app/notice`를
    # path: "notice"로 준수한다(컨트롤러명은 Notices). 읽음 기록은 자원의 상태 생성 성격이라
    # member POST로 정당화 — NoticeReads::MarkService로 멱등(SEC-5).
    resources :notices, only: %i[ index show ], path: "notice" do
      member { post :mark_read }
    end

    # ── F-ADMIN Run C — 1:1 문의 티켓(ADMIN-8). 추가 질문은 스레드 상의 발화 추가·재문의
    # 상태 전이라 member POST로 정당화. 작성 rate_limit은 컨트롤러(5회/시간).
    resources :tickets, only: %i[ index new create show ] do
      member { post :follow_up }
      # W-1(05_review) — 첨부 이미지 인증 서빙(AS 공개 리다이렉트 대체 — 소유 U1 세션 전제).
      # GET /app/tickets/:ticket_id/messages/:message_id/image
      get "messages/:message_id/image" => "tickets#image", as: :message_image
    end

    # ── F-DASH 리포트(DASH-5·DASH-6) — 거래처별 지연·월간 수금 추이·신고 주기 집계(/app/report) ──
    resource :report, only: :show

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

  # ── 포트원 웹훅(PLAN-5) — 포트원 서버 → 우리 서버(비인증 서버 간 호출) ──
  post "/webhooks/portone", to: "webhooks/portone#create"

  # ── 표면 ④ 관리자 콘솔(/admin) — AUTH-7 전용 계정·2FA(TOTP) 필수, ADMIN-1 ──
  # U1 세션과 완전 분리(admin_sessions · session[:admin_session_token]). 전 경로 noindex(SURF-3).
  # 2FA 단계(totp_setup/totp_confirm/totp_verify)는 session 자원의 상태 전이 성격이라
  # collection으로 정당화한다 — URL 동사 없이 플로우 단계를 표현.
  namespace :admin do
    root to: "dashboards#show"                                    # ADMIN-1 운영 대시보드(Run A 골격)
    resource :session, only: %i[ new create destroy ] do
      collection do
        get  :totp_setup    # 2단계 화면(미등록: QR+시크릿 / 등록: 코드 입력)
        post :totp_confirm  # 최초 2FA 등록 완료(otp_confirmed_at 기록 — AUTH-7.1)
        post :totp_verify   # 등록 계정 코드 검증
      end
    end
    resources :passwords, param: :token, only: %i[ new create edit update ]  # AUTH-7.6 재설정

    # Run B 결선(3-S) — ADMIN-2 감사 로그 / ADMIN-3 회원 관리 / ADMIN-4 결제·매출 관리.
    # 계약: _workspace/02_prd_update.md 확정 해석 1 그대로. 상태 전이(정지 전환·플랜 변경·
    # 환불 기록)는 예외적 동사라 member PATCH로 정당화.
    resources :audit_logs, only: :index                                             # ADMIN-2
    resources :admins, only: %i[ index new create ] do                              # ADMIN-1 관리자 계정 콘솔(owner 전용 — AUTH-7.2). role 승강·잠금 해제는 상태 전이라 member PATCH로 정당화
      member do
        patch :change_role
        patch :unlock
      end
    end
    resources :coupons                                                              # ADMIN-4 쿠폰 관리(표준 CRUD — Q12)
    resources :members, only: %i[ index show destroy ] do                           # ADMIN-3 (계정 삭제·데이터 파기 — Q13)
      member do
        patch :toggle_suspension
        patch :change_plan
      end
    end
    resources :orders, only: %i[ index show ] do                                    # ADMIN-4
      member do
        patch :mark_refunded
      end
    end

    # Run C 결선 — ADMIN-6 운영 공지 관리(CRUD + 발행/종료). 발행(publish)·종료(close)는
    # 상태 전이라 member PATCH로 정당화.
    resources :notices do
      member do
        patch :publish
        patch :close
      end
    end

    # Run C 결선(3-b) — ADMIN-8 티켓 관리. 답변 등록(reply)·종료(close)는 상태 전이·발화
    # 추가라 member 액션으로 정당화(답변 POST — 답변 등록은 발화 추가 성격).
    resources :tickets, only: %i[ index show ] do
      member do
        post :reply
        patch :close
      end
      # W-1(05_review) admin 측 — 첨부 이미지 인증 서빙(AS 공개 리다이렉트 대체 — admin 가드
      # 전제). GET /admin/tickets/:ticket_id/messages/:message_id/image
      get "messages/:message_id/image" => "tickets#image", as: :message_image
    end
  end

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
    # VIEW-7 — 수신 거부 접수 완료 화면(kind=refusal 접수의 PRG GET — promise_thanks와 톤이 달라
    # 별도 최소 안내로 분리한다. 접수 POST는 위 promises 경로를 재사용한다).
    get "/:token/refusal_thanks", to: "viewer#refusal_thanks", as: :viewer_refusal_thanks
  end

  # ── 표면 ① 공개 정적 페이지 — 법적 고지(PG 심사 요건) ──────────
  # 랜딩과 동일 공개 크롬(landing 레이아웃), 비인증(SURF-1). NOINDEX_PATH_PREFIXES 미포함 — 색인 허용(SURF-3).
  get "/terms" => "pages#terms", as: :terms
  get "/refund" => "pages#refund", as: :refund
  get "/privacy" => "pages#privacy", as: :privacy

  # ── 표면 ① 랜딩 ───────────────────────────────
  # 비로그인 공개(SURF-1) — 색인 허용(SURF-3), ①→② 진입은 가입 CTA 단일(SURF-4)
  root "landing#index"
end

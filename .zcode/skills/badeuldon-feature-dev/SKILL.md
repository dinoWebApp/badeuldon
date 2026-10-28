---
name: badeuldon-feature-dev
description: 받을돈 기능 개발 가이드 스킬. Rails 8.1 + ERB + Hotwire + Tailwind 스택의 레이어별 구현 순서, 코드 템플릿, 응답 전략(303/422/Turbo Stream), 네이밍, 품질 게이트 명령어를 제공한다. 받을돈 기능을 구현할 때 따른다.
---

# 받을돈 기능 개발 가이드 (Rails 8.1)

## 이 스킬의 목적

ARCHITECTURE_CONVENTION.md(v1.0.0)을 구현 관점으로 요약한 단계별 가이드. 구현 시작 전 해당 도메인의 Rule ID를 PRD에서 확인하고, 아래 레이어 순서·템플릿을 따른다. 상세 규칙은 ARCHITECTURE_CONVENTION.md가 단일 소스다.

## 구현 순서 (레이어 파이프라인)

```
1. 마이그레이션 (db/migrate/) — 컬럼·인덱스·enum 기반 설계
2. Model (app/models/) — 검증·연관·enum·scope·간단한 도메인 메서드
3. Form/Service/Query (필요 시만) — 도입 기준 아래 참조
4. Controller (app/controllers/) — 얇게, before_action + params.expect
5. View (app/views/) — ERB + 파셜, Turbo Frame/Stream
6. Routes (config/routes.rb) — resources + 표면별 블록
7. Job (app/jobs/) — 지연·발송 등 비동기 (필요 시)
8. 테스트 — badeuldon-test-patterns 스킬 참조
```

**도입 기준**: Service는 ① 2개+ 모델 쓰기 ② 트랜잭션 ③ 외부 API(핵클·토스페이먼츠) 중 하나라도 해당될 때. Query Object는 조인 2개+·동적 조합. Form Object는 모델 없는 복잡 입력만. 그 외는 모델 검증 + 얇은 컨트롤러로 충분하다(과도한 추상화 금지).

## 표면별 라우트 골격

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # ── 표면 ① 랜딩 ──
  root "landing#index"

  # ── 표면 ② 대시보드 (로그인 U1) ──
  namespace :app do
    resources :invoices, shallow: true do
      member { patch :void }      # 무효 처리(INV-6) 등 상태 전환만 member로
    end
    resources :clients
  end

  # ── 표면 ③ 청구서 뷰어 (비로그인 U2, /b/:token) ──
  scope "/b" do
    get "/:token", to: "viewer#show", as: :viewer
  end

  # ── 표면 ④ 관리자 ──
  namespace :admin do
    # ADMIN 롤 + 2FA 가드(AUTH-7)
  end
end
```

- `/app`, `/b/*`, `/admin`은 noindex(SURF-3). 뷰어 컨트롤러는 인증 없이 토큰으로만 조회(SHARE-1).
- 경로 헬퍼 사용, URL 하드코딩 금지.

## Model 템플릿

```ruby
class Invoice < ApplicationRecord
  belongs_to :user
  belongs_to :client
  has_many :invoice_items, dependent: :destroy
  has_many :reminders, dependent: :destroy

  # INV-4 상태 전이 — enum으로
  enum :status, { draft: 0, issued: 1, viewed: 2, overdue: 3, promised: 4,
                  partially_paid: 5, paid: 6, voided: 7 }, default: :draft

  validates :issue_number, presence: true, uniqueness: true   # INV-1 자동 채번
  validates :due_on, presence: true

  scope :overdue, -> { issued.where(due_on: ...Date.current) }
  scope :unpaid, -> { where.not(status: [:paid, :voided]) }

  def to_s = issue_number.to_s
end
```

규칙: 연관에 `dependent:` 필수 · 상태는 enum(`?`/`!`/scope 자동) · 콜백 3개 이하(초과 시 Service 승격) · 마이그레이션에 `null: false`·`default`·인덱스 명시.

## Controller 템플릿

```ruby
class App::InvoicesController < ApplicationController
  before_action :require_login                      # 인증은 반드시 before_action
  before_action :set_invoice, only: [:show, :void]

  def create
    @invoice = Current.user.invoices.build(invoice_params)
    if @invoice.save
      redirect_to [:app, @invoice], status: :see_other, notice: "청구서가 저장되었습니다."
    else
      render :new, status: :unprocessable_entity    # Turbo 폼 교체의 전제(422)
    end
  end

  private

  def set_invoice
    @invoice = Current.user.invoices.find(params[:id])   # 소유권 격리 겸용
  end

  def invoice_params
    params.expect(invoice: [:client_id, :due_on, :tax_mode, { items_attributes: [...] }])
  end
end
```

규칙: 액션 본문 10줄 이내 · 조건 분기 3개+면 Service로 · 성공 `303 see_other`/실패 `422` · 액션 본문에 인증 if문 금지.

## Service 템플릿 (외부 API·트랜잭션)

```ruby
module Reminders
  class DispatchService
    class SendWindowViolation < StandardError; end   # REM-3 위반은 코드 레벨에서 차단

    def initialize(invoice:, step:)
      @invoice = invoice
      @step = step
    end

    def call
      raise SendWindowViolation unless KstBusinessHours.sendable_now?

      ActiveRecord::Base.transaction do
        # SEC-5 멱등성: 동일 청구·동일 단계 1회만 발송
        return if @invoice.reminders.sent.exists?(step: @step)
        reminder = @invoice.reminders.create!(step: @step)
        HackleMessage.send(alarmtalk_body(reminder))   # REM-10 핵클 — wrapper 경유
      end
    end
  end
end
```

규칙: 진입점 `#call` 하나 · 생성자는 데이터만(params/Current 금지) · 여러 쓰기는 transaction · 실패는 사용자 정의 예외 · 외부 API는 도메인 wrapper(예: `HackleMessage`)로 감싸 테스트에서 교체 가능하게.

## View / Hotwire 규칙

- 뷰는 @변수·헬퍼·파셜만 — DB 쿼리 호출 금지. 표현 로직 3줄+는 헬퍼로.
- Frame id는 `dom_id(@invoice)` 또는 `명사_복수` 컨벤션. 폼 성공 303/실패 422 상태 코드 규약 준수.
- 생성/삭제 후 목록 갱신은 `create.turbo_stream.erb`(append/remove만). 파괴적 버튼은 `button_to` + `turbo_confirm`.
- Stimulus는 UI 동작 1개만 담당(비즈니스 로직·도메인 상태 금지). 뷰어(③) 계좌 복사 등은 여기 해당.
- 사용자 입력 출력은 `<%= %>` 이스케이프 기본 — `raw`/`html_safe` 금지.
- 표면 ③ 뷰어: 화이트리스트 요소만(VIEW-8), 레이아웃 공유 앱 내비 포함 금지 — 전용 레이아웃 사용.

## Job 규칙 (리마인더·알림은 전부 Job)

```ruby
class ReminderDispatchJob < ApplicationJob
  queue_as :default
  retry_on Timeout::Error, wait: 30.seconds, attempts: 3

  def perform(invoice_id, step)     # 객체가 아니라 id(스칼라)만
    Reminders::DispatchService.new(invoice: Invoice.find(invoice_id), step:).call
  end
end
```

- 웹 응답 1초+ 작업(외부 API 발송·PDF)은 반드시 Job으로 · Job은 멱등(SEC-5) · Job은 Service/Model만 호출.
- 시간 비교는 KST 기준(TIME-1)으로 통일 — `Time.current`(앱 TZ=Seoul) 사용.

## 코딩 규칙 요약

- **들여쓰기: Ruby·JS·HTML·ERB 2칸 space(탭 금지)** — RuboCop(omakase)이 기준
- 네이밍: ARCHITECTURE_CONVENTION §5 (Service=`동사+목적어+Service`, Query=`{목적}Query`, Form=`{목적}Form`, 예외=`{문제}Error`)
- 도메인 간 결합은 공개 진입점만(예: `Notifications.deliver(...)`) — 타 도메인 내부 클래스 직접 호출 금지
- 자동 완성 검증: `bin/rails zeitwerk:check`

## 완료 전 자체 점검 (Developer 체크리스트)

- [ ] 관련 Rule ID 전부 구현에 반영됐는가 (PRD §6 해당 항목 대조)
- [ ] `bin/rubocop` 0 에러
- [ ] `bin/rails zeitwerk:check` 통과
- [ ] 마이그레이션 있으면 `bin/rails db:migrate` 성공 + `db/schema.rb` 갱신
- [ ] 뷰어(③) 변경 시 마케팅 요소·인증 요구 없음(VIEW-8/P3)
- [ ] 발송 로직은 멱등(SEC-5)·발송 창 준수(REM-3)·상한 5통(REM-12)
- [ ] `_workspace/03_implementation.md` 작성 (변경 파일·Rule ID 매핑)

# 구독 플로우(F-PLAN — PLAN-2/5) — 체험 시작·카드 등록(빌링키)·자동 갱신·해지·만료 강등의
# 단일 진입점. 포트원 API는 PortOne::ClientService 경유만 쓰며(외부 API 캡슐화 규약),
# 여러 쓰기(주문+주기 연장)는 트랜잭션으로 묶는다. 생명주기 상태 규칙은 Subscription 모델이
# 소유하고 이 서비스는 흐름·가드·외부 호출을 담당한다.
#
# action — start_trial: 체험 시작(14일 무료·1회) / register_card: 빌링키 발급 후 활성 /
#          cancel: 해지(Plus 이용 중만 — 기간 종료까지 유지) / expire: 만료 강등(Free 복귀) /
#          renew: 자동 갱신(Job — with_lock·선주문 멱등) /
#          settle_renewal: 웹훅 회복(모호 실패 후 실제 성공한 차감의 확정)
module Subscriptions
  class UpgradeService
    class UpgradeError < StandardError; end

    def initialize(user:, action:, issue_token: nil, order: nil, payment: nil,
                   client: PortOne::ClientService.new)
      @user = user
      @action = action.to_sym
      @issue_token = issue_token
      @order = order
      @payment = payment || {}
      @client = client
    end

    def call
      case @action
      when :start_trial then start_trial
      when :register_card then register_card
      when :cancel then cancel
      when :expire then expire
      when :renew then renew
      when :settle_renewal then settle_renewal
      else raise UpgradeError, "알 수 없는 구독 처리입니다: #{@action}"
      end
    end

    private

    # 체험 시작(PLAN-2) — Subscription이 없거나 Free인 사용자만. Plus 이용 중이면 거부한다.
    # 체험 이력(used_trial)이 있으면 1인 1회 가드로 거부한다(이슈 #2 — 무한 재체험 차단).
    def start_trial
      subscription = resolve_subscription
      raise UpgradeError, "이미 Plus를 이용 중입니다" unless subscription.free?

      subscription.start_trial!
    rescue Subscription::TrialAlreadyUsedError
      raise UpgradeError, "무료 체험은 계정당 1회만 이용할 수 있습니다. 카드를 등록해 Plus로 이용해 주세요"
    end

    # 카드 등록·빌링키 발급 — 위젯이 발급한 토큰(billingIssueToken)을 빌링키로 교환해 저장하고
    # 활성 전환한다. Free 사용자가 체험 없이 바로 카드를 등록하면 유료 Plus로 즉시 활성화된다
    # (동일 플로우).
    def register_card
      subscription = resolve_subscription
      raise UpgradeError, "카드 인증 정보(발급 토큰)가 없습니다" if @issue_token.blank?

      subscription.activate!(billing_key: issue_billing_key!(subscription))
    end

    # 해지(PLAN-5) — 이용 중인 Plus(체험 포함)만 해지하며, 이용은 기간 종료까지 유지된다.
    # Free의 해지는 넌센스 상태(free/cancelled)를 만드므로 거부한다(이슈 #6).
    def cancel
      subscription = resolve_subscription
      unless subscription.plus? && (subscription.active? || subscription.trialing?)
        raise UpgradeError, "해지할 이용 중인 Plus 구독이 없습니다"
      end

      subscription.cancel!
    end

    # 체험 종료 강등 — 체험이 끝났는데 카드(빌링키)가 없으면 Free로 복귀한다. 잡 재실행에도
    # 안전하도록 이미 만료된 구독은 무변경(멱등)으로 흡수한다.
    def expire
      subscription = resolve_subscription
      return subscription if subscription.expired?

      subscription.expire!
    end

    # 자동 갱신(잡 전용) — with_lock 하에서 주기 종료를 다시 판정한 뒤 차감한다(이슈 #4 —
    # 병렬 실행 시 1회만 차감). 그 외(해지 후 주기 종료·카드 부재)는 만료 강등한다.
    # 차감 실패 처리는 record_charge_failure!가 담당한다 — 명확한 실패만 즉시 만료하고,
    # 모호 실패(타임아웃)는 pending 유지로 웹훅·재시도 회복을 연다(dunning 미실시 — 마일스톤
    # 확정). trialing·expired는 무변경(멱등)이다.
    def renew
      subscription = resolve_subscription
      @renewal_error = nil
      subscription.with_lock do
        subscription.reload
        if subscription.active? && subscription.pg_billing_key.present?
          charge_and_extend!(subscription) if renewal_due?(subscription)
        elsif subscription.active? || renewal_due?(subscription)
          subscription.expire! # active-카드 부재 또는 해지 후 주기 종료
        end
      end
      raise @renewal_error if @renewal_error
    end

    # 웹훅 회복(이슈 #4) — 모호 실패로 pending인 갱신 주문이 실제로는 차감 성공이었던 경우
    # (웹훅 DONE 재조회 확정). 주문을 paid로 확정하고 주기를 연장한다. 이미 확정됐으면 무변경.
    def settle_renewal
      subscription = resolve_subscription
      order = @order
      raise UpgradeError, "Plus 갱신 주문이 아닙니다" unless order&.plus_monthly?

      order.with_lock do
        order.reload
        next unless order.pending?

        ActiveRecord::Base.transaction do
          order.update!(status: :paid, paid_at: Time.current,
                        pg_payment_id: @payment[:id], metadata: @payment)
          extend_period!(subscription.reload) unless renewal_current?(subscription)
        end
      end
      order
    end

    def resolve_subscription
      @user.subscription || @user.create_subscription!(plan: :free)
    end

    def issue_billing_key!(subscription)
      response = @client.issue_billing_key(
        issue_token: @issue_token, channel_key: portone_channel_key_billing,
        customer_id: subscription.pg_customer_key
      )
      response.fetch(:billingKey)
    rescue PortOne::ApiError => e
      raise UpgradeError, "카드 등록에 실패했습니다 (#{e.message})"
    end

    # 차감·연장 — 잠금 하에서 호출된다. 차감 전 pending 주문을 선기록해 포트원 결제 ID
    # (pg_order_id)를 확정한다(이슈 #4): 차감 성공 후 프로세스 종료·DB 실패로 주기 연장이
    # 누락돼도 재실행은 같은 주문(같은 paymentId)으로 재시도하므로 포트원이 중복 차감을 거부한다.
    def charge_and_extend!(subscription)
      order = prepare_renewal_order!(subscription)
      response = @client.charge_billing_key(
        payment_id: order.pg_order_id, billing_key: subscription.pg_billing_key,
        channel_key: portone_channel_key_billing, amount: Subscription::PLUS_MONTHLY_PRICE,
        customer_id: subscription.pg_customer_key, order_name: "받을돈 Plus 월 구독"
      )
      ActiveRecord::Base.transaction do
        # 포트원 결제 ID는 우리가 지정한 paymentId(pg_order_id)와 같다.
        order.update!(status: :paid, paid_at: Time.current, pg_payment_id: order.pg_order_id,
                      pg_billing_key: subscription.pg_billing_key, metadata: response)
        extend_period!(subscription)
      end
    rescue PortOne::ApiError => e
      @renewal_error = record_charge_failure!(subscription, order, e)
    end

    # 차감 대상 pending 주문 확보 — 잔존 pending 주문(선기록 후 실패한 시도)이 있으면 재사용해
    # 같은 결제 ID로 재시도하고, 없으면 새로 만든다.
    def prepare_renewal_order!(subscription)
      subscription.user.orders.where(product: :plus_monthly, status: :pending)
                  .order(:created_at).first ||
        subscription.user.orders.create!(product: :plus_monthly,
                                         amount: Subscription::PLUS_MONTHLY_PRICE,
                                         pg_order_id: SecureRandom.uuid)
    end

    # 정기결제 채널 키 — 빌링키 발급·차감을 INIBillTst(정기결제 테스트 채널)로 라우팅한다.
    def portone_channel_key_billing
      Rails.application.credentials.dig(:portone, :channel_key_billing)
    end

    def renewal_due?(subscription)
      subscription.current_period_end.present? && subscription.current_period_end <= Time.current
    end

    def renewal_current?(subscription)
      subscription.current_period_end.present? && subscription.current_period_end > Time.current
    end

    # 주기 연장 — 현재 주기 종료일(없으면 지금)을 시작으로 1개월 연장한다.
    def extend_period!(subscription)
      base = subscription.current_period_end || Time.current
      subscription.update!(current_period_start: base,
                           current_period_end: base + Subscription::PERIOD_MONTHS.months)
    end

    # 차감 실패 처리(이슈 #4) — 모호 실패(TIMEOUT/CONNECTION)는 차감이 실제로는 성공했을 수
    # 있으므로 구독을 유지하고 pending 주문으로 회복을 기다린다(웹훅 Transaction.Paid →
    # settle_renewal, 또는 익일 잡이 같은 결제 ID로 재시도). 같은 주문의 재시도 거절은
    # "이미 결제됨"일 수 있어 (모호 실패 이력 있음) 만료하지 않는다. 명확한 실패만 실패 주문 +
    # 즉시 만료를 한 트랜잭션으로 수행해 "실패 주문만 남고 구독은 이용 중"인 상태가 없게 한다.
    def record_charge_failure!(subscription, order, error)
      metadata = order.metadata.to_h
      if error.ambiguous? || metadata["ambiguous"].present?
        order.update!(metadata: metadata.merge("ambiguous" => true,
                                               "last_code" => error.code,
                                               "last_message" => error.message))
        return UpgradeError.new(
          "자동 결제 확인이 지연되고 있습니다. 확정 전까지 구독이 유지됩니다 (#{error.message})"
        )
      end

      ActiveRecord::Base.transaction do
        order.update!(status: :failed,
                      metadata: { code: error.code, message: error.message,
                                  pg_code: error.pg_code, pg_message: error.pg_message })
        subscription.expire!
      end
      UpgradeError.new("자동 결제에 실패했습니다 (#{error.message}). 구독이 만료되어 Free로 전환됩니다")
    end
  end
end

# 구독 플로우(F-PLAN — PLAN-2/5) — 체험 시작·카드 등록(빌링키)·자동 갱신·해지·만료 강등의
# 단일 진입점. 포트원 API는 PortOne::ClientService 경유만 쓰며(외부 API 캡슐화 규약),
# 여러 쓰기(주문+주기 연장)는 트랜잭션으로 묶는다. 생명주기 상태 규칙은 Subscription 모델이
# 소유하고 이 서비스는 흐름·가드·외부 호출을 담당한다.
#
# action — start_trial: 체험 시작(14일 무료·1회) / register_card: 빌링키 발급 후 활성 /
#          cancel: 해지(Plus 이용 중만 — 기간 종료까지 유지) / expire: 만료 강등(Free 복귀) /
#          renew: 자동 갱신(Job — with_lock·선주문 멱등) /
#          retry_charge: dunning 재차감(PLAN-5 — D+1·D+3·D+7, Job 전용) /
#          settle_renewal: 웹훅 회복(모호 실패 후 실제 성공한 차감의 확정)
module Subscriptions
  class UpgradeService
    class UpgradeError < StandardError; end

    def initialize(user:, action:, issue_token: nil, order: nil, payment: nil,
                   channel_key: nil, client: PortOne::ClientService.new)
      @user = user
      @action = action.to_sym
      @issue_token = issue_token
      @order = order
      @payment = payment || {}
      @channel_key = channel_key
      @client = client
    end

    def call
      case @action
      when :start_trial then start_trial
      when :register_card then register_card
      when :cancel then cancel
      when :expire then expire
      when :renew then renew
      when :retry_charge then retry_charge
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
    # 차감 실패 처리는 record_charge_failure!가 담당한다 — 명확한 실패는 dunning 스케줄에
    # 진입해 D+1·D+3·D+7 재차감으로 이어지고(PLAN-5 2026-11-16 확정), 모호 실패(타임아웃)는
    # pending 유지로 웹훅·재시도 회복을 연다. dunning 진행 중인 구독은 재시도 Job 전용이므로
    # 여기서 차감하지 않는다(갱신 Job과 재시도 Job의 경합 방지). trialing·expired는 무변경.
    def renew
      subscription = resolve_subscription
      @renewal_error = nil
      subscription.with_lock do
        subscription.reload
        if subscription.dunning_active?
          # dunning 진행 중 — 재차감은 Subscriptions::DunningRetryJob이 담당한다(무변경).
        elsif subscription.active? && subscription.pg_billing_key.present?
          charge_and_extend!(subscription) if renewal_due?(subscription)
        elsif subscription.active? || renewal_due?(subscription)
          subscription.expire! # active-카드 부재 또는 해지 후 주기 종료
        end
      end
      raise @renewal_error if @renewal_error
    end

    # dunning 재차감(PLAN-5 — 잡 전용) — 스케줄 시각(next_retry_at)이 된 구독을 동일 빌링키로
    # 다시 차감한다. 차감 경로는 갱신과 동일한 charge_and_extend!를 재사용한다(새 API 호출
    # 코드 없음). 성공 시 extend_period!가 dunning을 초기화한다. 실패 시
    # record_charge_failure!가 다음 단계를 스케줄하거나(3회 미만) cancelled로 전환한다(3회).
    # next_retry_at이 아직 미래면(스케줄 이동) Job을 미래 시각으로 다시 걸고 종료한다(멱등).
    def retry_charge
      subscription = resolve_subscription
      @renewal_error = nil
      subscription.with_lock do
        subscription.reload
        if subscription.dunning_active? && subscription.next_retry_at.present? &&
           subscription.next_retry_at > Time.current
          Subscriptions::DunningRetryJob
            .set(wait: (subscription.next_retry_at - Time.current).seconds)
            .perform_later(subscription.id)
        elsif subscription.dunning_active? && subscription.pg_billing_key.present?
          charge_and_extend!(subscription)
        end
        # dunning 비대상(성공으로 초기화됨·취소됨·카드 부재)은 무변경 — 멱등 no-op.
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
          # C-2(Q12) — 웹훅 회복도 "결제 성공 시점"이다: 첫 차감 할인 건(예약 쿠폰 존재)이면
          # 성공 경로와 동일하게 consume_first_charge_coupon!로 used_count 증가·예약 해제를
          # 정산하고, metadata는 @payment에 coupon 기록을 병합(덮어쓰기 아님 — P4).
          coupon = subscription.coupon
          metadata = coupon_metadata(@payment, coupon)
          order.update!(status: :paid, paid_at: Time.current,
                        pg_payment_id: @payment[:id], metadata: metadata)
          consume_first_charge_coupon!(subscription, coupon) if coupon
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
    #
    # ADMIN-4 쿠폰(Q12) — 구독에 쿠폰이 예약돼 있고 성공한 Plus 결제가 아직 없으면 이 차감이
    # "첫 결제"로 할인가로 진행된다. used_count 증가·쿠폰 예약 해제는 차감 성공 트랜잭션에서만
    # 수행되므로(SEC-5) 차감 실패 시 소비되지 않고, 이후 재과금은 항상 정상가다.
    def charge_and_extend!(subscription)
      coupon = resolve_first_charge_coupon!(subscription)
      charge_amount = coupon ? coupon.final_price_for(Subscription::PLUS_MONTHLY_PRICE)
                             : Subscription::PLUS_MONTHLY_PRICE
      order = prepare_renewal_order!(subscription, charge_amount)
      response = @client.charge_billing_key(
        payment_id: order.pg_order_id, billing_key: subscription.pg_billing_key,
        channel_key: portone_channel_key_billing, amount: charge_amount,
        customer_id: subscription.pg_customer_key, order_name: "받을돈 Plus 월 구독"
      )
      ActiveRecord::Base.transaction do
        # 포트원 결제 ID는 우리가 지정한 paymentId(pg_order_id)와 같다.
        order.update!(status: :paid, paid_at: Time.current, pg_payment_id: order.pg_order_id,
                      pg_billing_key: subscription.pg_billing_key,
                      metadata: coupon_metadata(response, coupon))
        extend_period!(subscription)
        consume_first_charge_coupon!(subscription, coupon) if coupon
      end
    rescue PortOne::ApiError => e
      @renewal_error = record_charge_failure!(subscription, order, e)
    end

    # 첫 차감 쿠폰 확정 — 예약 쿠폰이 없으면 nil(정상가). 있으면 적용 자격을 재검증한다:
    # ① 쿠폰이 유효하지 않게 됐으면(만료·한도·비활성·0원) 결제를 중단한다(정가 폴백 금지 —
    #   사용자가 안 내받은 금액을 차감하는 금액 불일치 방지).
    # ② 이미 성공한 Plus 결제가 있으면(방어 — 정상 경로에서는 발생 없음) 예약을 해제하고
    #   정상가로 진행해 중복 할인을 원천 차단한다("적용 1회").
    def resolve_first_charge_coupon!(subscription)
      coupon = subscription.coupon
      return nil if coupon.nil?
      if subscription.user.orders.paid.plus_monthly.exists?
        subscription.update!(coupon_id: nil)
        return nil
      end
      raise UpgradeError, "쿠폰(#{coupon.code})을 사용할 수 없습니다 — #{coupon.unavailability_reason}. 결제가 중단되었습니다" unless coupon.redeemable?

      coupon
    end

    # 쿠폰 소비 — used_count 1회 증가(원자 연산·SEC-5·한도 가드 W-1) + 구독 예약 해제를
    # 같은 트랜잭션에서. 가드 미적용(경합으로 잔여 소진)이면 예외로 결제를 중단한다.
    # 이후 모든 차감은 정가다(재과금 할인 없음 — Q12).
    def consume_first_charge_coupon!(subscription, coupon)
      raise UpgradeError, "쿠폰(#{coupon.code}) 한도가 소진되었습니다. 결제가 중단되었습니다" unless coupon.consume!

      subscription.update!(coupon_id: nil)
    end

    # 주문 metadata — 포트원 응답 원문(P4) + 쿠폰 적용 사실. ADMIN-4 매출 집계·CS 추적 근거.
    def coupon_metadata(response, coupon)
      return response if coupon.nil?

      response.to_h.merge(
        "coupon" => { "code" => coupon.code, "discount_type" => coupon.discount_type,
                      "discount_value" => coupon.discount_value }
      )
    end

    # 차감 대상 pending 주문 확보 — 잔존 pending 주문(선기록 후 실패한 시도)이 있으면 재사용해
    # 같은 결제 ID로 재시도하고, 없으면 새로 만든다. 재사용 시 금액을 이번 차감 금액으로
    # 맞춘다(쿠폰 할인 반영·정가 잔존 주문과의 불일치 방지).
    def prepare_renewal_order!(subscription, amount)
      order = subscription.user.orders.where(product: :plus_monthly, status: :pending)
                           .order(:created_at).first
      if order
        order.update!(amount: amount) unless order.amount == amount
        order
      else
        subscription.user.orders.create!(product: :plus_monthly, amount:,
                                         pg_order_id: SecureRandom.uuid)
      end
    end

    # 정기결제 채널 키 — 빌링키 발급·차감에 쓴다. 주입값 우선(테스트 밀봉), 없으면 환경
    # 선택기(PLAN-5 — 운영은 라이브 채널 키, 그 외 환경은 테스트 채널 키).
    def portone_channel_key_billing
      @channel_key || PortOne::ChannelKey.billing
    end

    def renewal_due?(subscription)
      subscription.current_period_end.present? && subscription.current_period_end <= Time.current
    end

    def renewal_current?(subscription)
      subscription.current_period_end.present? && subscription.current_period_end > Time.current
    end

    # 주기 연장 — 현재 주기 종료일(없으면 지금)을 시작으로 1개월 연장한다. 차감 성공 시점이므로
    # dunning 진행 상태도 함께 초기화한다(PLAN-5 — 재시도 중 회복).
    def extend_period!(subscription)
      base = subscription.current_period_end || Time.current
      subscription.update!(current_period_start: base,
                           current_period_end: base + Subscription::PERIOD_MONTHS.months)
      subscription.reset_dunning!
    end

    # 차감 실패 처리(이슈 #4) — 모호 실패(TIMEOUT/CONNECTION)는 차감이 실제로는 성공했을 수
    # 있으므로 구독을 유지하고 pending 주문으로 회복을 기다린다(웹훅 Transaction.Paid →
    # settle_renewal, 또는 익일 잡이 같은 결제 ID로 재시도). 같은 주문의 재시도 거절은
    # "이미 결제됨"일 수 있어 (모호 실패 이력 있음) 만료하지 않는다.
    #
    # 명확한 실패(PLAN-5 dunning — 2026-11-16 확정)는 실패 주문 기록과 함께 재시도 스케줄에
    # 진입한다: 3회 미만이면 dunning_stage를 1 진행하고 DUNNING_RETRY_DELAYS만큼 뒤
    # (D+1·D+3·D+7) 재차감 Job을 예약한다. 3회 모두 실패하면 구독을 cancelled로 전환한다
    # (기간 말 만료 — 해지 정책과 동일. 주기가 이미 종료됐으므로 갱신 Job의 해지 경로가
    # 다음 스윕에서 expire!로 강등한다). "실패 주문만 남고 구독 상태가 반영되지 않는" 상태는
    # 없게 한다. 최종 실패 시점의 실패 주문은 paid가 아니므로 ADMIN-5 매출 집계에 자동 제외다.
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
        advance_dunning!(subscription)
      end
      UpgradeError.new("자동 결제에 실패했습니다 (#{error.message}). #{dunning_message(subscription)}")
    end

    # dunning 단계 진행 — 실패 1회마다 stage +1. 최종(3회) 실패 시 cancelled(기간 말 만료).
    def advance_dunning!(subscription)
      stage = subscription.dunning_stage + 1
      if stage > Subscription::DUNNING_MAX_STAGE
        subscription.update!(dunning_stage: Subscription::DUNNING_MAX_STAGE,
                             next_retry_at: nil, last_payment_failed_at: Time.current)
        subscription.cancel!
        nil
      else
        delay = Subscription::DUNNING_RETRY_DELAYS[stage - 1]
        subscription.update!(dunning_stage: stage, next_retry_at: delay.days.from_now,
                             last_payment_failed_at: Time.current)
        Subscriptions::DunningRetryJob.set(wait: delay.days).perform_later(subscription.id)
        nil
      end
    end

    def dunning_message(subscription)
      if subscription.cancelled?
        "재시도 #{Subscription::DUNNING_MAX_STAGE}회를 모두 실패해 구독이 해지되었습니다"
      else
        "#{subscription.next_retry_at.strftime('%m-%d %H:%M')}에 1회 재시도됩니다 " \
          "(재시도 #{subscription.dunning_stage}/#{Subscription::DUNNING_MAX_STAGE})"
      end
    end
  end
end

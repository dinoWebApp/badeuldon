# 관리자 환불 실행(PLAN-9·ADMIN-11 — 결정 기록 Q27). 포트원 결제 취소(전액·즉시 한정 —
# 부분 취소·예약 취소 없음)와 결제 상품별 되돌리기를 한 절차로 수행한다. 기존 mark_refunded!
# 기록 전용 경로(ADMIN-4)를 대체하며, 포트원 콘솔에서 먼저 환불된 건도 같은 버튼으로 정산을
# 완료한다(재동기화).
#
# 확정 절차(01_plan §1 + 리뷰 C-2 반영):
#   ① 사전 가드 — 하나라도 걸리면 로컬 변경·PG 호출·감사 기록 없이 실패 Result(PG 호출이
#      없는 시도라 감사 기록 대상이 아니다).
#   ② 시도 감사(별도 트랜잭션) — PG 취소 호출 직전에 기록한다(action "order_refund_attempt"
#      — ADMIN-2). 기록에 실패하면 PG 호출을 하지 않고 중단한다(기록 없는 취소 금지).
#   ③ PG 취소(트랜잭션 밖) — 오류는 흡수하고 ④으로 진행한다(이미 전액 취소된 결제일 수 있다:
#      포트원 콘솔 선(先)환불·응답 유실 — 흡수한 오류 코드는 실패 메시지에 보존한다(W-4a)).
#      이 시점부터는 ④의 판정 결과와 무관하게 PG에서 환불이 실행됐을 수 있다 — 정산이 안
#      끝난 모든 경로에 실패 감사(action "order_refund_failed")를 남긴다(C-2).
#   ④ PG 재조회로 확정 — 취소 응답 본문은 신뢰하지 않고 재조회 결과만 신뢰한다(웹훅과 같은
#      무결성 원칙). 결제 완료 사실 + 전액 취소를 모두 확인하며, 하나라도 확인하지 못하면
#      실패(fail-closed — 로컬 무변경. 단 PG 환불 부재까지는 보장하지 않는다 — ③ 참조·C-2
#      감사로 추적한다).
#   ⑤ 로컬 확정 트랜잭션 — order.with_lock 후 가드를 다시 검사해 통과한 쪽만 한 번 실행
#      (이중 제출·경합 방지). 주문 기록 → 상품 되돌리기 → 감사 로그를 한 트랜잭션에 둔다.
#      PG 취소 후 로컬 확정이 실패·롤백되면 주문은 실행 전 상태(paid 등)로 미정산 채 남는다
#      (W-8 정정 — 이전 주석의 "주문은 cancelled로 남는다"는 롤백 경로와 맞지 않는 서술이었다.
#      웹훅이 cancelled로 도착한 뒤 콘솔의 재실행 버튼(재검사 통과)으로 정산이 회복된다).
module Orders
  class RefundService
    Result = Struct.new(:success, :errors, :message, keyword_init: true) do
      def success? = success
    end

    # 포트원 공식 결제 상태 enum(공식 OpenAPI v2 확정 — 2026-11-24 리뷰 §5): READY·PENDING·
    # VIRTUAL_ACCOUNT_ISSUED·PAID·FAILED·PARTIAL_CANCELLED·CANCELLED. 전액 취소는 CANCELLED뿐이고
    # CONSOLE_CANCELLED는 스펙에 없다(콘솔 취소도 상태는 CANCELLED — 이전 후보 제거·웹훅 컨트롤러
    # 상수는 이번 변경 대상이 아니다). PARTIAL_CANCELLED(부분 취소)는 전액이 아니므로 명시적으로
    # 실패 처리한다.
    FULL_CANCELLED_STATUSES = %w[CANCELLED].freeze

    # ip(ADMIN-2·Q32) — 컨트롤러가 ClientIp.of(request)로 넘긴 요청자 IP. 시도(attempt)·
    # 실패(failed)·완료(refund) 감사 3종에 그대로 전달되며, 인자 없는 호출(runner·기존
    # 테스트)은 nil로 기록된다.
    def initialize(admin:, order:, reason:, client: PortOne::ClientService.new, ip: nil)
      @admin = admin
      @order = order
      @reason = reason.to_s.strip
      @client = client
      @ip = ip
    end

    def call
      return failure(precheck_error) if precheck_error

      # ② 시도 감사 — 기록 실패 시 PG 호출 없이 중단한다(기록 없는 취소 금지 — C-2).
      unless record_attempt_audit!
        return failure("환불 시도 기록(감사 로그)에 실패해 실행을 중단했습니다. 잠시 후 다시 시도해 주세요.")
      end

      confirmation_error = confirm_cancellation!
      return fail_with_audit(confirmation_error) if confirmation_error

      finalize!
    end

    private

    # ── ① 사전 가드 — 실패 시 로컬 변경·PG 호출·감사 기록 없음 ────────────────────

    def precheck_error
      return "환불 사유는 필수입니다." if @reason.blank?
      return "이미 환불 처리된 주문입니다." if @order.refunded?
      return "결제 완료·취소 상태의 주문만 환불할 수 있습니다(현재: #{order_status_label})." unless @order.paid? || @order.cancelled?
      return "결제가 완료된 적이 없는 주문은 환불할 수 없습니다(가상계좌 말소 등)." if @order.paid_at.nil?
      return "포트원 결제 ID가 없어 취소를 실행할 수 없습니다." if @order.pg_order_id.blank?

      nil
    end

    def order_status_label
      @order.status.humanize
    end

    # ── ② 시도 감사(C-2 — ADMIN-2) ─────────────────────────────────────────────

    # PG 취소 호출 직전의 시도를 별도 트랜잭션으로 기록한다 — 확정이 실패해도 "돈이
    # 움직였을 수 있는 시도"가 감사 로그에 남는다. false 반환 시 호출부가 PG 호출 없이 중단.
    def record_attempt_audit!
      ActiveRecord::Base.transaction do
        AuditLogs::RecordService.call(admin: @admin, action: "order_refund_attempt",
                                      target: @order, detail: "PG 취소 요청 직전 — 사유: #{@reason}", ip: @ip)
      end
      true
    rescue StandardError => e
      Rails.logger.error("[Orders::RefundService] 환불 시도 감사 기록 실패 #{e.class}: #{e.message}")
      false
    end

    # ── ③ PG 취소 + ④ 재조회 확정 ──────────────────────────────────────────────

    # 취소 요청의 오류는 흡수한다 — 이미 전액 취소된 결제(콘솔 선취소·응답 유실)는 재조회로
    # 수렴시키는 재동기화 경로다(01_plan §3). ApiError 이외의 예외(SSL·응답 파싱 오류 등)도
    # 요청이 도달했을 수 있으므로 같은 취급으로 재조회에 진행한다(W-1). 흡수한 오류 코드는
    # 실패 메시지에 보존한다(W-4a).
    def confirm_cancellation!
      cancel_error = nil
      cancel_result = nil
      begin
        cancel_result = @client.cancel_payment(payment_id: @order.pg_order_id, reason: @reason)
      rescue StandardError => e
        cancel_error = e
      end

      begin
        payment = @client.get_payment(payment_id: @order.pg_order_id)
      rescue PortOne::ApiError => e
        Rails.logger.error("[Orders::RefundService] PG 재조회 실패 #{e.class}: #{e.code} #{e.message}")
        return cancel_failure_message("포트원 API 오류로 취소를 확정하지 못했습니다(#{e.code}: #{e.message}). 로컬 변경 없이 실패했습니다.", cancel_error)
      rescue StandardError => e
        Rails.logger.error("[Orders::RefundService] PG 재조회 실패 #{e.class}: #{e.message}")
        return cancel_failure_message("포트원 재조회 중 오류로 취소를 확정하지 못했습니다. 로컬 변경 없이 실패했습니다.", cancel_error)
      end

      ensure_full_cancellation(payment, cancel_error, cancel_result)
    end

    # 전액 환불 확정 판정 — ① 재조회 응답이 이 주문의 결제(payment.id 일치 — 웹훅과 같은
    # 무결성 확인, W-3) ② 결제 완료 사실(amount.paid — 필수 필드) ③ 전액 취소(상태 CANCELLED
    # 또는 취소 합계)를 모두 만족해야 한다.
    #
    # 응답 필드 해석(공식 OpenAPI v2 확정 — 2026-11-24 리뷰 §5 대조):
    #   - :status·:id — 실측(웹훅·PurchaseService가 이미 이 키로 읽는다).
    #   - amount.paid·amount.cancelled — 공식 PaymentAmount required("실제 결제금액"·"총 취소금액").
    #     cancellations[].totalAmount — 공식 required("취소 금액"; 이전 후보 키
    #     cancellationAmount·amount는 스펙에 없다 — 제거).
    #   - [INFERENCE] 전액 취소 뒤에도 amount.paid가 결제 금액으로 유지되는지(같은 PaymentAmount
    #     타입이라 유지 추정)·카드 취소가 동기(SUCCEEDED)로 끝나는지 — 첫 실환불 1건으로 확인 필요.
    def ensure_full_cancellation(payment, cancel_error, cancel_result)
      status = payment[:status].to_s
      unless payment[:id] == @order.pg_order_id
        return cancel_failure_message("재조회 응답이 이 주문의 결제가 아닙니다(결제 ID 불일치). 로컬 변경 없이 실패했습니다.", cancel_error)
      end
      if status == "PARTIAL_CANCELLED"
        return cancel_failure_message("부분 취소된 결제입니다(PARTIAL_CANCELLED) — 포트원 콘솔에서 나머지를 환불한 뒤 다시 실행해 주세요. 로컬 변경 없이 실패했습니다.", cancel_error)
      end
      unless payment_paid_fact?(payment)
        return cancel_failure_message("재조회에서 결제 완료 사실(결제 금액)을 확인할 수 없습니다(상태: #{status.presence || "알 수 없음"}). 로컬 변경 없이 실패했습니다.", cancel_error)
      end
      unless fully_cancelled?(payment, status)
        return cancel_failure_message(not_cancelled_message(status, cancel_result, payment), cancel_error)
      end

      nil
    end

    # W-4b — 비동기 취소(REQUESTED) 진행 중이면 재실행이 재조회로 수렴한다는 안내로 대체한다.
    def not_cancelled_message(status, cancel_result, payment)
      return "취소가 비동기로 진행 중입니다. 잠시 후 다시 실행해 주세요." if async_pending?(cancel_result, payment)

      "전액 취소를 확인할 수 없습니다(상태: #{status.presence || "알 수 없음"}). 로컬 변경 없이 실패했습니다."
    end

    # ① 결제 완료 사실 — 결제 금액(amount.paid — 공식 확정 필수 필드)이 주문 금액 이상.
    #    없으면 확인 불가로 실패한다(W-3 — amount.total 폴백 제거: 폴백이 "결제 완료 사실"을
    #    대신해 미결제 응답을 통과시키는 우회를 막는다).
    def payment_paid_fact?(payment)
      paid = payment.dig(:amount, :paid)
      return false if paid.nil?

      paid.to_i >= @order.amount
    end

    # ② 전액 취소 — 상태가 CANCELLED이거나 취소 합계(amount.cancelled → cancellations[] 합계)가
    #    주문 금액 이상. 취소 내역 합계는 status가 SUCCEEDED인 항목의 totalAmount만 더한다
    #    (REQUESTED·FAILED 항목은 아직 확정된 취소가 아니다 — W-2).
    def fully_cancelled?(payment, status)
      return true if FULL_CANCELLED_STATUSES.include?(status)

      cancelled = payment.dig(:amount, :cancelled)
      cancelled = cancellations_total(payment) if cancelled.nil?
      !cancelled.nil? && cancelled.to_i >= @order.amount
    end

    def cancellations_total(payment)
      list = payment[:cancellations]
      return nil unless list.is_a?(Array)

      list.select { |entry| entry[:status] == "SUCCEEDED" }
          .sum { |entry| entry[:totalAmount].to_i }
    end

    # W-4b — 취소 응답 본문(신뢰하지 않지만 참고용)이 비동기 취소(REQUESTED)를 알리고 재조회에도
    # 아직 전액 취소가 아닌 경우. 재실행은 재조회로 수렴한다.
    def async_pending?(cancel_result, payment)
      return false unless cancel_result.is_a?(Hash)
      return false if fully_cancelled?(payment, payment[:status].to_s)

      cancel_result.dig(:cancellation, :status) == "REQUESTED"
    end

    # W-4a — 흡수한 취소 요청 오류(ApiError는 코드, 그 외 예외는 클래스명)를 실패 메시지 앞에
    # 덧붙여 PG 거절 사유가 사라지지 않게 한다.
    def cancel_failure_message(base_message, cancel_error)
      return base_message unless cancel_error

      "포트원 취소 요청 오류: #{cancel_error_identifier(cancel_error)} — #{base_message}"
    end

    def cancel_error_identifier(cancel_error)
      return cancel_error.class.name unless cancel_error.is_a?(PortOne::ApiError)

      cancel_error.code.presence || "UNKNOWN"
    end

    # ── ⑤ 로컬 확정 트랜잭션 ─────────────────────────────────────────────────────

    def finalize!
      summary = nil
      ActiveRecord::Base.transaction do
        @order.with_lock do
          @order.reload
          # 잠금 후 재검사 — 이중 제출·경합에서 이긴 요청만 한 번 실행한다. PG 취소는 이미
          # 실행됐으므로(이미 취소된 결제는 PG가 거부) 정산이 안 끝난 경로는 전부 실패 감사를
          # 남긴다(C-2).
          return fail_with_audit("이미 환불 처리된 주문입니다.") if @order.refunded?
          return fail_with_audit("환불 실행 조건이 변경되어 실패했습니다. 새로고침 후 다시 시도해 주세요.") unless refundable_state?

          apply_refund!
          summary = revert_product!
          record_audit!(summary)
        end
      end
      success_result(summary)
    rescue ActiveRecord::ActiveRecordError => e
      # PG 취소는 이미 실행됐고 로컬만 미정산 상태다 — 웹훅 도착 뒤 콘솔 재실행 버튼으로
      # 회복된다(01_plan §3). 트랜잭션 롤백 뒤에 별도 기록한다(감사가 롤백에 묻히지 않게 — C-2).
      # StatementInvalid(SQLite BUSY·타임아웃)·RecordInvalid 등 포함(W-1 — 500 금지).
      Rails.logger.error("[Orders::RefundService] 로컬 확정 실패 #{e.class}: #{e.message}")
      fail_with_audit("환불 기록 중 오류(#{e.class})가 발생했습니다. PG 취소 상태를 확인한 뒤 다시 실행해 주세요.")
    rescue StandardError => e
      Rails.logger.error("[Orders::RefundService] 로컬 확정 실패(예기치 않은 오류) #{e.class}: #{e.message}")
      fail_with_audit("환불 기록 중 예기치 않은 오류가 발생했습니다. PG 취소 상태를 확인한 뒤 다시 실행해 주세요.")
    end

    # C-2 — PG 취소 뒤 정산이 되지 않고 끝난 경로의 실패 감사(로컬 트랜잭션 밖·롤백 뒤 별도
    # 기록). 감사 기록 자체가 실패해도 실패 Result는 유지한다(상태는 미정산으로 남는다).
    def fail_with_audit(message)
      AuditLogs::RecordService.call(admin: @admin, action: "order_refund_failed",
                                    target: @order, detail: "#{@reason} — 정산 미완료: #{message}", ip: @ip)
      failure(message)
    rescue StandardError => e
      Rails.logger.error("[Orders::RefundService] 환불 실패 감사 기록 실패 #{e.class}: #{e.message}")
      failure(message)
    end

    # 잠금 후 재검사 — 사유·pg_order_id는 변하지 않으므로 상태 조건만 재판정한다.
    def refundable_state?
      !@order.refunded? && (@order.paid? || @order.cancelled?) && @order.paid_at.present?
    end

    def apply_refund!
      # mark_refunded!는 refunded_at·refund_reason만 설정 — status는 환불 실행이
      # 콘솔 수동 환불 때 웹훅이 하던 것과 같은 결과(cancelled)로 수렴시킨다(웹훅 도착
      # 순서와 무관하게 같은 상태). metadata는 B-1 병합 선례로 기존 키를 보존한다.
      @order.mark_refunded!(@reason)
      @order.update!(status: :cancelled, metadata: merged_metadata)
    end

    def merged_metadata
      (@order.metadata || {}).stringify_keys.merge(
        "refund" => {
          "executed_by" => @admin.email,
          "executed_at" => Time.current.iso8601,
          "amount" => @order.amount,
          "reason" => @reason
        }
      )
    end

    # 상품별 되돌리기(Q27) — Plus 주문은 구독 즉시 Free(+빌링키 복사본 정리), 수금 패스
    # 주문은 구매 수량 차감, 내용증명·세금계산서는 되돌리지 않는다(이미 생성·발행된 것은
    # 건드리지 않는다 — 세금계산서 취소 요청 없음). 반환은 실행 요약 문자열(감사·flash).
    def revert_product!
      if @order.plus_monthly?
        expire_subscription!
      elsif @order.collection_pass? && @order.pass?
        revoke_passes!
      else
        "발행물은 그대로 유지(환불 기록만 실행)"
      end
    end

    # 구독 즉시 Free(남은 기간 무관 — 재구독 시 카드 재등록). 자동 갱신·dunning 잡과의
    # 경합을 막기 위해 SubscriptionRenewalJob과 같은 with_lock 방식으로 실행한다.
    # plan이 이미 free면(상태 무관) expire!을 실행하지 않는다(W-6 — 무변경 보고).
    # expire!는 dunning 재시도 상태(dunning_stage·next_retry_at·last_payment_failed_at)를
    # 지우지 않으므로 함께 비운다(C-1 — 잔존 재시도 잡이 재등록한 새 카드로 차감하는 사고
    # 차단. reset_dunning!은 멱등이라 이미 Free여서 expire!을 건너뛴 경우에도 안전).
    # expire!가 비운 구독의 빌링키와 같은 값이 복사돼 있는 그 회원의 주문 행(pg_billing_key —
    # 읽는 곳이 없는 복사본)도 함께 비운다(구독에 빌링키가 남아 있을 때만 — W-6 쿼리 생략).
    def expire_subscription!
      subscription = @order.user.subscription
      return "구독 행이 없어 구독 되돌리기를 건너뜁니다" unless subscription

      already_free = false
      billing_key = nil
      subscription.with_lock do
        subscription.reload
        billing_key = subscription.pg_billing_key
        already_free = subscription.free?
        subscription.expire! unless already_free
        subscription.reset_dunning!
        subscription.update!(last_payment_failed_at: nil) if subscription.last_payment_failed_at?
      end
      if billing_key.present?
        Order.where(user_id: subscription.user_id, pg_billing_key: billing_key)
             .update_all(pg_billing_key: nil) # rubocop:disable Rails/SkipsModelValidations — 복사본 일괄 정리(값이 없는 검증 없음)
      end
      already_free ? "구독은 이미 Free(무변경)" : "구독 즉시 Free 전환"
    end

    # 수금 패스 주문 — 구매 수량(10건)만큼 회원 단위 차감(만료 임박순). 모자라면 0에서 종료.
    def revoke_passes!
      revoked, ignored = PaymentPass.revoke_uses!(user: @order.user, count: PaymentPass::TOTAL_USES)
      ignored.positive? ? "수금 패스 #{revoked}건 차감(미차감 #{ignored}건)" : "수금 패스 #{revoked}건 차감"
    end

    # ADMIN-2 — 기존 action "order_refund"를 그대로 쓴다(기존 감사 로그·화면과 정합).
    def record_audit!(summary)
      AuditLogs::RecordService.call(admin: @admin, action: "order_refund", target: @order, ip: @ip,
                                    detail: "#{@reason} — 환불 금액 #{@order.amount}원 · #{summary}")
    end

    def success_result(summary)
      Result.new(success: true, errors: [],
                 message: "환불을 실행했습니다. 환불 금액 #{@order.amount}원 · #{summary}")
    end

    def failure(message)
      Result.new(success: false, errors: [ message ], message: nil)
    end
  end
end

module Dashboards
  # DASH-2·Q31 — 「약속일 도래」 카드 조회. 미수 청구 중 최신 약속(kind this_week·date_selected —
  # 청구별 created_at·id 가장 뒤 — Reminders::DispatchService#latest_promise와 같은 판정)의
  # 약속일이 오늘인 건. 발송 모집합(reminders_dispatchable)과 무관하게 미수(unsettled)만으로
  # 판정한다 — 보류·수신 거부 청구도 "오늘 입금 약속" 사실 자체는 유효하고, 카드 액션은
  # 마감 확인(PAY — 발송이 아니다)이기 때문. 정렬은 만기일 오름차순.
  class PromisesDueTodayQuery
    Row = Struct.new(:invoice, :promise, keyword_init: true)

    def self.call(user:)
      today = Date.current  # TIME-1 — KST 기준
      scope = user.invoices.unsettled
      invoice_ids = Promise.where(kind: promise_kinds, promised_on: today)
                           .where(invoice_id: scope.select(:id)).pluck(:invoice_id)
      return [] if invoice_ids.empty?

      # 최신 약속 판정 — 후보 청구의 약속 이력 전체를 접수순으로 읽어 청구별 마지막 행을 취한다.
      # 재응답으로 최신 약속일이 내일 이후로 바뀐 건은 오늘 도래에서 제외한다(약속 트랙과 동일 기준).
      latest_by_invoice = Promise.where(kind: promise_kinds, invoice_id: invoice_ids)
                                 .order(:invoice_id, :created_at, :id)
                                 .group_by(&:invoice_id).transform_values(&:last)
      due_invoice_ids = latest_by_invoice.filter_map { |id, promise| id if promise.promised_on == today }

      scope.where(id: due_invoice_ids).includes(:client).sorted_by_due
           .map { |invoice| Row.new(invoice:, promise: latest_by_invoice.fetch(invoice.id)) }
    end

    def self.promise_kinds
      Promise.kinds.slice(:this_week, :date_selected).values
    end
  end
end

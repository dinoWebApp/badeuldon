# ADMIN-4(T-B3) — 환불 사유 기록(PLAN-6 CS 예외 절차). 실제 PG 환불은 포트원 콘솔에서
# 수동 수행(PLAN-5)하며, 이 컬럼들은 그 결과를 서비스 측에 기록(감사·매출 집계 제외)하기 위한 것.
class AddRefundColumnsToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :refunded_at, :datetime
    add_column :orders, :refund_reason, :text
  end
end

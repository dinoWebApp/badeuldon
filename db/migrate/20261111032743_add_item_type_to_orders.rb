# LEGAL-2(Q5) — 내용증명 양식 주문 구분. 기존 orders는 수금 패스·Plus 구독 주문(item_type
# 기본값 0 = pass)이며 데이터 이동 없이 컬럼만 추가한다 — 기존 결제 플로우 무영향.
# [user_id, item_type] 인덱스는 LEGAL 내용증명 목록(App::LegalDocumentsController#index)의
# "사용자별 legal_doc 주문 조회"를 위한 것이다.
class AddItemTypeToOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :orders, :item_type, :integer, default: 0, null: false
    add_index :orders, [ :user_id, :item_type ]
  end
end

# 열람 이벤트(SHARE-3) — 뷰어(③) 진입 기록. 최초/재열람(first)·대략 디바이스·IP·열람 시각을
# 남긴다(P4 — 열람도 기록). invoice FK로 청구서와 묶으며, invoice_id 인덱스가 열람 이력 조회를
# 지원한다. 상태 전이(issued→viewed)는 ViewEvents::TrackService가 담당한다.
class CreateViewEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :view_events do |t|
      t.references :invoice, null: false, foreign_key: true
      # first — 최초 열람 여부(기존 이벤트 0건일 때 true — SHARE-3)
      t.boolean :first, default: false, null: false
      # device — User-Agent 대략 판별(mobile/pc — ViewEvent.device_from_user_agent)
      t.string :device, null: false
      # ip — 열람 IP(알림·분석 근거 기록 — 플랜 결정 #4, 최소 수집). IPv6 최대 길이 45.
      t.string :ip, limit: 45, null: false
      # viewed_at — 열람 시각(KST 고정 — TIME-1)
      t.datetime :viewed_at, null: false

      t.timestamps
    end
  end
end

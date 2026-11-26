# VIEW-7(Q30 — 2026-11-26) — 수신 거부를 거부 시점 번호에 고정한다. refused_phone은 거부
# 접수·전파 시점의 전화번호(하이픈 제외 숫자)를 저장하며 상속·전파 판정의 기준이다 — 행의
# 현재 번호(phone)를 바꿔도 불변이므로 거부된 행이 새 번호의 상속 원천이 되는 문제를 막는다.
# nullable: 거부되지 않은 행은 nil. 인덱스 불요 — 상속·전파는 같은 회원(user_id 인덱스) 안
# 검색이라 기존 인덱스로 충분하다.
class AddRefusedPhoneToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :refused_phone, :string

    # 기존 거부 행 소급 — 거부 시점 번호가 없는 행에 현재 번호를 채운다.
    # 운영 실측 0건(2026-11-26 읽기 전용 조회) — 방어적 소급(로컬·테스트 DB 대비).
    execute <<~SQL
      UPDATE clients
      SET refused_phone = replace(phone, '-', '')
      WHERE refused_at IS NOT NULL AND refused_phone IS NULL
    SQL
  end
end

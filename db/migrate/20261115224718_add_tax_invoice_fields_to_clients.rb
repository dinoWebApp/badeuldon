# TAX-1(2026-11-16) — 공급받는자(거래처) 세금계산서 정보 확장. 상호(name)·담당자(contact_name)·
# 사업자번호(business_number — corp_num 역할, 하이픈 제외 저장은 서비스 계층 책임)·이메일은
# 기존 컬럼을 재사용하고, 세금계산서에 필요한 대표자명·주소만 추가한다(마이그레이션 최소화).
# 개인 거래처(사업자번호 없음)는 TAX-1 발행 비대상이다.
class AddTaxInvoiceFieldsToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :ceo_name, :string
    add_column :clients, :corp_addr, :string
  end
end

# TAX-1(2026-11-16) — 전자세금계산서 발행 설정(users 발행 주체 정보). 바로빌 회원사 가입
# (RegistCorp)에 필요한 사업자 정보와 연동 계정 식별자를 U1에 확장한다. corp_num은 하이픈
# 제외 숫자만 저장(바로빌 규격 — CorpNum 10자리). barobill_id는 받을돈 채번
# (TaxInvoices::RegisterCorpService — "bd" + user_id 0패딩, 20자 이내)하며 유니크 제약으로
# 1인 1바로빌 계정 불변식을 DB에서 담보한다.
class AddTaxInvoiceSettingsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :corp_num, :string
    add_column :users, :corp_name, :string
    add_column :users, :ceo_name, :string
    add_column :users, :corp_addr, :string
    add_column :users, :contact_name, :string
    # TAX-1 — 과세유형 enum(general: 0 일반과세자 / simplified: 1 간이과세자 / exempt: 2 면세사업자).
    # 세금계산서 TaxType 매핑(1 과세·2 영세·3 면세)의 근거값.
    add_column :users, :tax_type, :integer, default: 0, null: false
    add_column :users, :barobill_id, :string
    # 공동인증서 등록 완료 마킹(TAX-1 전제 — 미등록 시 발행 차단). 전용 상태조회는
    # BaroBill::ClientService#check_cert_is_valid(CheckCERTIsValid)로 실시간 판정한다.
    add_column :users, :barobill_cert_registered, :boolean, default: false, null: false
    add_index :users, :barobill_id, unique: true
  end
end

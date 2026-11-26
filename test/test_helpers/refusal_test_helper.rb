# 수신 거부 마킹 헬퍼(VIEW-7·Q30 — 2026-11-26 폴백 제거 후 공용) — 접수 경로
# (Promises::RegisterService)와 같은 형태로 refused_at·refused_phone을 함께 기록한다.
# refused_phone 없이 refused_at만 찍는 단독 마킹(update_column 우회)은 상속의 원천이
# 되지 않는다 — 거부 행은 자기 행만 차단하고 같은 번호의 새 거래처에 상속되지 않는다.
# 테스트에서 "그 거래처가 거부 접수된 상태"를 만들 때는 반드시 이 헬퍼를 쓴다.
module RefusalTestHelper
  def mark_refused(client, at: Time.current)
    client.update_columns(refused_at: at, refused_phone: client.phone_digits)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include RefusalTestHelper
end

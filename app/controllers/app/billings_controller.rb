# 요금제 페이지(F-PLAN 표면 ②) — 현재 플랜·체험/주기 상태·보유 수금 패스 표시와
# Plus 체험 시작·카드 등록·해지·수금 패스 구매로의 분기 축. 표시에 필요한 @변수를
# 모두 적재하며 구독 행이 없는 기존 사용자도 즉석에서 Free 행을 만들어 일관되게 보여준다.
class App::BillingsController < App::BaseController
  def show
    @subscription = Current.user.subscription || Current.user.create_subscription!(plan: :free)
    @usable_passes = Current.user.payment_passes.usable.order(expires_at: :asc)
    # 수금 패스 결제 대기 주문(구매 버튼 → 위젯 체크아웃 전환) — 위변조 방지로 본인 pending만
    @checkout_order = Current.user.orders.pending.collection_pass
                                .find_by(pg_order_id: params[:checkout]) if params[:checkout].present?
    @portone_store_id = Rails.application.credentials.dig(:portone, :store_id)
    @portone_channel_key_normal = Rails.application.credentials.dig(:portone, :channel_key_normal)
    @portone_channel_key_billing = Rails.application.credentials.dig(:portone, :channel_key_billing)
    # B1(KG이니시스 필수 파라미터) — 위젯 customer 정보·빌링키 발급 건 ID. 표시명은 프로필
    # 완료 가드로(AUTH-1.3), 이메일은 가입 가드로(AUTH-1.4) 항상 존재하고 연락처는 선택
    # 입력이라 빈 값은 위젯 JS가 파라미터에서 뺀다. issueId는 발급 건 고유 번호(ASCII UUID).
    @portone_customer_name = Current.user.display_name
    @portone_customer_phone = Current.user.phone
    @portone_customer_email = Current.user.email
    @portone_billing_issue_id = SecureRandom.uuid
  end
end

# 열람 추적(SHARE-3·P4) — 뷰어(③) 진입 1회마다 ViewEvent를 기록하고, 최초 열람이면 청구서
# 상태를 issued→viewed로 전이한다(INV-4). 두 쓰기를 하나의 트랜잭션으로 묶어 이벤트 기록과
# 상태 전이가 항상 함께 확정되게 한다. 실패는 예외로 전파된다(기록 누락 상태로 뷰어를
# 성공 응답하지 않는다).
module ViewEvents
  class TrackService
    def initialize(invoice:, user_agent:, ip:, viewed_at: Time.current)
      @invoice = invoice
      @user_agent = user_agent
      @ip = ip
      @viewed_at = viewed_at
    end

    def call
      ActiveRecord::Base.transaction do
        # SHARE-3 — first?는 기존 이벤트 0건 기준. 동시 열람 경합에서 이 값은 드물게 중복
        # 기록될 수 있으나 상태 전이는 조건부 UPDATE로 정확히 1회만 적용된다(Invoice#mark_viewed!).
        first = @invoice.view_events.none?
        @invoice.view_events.create!(
          first: first, device: device, ip: @ip, viewed_at: @viewed_at
        )
        @invoice.mark_viewed! if first
      end
      self
    end

    private

    # SHARE-3 — User-Agent로 모바일/PC를 대략 판별한다.
    def device
      ViewEvent.device_from_user_agent(@user_agent)
    end
  end
end

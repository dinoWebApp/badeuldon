# 열람 추적(SHARE-3·P4) — 뷰어(③) 진입 1회마다 ViewEvent를 기록하고, 최초 열람이면 청구서
# 상태를 issued→viewed로 전이한다(INV-4). 두 쓰기를 하나의 트랜잭션으로 묶어 이벤트 기록과
# 상태 전이가 항상 함께 확정되게 한다. 최초 열람 확정 커밋 후 U1 열람 알림(SHARE-4·PERF-1)을
# 인큐한다. 실패는 예외로 전파된다(기록 누락 상태로 뷰어를 성공 응답하지 않는다).
module ViewEvents
  class TrackService
    def initialize(invoice:, user_agent:, ip:, viewed_at: Time.current)
      @invoice = invoice
      @user_agent = user_agent
      @ip = ip
      @viewed_at = viewed_at
    end

    def call
      # SHARE-3(PRD v0.27) — 크롤러·봇 UA는 열람 이력·최초 열람 전이(INV-4)·열람 알림
      # (SHARE-4) 전체에서 제외다("기록 제외"가 확정 설계 — 무기록 반환으로 훅까지 자연 차단).
      return self if ViewEvent.bot?(@user_agent)

      first_viewed = false
      ActiveRecord::Base.transaction do
        # SHARE-3 — first?는 기존 이벤트 0건 기준. 동시 열람 경합에서 이 값은 드물게 중복
        # 기록될 수 있으나 상태 전이는 조건부 UPDATE로 정확히 1회만 적용된다(Invoice#mark_viewed!).
        first = @invoice.view_events.none?
        @invoice.view_events.create!(
          first: first, device: device, ip: normalized_ip, viewed_at: @viewed_at
        )
        first_viewed = first && @invoice.mark_viewed!
      end
      # SHARE-4·PERF-1 — 최초 열람 확정(조건부 UPDATE 승자 1 스레드만) 커밋 후 인큐해 경합의
      # 중복 알림을 흡수한다. U1 향이므로 REM-3 창 없이 즉시(SendService — 확정 해석 3).
      Reminders::DeliverJob.perform_later(@invoice.id, "noti_opened", "user") if first_viewed
      self
    end

    private

    # SHARE-3 — User-Agent로 모바일/PC를 대략 판별한다. device 판정은 절단 전 원본 UA 기준.
    def device
      ViewEvent.device_from_user_agent(@user_agent)
    end

    # 하드닝 — IP는 컬럼 limit 45를 유지하며 공백 제거·절단 정도의 최소 정규화만 적용한다.
    # UA는 저장 컬럼이 없어(device 판정 입력으로만 사용) 절단 대상이 아니다 — device는
    # 절단 개념 없이 원본 UA 기준으로 판정한다.
    def normalized_ip
      @ip.to_s.gsub(/\s+/, "")[0, 45]
    end
  end
end

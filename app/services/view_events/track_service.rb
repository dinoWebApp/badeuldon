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
        # T3 하드닝 — 중복 열람 스팸 억제. 기록 0건(첫 열람)이면 억제 판정 없이 반드시 기록한다
        # (SHARE-4 최초 열람 알림 불변). 기록이 있고 DUPLICATE_WINDOW 이내 동일 청구서+IP
        # 재열람이면 생성을 생략하고 suppressed로 반환한다(알림·상태 전이 모두 없음).
        if !first && duplicate_recently?
          @suppressed = true
          return self
        end
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

    # T3 하드닝 — 재열람이 DUPLICATE_WINDOW 이내 억제됐는지(호출자 구분용).
    def suppressed?
      @suppressed == true
    end

    private

    # T3 하드닝 — 억제 판정 키: 청구서(share token 1:1 대응)+정제된 IP. 윈도우는
    # ViewEvent::DUPLICATE_WINDOW(30분). 조회 최적화 인덱스는 03 문서 "스키마 선언" 참조.
    def duplicate_recently?
      @invoice.view_events
              .where(ip: normalized_ip, viewed_at: ViewEvent::DUPLICATE_WINDOW.ago..)
              .exists?
    end

    # SHARE-3 — User-Agent로 모바일/PC를 대략 판별한다. UA 정제(상한 절단) 후 판별한다.
    def device
      ViewEvent.device_from_user_agent(sanitized_user_agent)
    end

    def sanitized_user_agent
      @sanitized_user_agent ||= ViewEvent.sanitize_user_agent(@user_agent)
    end

    # T3 하드닝 — IP 정제(공백 제거·45자 절단·IPv4/IPv6 형식 검증, 실패 시 "unknown").
    # 정제 결과를 억제 판정 키와 저장 양쪽에 동일하게 사용해 키 일관성을 유지한다.
    def normalized_ip
      @normalized_ip ||= ViewEvent.sanitize_ip(@ip)
    end
  end
end

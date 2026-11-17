# 열람 이벤트(SHARE-3) — 청구서 뷰어(③) 진입 기록. 최초/재열람(first)·대략 디바이스·IP·
# 열람 시각을 남긴다(P4 — 열람도 기록). 기록과 상태 전이(issued→viewed)의 오케스트레이션은
# ViewEvents::TrackService가 담당하며, 이 모델은 데이터·검증만 갖는다.
class ViewEvent < ApplicationRecord
  DEVICES = %w[mobile pc].freeze

  # 열람 스팸 억제(T3 하드닝) — 동일 청구서(share token 1:1 대응)+IP 조합이 이 윈도우 안에
  # 이미 기록돼 있으면 새 이벤트를 만들지 않는다. 첫 열람(기록 0건)은 SHARE-4·PERF-1 때문에
  # 항상 기록+알림 대상이므로, 억제는 두 번째 이후 재열람에만 적용된다.
  DUPLICATE_WINDOW = 30.minutes

  # UA 입력 상한(T3 하드닝) — 비정상적으로 긴 UA(공격 페이로드)가 device·봇 판별 정규식에
  # 그대로 들어가는 것을 막는다. nil은 빈 문자열로 흡수한다(저장 컬럼은 없고 판별 입력 전용).
  UA_MAX_LENGTH = 512

  # SHARE-3 — User-Agent 대략 판별용. 모바일 계열 키워드가 1개라도 매칭되면 mobile로 본다.
  MOBILE_UA_PATTERN = /Android|iPhone|iPad|iPod|Mobile|BlackBerry|Opera Mini|IEMobile|Windows Phone/i

  # SHARE-3(PRD v0.27) — 크롤러·봇 사용자 에이전트 판별. 봇 접근은 열람 이력·최초 열람
  # 전이·열람 알림(SHARE-4) 대상에서 제외된다("기록 제외"가 확정 설계). HeadlessChrome은
  # 의도적으로 제외했다 — Capybara 시스템 테스트 자체 UA라 포함 시 테스트가 전부 파괴된다.
  BOT_UA_PATTERN = /
    Googlebot|bingbot|Yeti|slurp|Mediapartners |
    Slackbot|facebookexternalhit|WhatsApp|Twitterbot|Discordbot|TelegramBot |
    crawl|spider |
    curl|wget|python-requests
  /ix

  # 봇 UA 단일 판정 출처 — TrackService와 테스트가 이 메서드만 참조한다.
  def self.bot?(user_agent)
    user_agent.to_s.match?(BOT_UA_PATTERN)
  end

  # T3 하드닝 — UA 정제(단일 출처). nil 안전 + 길이 상한 절단. 모바일 키워드는 UA 앞부분에
  # 위치하므로 절단이 device 판별 결과에 미치는 영향은 미미하다.
  def self.sanitize_user_agent(user_agent)
    user_agent.to_s.strip[0, UA_MAX_LENGTH]
  end

  # T3 하드닝 — IP 정제(단일 출처). 공백 제거·길이 절단 후 IPv4/IPv6 형식 검증을 통과한
  # 값만 신뢰하고, 그 외(위조·파손된 헤더)는 "unknown"으로 대체한다(ip NOT NULL 유지).
  def self.sanitize_ip(raw_ip)
    candidate = raw_ip.to_s.gsub(/\s+/, "")[0, 45]
    IPAddr.new(candidate)
    candidate
  rescue IPAddr::InvalidAddressError
    "unknown"
  end

  belongs_to :invoice

  validates :device, inclusion: { in: DEVICES }
  validates :viewed_at, :ip, presence: true

  # User-Agent 문자열로 모바일/PC를 판별한다(SHARE-3 — 대략 판별이 목적, 정밀 기기 분석 아님).
  # UA가 비어 있으면 PC로 본다.
  def self.device_from_user_agent(user_agent)
    user_agent.to_s.match?(MOBILE_UA_PATTERN) ? "mobile" : "pc"
  end
end

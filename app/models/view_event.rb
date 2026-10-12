# 열람 이벤트(SHARE-3) — 청구서 뷰어(③) 진입 기록. 최초/재열람(first)·대략 디바이스·IP·
# 열람 시각을 남긴다(P4 — 열람도 기록). 기록과 상태 전이(issued→viewed)의 오케스트레이션은
# ViewEvents::TrackService가 담당하며, 이 모델은 데이터·검증만 갖는다.
class ViewEvent < ApplicationRecord
  DEVICES = %w[mobile pc].freeze

  # SHARE-3 — User-Agent 대략 판별용. 모바일 계열 키워드가 1개라도 매칭되면 mobile로 본다.
  MOBILE_UA_PATTERN = /Android|iPhone|iPad|iPod|Mobile|BlackBerry|Opera Mini|IEMobile|Windows Phone/i

  belongs_to :invoice

  validates :device, inclusion: { in: DEVICES }
  validates :viewed_at, :ip, presence: true

  # User-Agent 문자열로 모바일/PC를 판별한다(SHARE-3 — 대략 판별이 목적, 정밀 기기 분석 아님).
  # UA가 비어 있으면 PC로 본다.
  def self.device_from_user_agent(user_agent)
    user_agent.to_s.match?(MOBILE_UA_PATTERN) ? "mobile" : "pc"
  end
end

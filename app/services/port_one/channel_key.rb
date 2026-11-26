# 포트원 채널 키 환경 선택기(PLAN-5 — 2026-11-25 구현 확정) — 빌링키는 발급 채널에 묶이므로
# 운영(production)만 라이브 채널 키를 쓰고, 그 외 환경(development·test 등)은 테스트 채널 키를
# 쓴다. 환경 판정은 규약 §9.4대로 환경 설정 플래그로 한다 — production.rb만
# config.x.portone_live_channel = true를 정의하고 다른 환경 설정 파일에는 정의하지 않는다
# (미정의 환경·nil은 테스트 채널로 본다 — fail-closed). 채널 키는 이 클래스 한 곳에서만
# 고른다(app 코드의 직접 credentials.dig 참조 금지). fail-closed — 비운영 환경에서 테스트 채널
# 키가 없으면 nil을 돌려주고 라이브 키로 대체하지 않는다(키 부재 환경의 결제가 라이브 채널로
# 나가는 사고 방지. nil 수신은 ClientService의 MissingChannelKey 가드가 API 호출 전에 차단한다).
# fetch에 live·credentials를 인자로 열어 둔 이유는 테스트가 실제 환경 설정·credentials(로컬은
# 값이 있고 CI는 없음)와 무관하게 결과를 고정할 수 있게 하기 위해서다. credentials의 키는
# Rails 규약대로 심볼로 조회한다.
module PortOne
  class ChannelKey
    KINDS = %i[ billing normal ].freeze

    # 운영 환경 판정 — config.x.portone_live_channel 플래그(production.rb만 true).
    # nil·미정의(Rails 8.1 config.x는 정의되지 않은 키에 빈 OrderedOptions를 돌려준다 —
    # 참으로 평가된다)·그 외 값은 false(테스트 채널)로 본다 — 플래그 미정의 환경이 라이브
    # 키를 쓰는 사고를 막는다. == true 비교를 유지한다(truthy 검사로 바꾸면 미정의 환경까지
    # 라이브가 된다).
    def self.live_channel?
      Rails.application.config.x.portone_live_channel == true
    end

    # 정기결제 채널(빌링키 발급·자동결제 차감 — Subscriptions::UpgradeService) 키.
    def self.billing
      fetch(:billing)
    end

    # 단건 결제 채널(수금 패스·내용증명·세금계산서 위젯 체크아웃) 키.
    def self.normal
      fetch(:normal)
    end

    def self.fetch(kind, credentials: Rails.application.credentials, live: live_channel?)
      # to_s.to_sym — nil·문자열·심볼을 모두 안전하게 정규화한다(nil은 빈 심볼로 KINDS 밖).
      raise ArgumentError, "kind는 #{KINDS.join('/')}만 허용됩니다: #{kind.inspect}" unless KINDS.include?(kind.to_s.to_sym)

      suffix = live ? "" : "_test"
      credentials.dig(:portone, :"channel_key_#{kind}#{suffix}")
    end
  end
end

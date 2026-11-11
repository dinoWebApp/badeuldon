# 독촉 문구 생성기 문구 상수(LLP-11 무료 도구 1종·REM-2 4단계 톤). 서버 상수만 사용하며
# 운영자 검수 완료 스타일의 무해 문구만 담는다 — 법적 조치·협박·내용증명 언급 금지(LP-12·P5).
# 상태·쿠키·DB 저장 없음(P3) — 치환은 순수 함수로 GET params 값만 사용한다.
module Tools
  class ReminderTextLibrary
    TONES = {
      "soft" => "부드럽게",
      "polite" => "정중하게",
      "factual" => "사실적으로",
      "firm" => "명확하게"
    }.freeze

    DEFAULT_TONE = "polite"

    # REM-2 톤 4단계 × 3종 = 12종. 변수는 {client}(거래처명)·{amount}(금액)·{due_date}(만기일).
    TEXTS = {
      "soft" => [
        "안녕하세요, {client} 담당자님. {due_date}에 안내드렸던 {amount}가 아직 입금 확인 전이라 여쭤봅니다. 혹시 일정에 차질이 있으시면 편하게 알려주세요.",
        "{client} 담당자님, 바쁘신 와중에 죄송합니다. 청구한 {amount} 건이 확인 대기 중이라 가볍게 접어봅니다. 처리 일정만 한 줄 공유 주시면 감사하겠습니다.",
        "안녕하세요. {amount} 청구 건을 잊고 계실까 봐 다시 안내드립니다. 여유 되시는 때 입금 부탁드리며, 문의 사항이 있으면 언제든 말씀해 주세요."
      ],
      "polite" => [
        "{client} 담당자님, {due_date} 만기의 {amount} 청구 건이 아직 입금 전입니다. 사정이 있으시다면 입금 예정일을 알려주시면 그에 맞춰 진행하겠습니다.",
        "안녕하세요, {client} 담당자님. 청구드린 {amount}가 만기({due_date})를 지나 확인 대기 중입니다. 입금 예정일을 회신 주시면 대단히 감사하겠습니다.",
        "{client} 담당자님, {amount} 청구 건의 입금이 확인되지 않아 안내드립니다. 예정일 공유 부탁드리며, 영수증이 필요하시면 말씀해 주세요."
      ],
      "factual" => [
        "{client} 담당자님, {due_date} 만기의 {amount} 청구 건이 만기일을 경과했습니다. 현재 상태를 확인 부탁드리며, 입금 예정일을 회신 주시면 일정을 갱신하겠습니다.",
        "안내드립니다 — {client} 담당자님. {amount} 청구 건({due_date} 만기)이 미입금 상태입니다. 처리 현황과 입금 예정일 확인 요청드립니다.",
        "{client} 담당자님, {amount} 청구 건이 {due_date} 이후 미입금으로 남아 있습니다. 입금 예정일을 알려주시면 회계 정리에 반영하겠습니다."
      ],
      "firm" => [
        "{client} 담당자님, {due_date} 만기 {amount} 청구 건이 상당 기간 미입금 중입니다. 금주 내 입금 또는 입금 예정일 회신 부탁드립니다.",
        "{client} 담당자님, {amount} 청구 건({due_date} 만기)이 계속 미입금 상태입니다. 이번 주까지 입금 여부를 명확히 알려주시기 바랍니다.",
        "{client} 담당자님, {amount} 청구 건의 입금이 장기 지연되고 있습니다. 구체적인 입금 예정일을 회신 주시지 않으면 후속 조치 일정을 다시 안내드리게 됩니다."
      ]
    }.freeze

    # tone·변수를 받아 치환된 문구 3종 배열을 돌려준다. 톰 미선택·무효면 정중(DEFAULT_TONE).
    def self.messages(tone:, client_name: nil, amount: nil, due_date: nil)
      tone = TONES.key?(tone) ? tone : DEFAULT_TONE
      vars = {
        "client" => client_name.to_s.strip.presence,
        "amount" => format_amount(amount),
        "due_date" => format_due_date(due_date)
      }
      TEXTS.fetch(tone).map { |template| template.gsub(/\{(client|amount|due_date)\}/) { vars[Regexp.last_match(1)] || "" } }
    end

    def self.format_amount(amount)
      value = amount.to_s.delete(",").to_i
      return "" unless value.positive?

      "#{ActiveSupport::NumberHelper.number_to_delimited(value)}원"
    end

    def self.format_due_date(due_date)
      date = due_date.present? ? begin
        Date.parse(due_date)
      rescue ArgumentError
        nil
      end : nil
      return "" unless date

      "#{date.month}월 #{date.day}일"
    end
  end
end

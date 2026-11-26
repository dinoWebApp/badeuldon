require "test_helper"

# 픽스처 날짜 폭탄 재발 방지 가드 (test-date-time-bombs 패턴 3 — T3, 2026-11-26).
# 공유 픽스처에 고정 미래 날짜 리터럴(예: "2026-12-30 23:59:59")이 새로 들어오면
# 그날 바로 이 테스트가 실패한다 — 유효·만료 기간은 ERB 상대값(<%= N.days.from_now %>)으로 쓴다.
# 선례: payment_passes.yml delta_active_pass의 고정 만료 2026-12-30이 2026-12-31에
# 5개 테스트를 실패시켰고, invoices.yml delta_issued의 만료 2026-11-30이 뷰어 테스트를
# 2026-11-30에 실패시킬 뻔했다(둘 다 상대값으로 근본 해소됨).
#
# 검사 대상 형식(2026-11-26 O-2 보강): 하이픈 ISO 외에 점(2026.12.01)·슬래시(2026/12/30)
# 구분자도 탐지하고, ERB 태그(<% ... %>) 부분만 제거한 나머지 텍스트를 검사한다 —
# `값: <%= 상대 %> # 2027-01-01 고정` 같은 ERB 혼합 줄의 고정 날짜도 놓치지 않는다.
# 여러 줄에 걸친 ERB 블록 안은 상대값 계산식·설명이므로 그대로 제외한다.
# 오탐 방지: 월 01~12·일 01~31 범위 제한 — 계좌번호(110-234-567890)·전화번호(010-3333-7777)·
# 품목 코드(BD-20260901-001)는 날짜로 해석되지 않는다.
#
# 예외 행은 해당 줄에 `fixtures_no_future_date: 허용 — 사유` 인라인 마커를 달아 가드가 제외한다.
# 현재 마커 예외는 0건 — "사실상 무기한"을 뜻하는 먼 미래 값도 상대값(예: 90.days.from_now)으로 쓴다.
class FixturesNoFutureDateTest < ActiveSupport::TestCase
  DATE_LITERAL_PATTERN = /20\d{2}[.\-\/](?:0[1-9]|1[0-2])[.\-\/](?:0[1-9]|[12]\d|3[01])/

  test "픽스처에 고정 미래 날짜 리터럴이 없다(test-date-time-bombs 패턴 3 가드)" do
    offenders = []

    Dir[Rails.root.join("test/fixtures/*.yml")].sort.each do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      future_date_literals(File.read(path)).each do |hit|
        offenders << "#{relative}:#{hit[:line]} — #{hit[:literal]} (줄: #{hit[:text].strip})"
      end
    end

    assert_empty offenders, <<~MESSAGE
      픽스처에 고정 미래 날짜 리터럴이 있습니다 — 날짜가 지나면 테스트가 실패하는 날짜 폭탄입니다.
      유효·만료 기간은 ERB 상대값(예: <%= 30.days.from_now.end_of_day %>)으로 바꾸세요.
      특정 시점 재현이 필요하면 테스트에서 travel_to를 쓰고, 의도된 먼 미래 값이면
      해당 줄에 `# fixtures_no_future_date: 허용 — 사유` 마커를 남기고 이 테스트에 사유를 기록하세요.

      #{offenders.join("\n")}
    MESSAGE
  end

  test "가드 판정 — ERB가 섞인 줄의 고정 미래 날짜도 탐지한다(O-2 a)" do
    hits = future_date_literals(<<~YML)
      delta_x:
        expires_at: <%= 30.days.from_now.end_of_day %> # 2099-12-31 고정
    YML
    assert_equal [ "2099-12-31" ], hits.map { |h| h[:literal] }
    assert_equal 2, hits.first[:line]
    assert_includes hits.first[:text], "expires_at:"
  end

  test "가드 판정 — 과거 날짜는 탐지하지 않는다" do
    hits = future_date_literals(<<~YML)
      delta_x:
        due_on: "2020-01-15"
        issued_at: "2020/03/01"
        voided_at: "2020.04.02 09:00:00"
    YML
    assert_empty hits
  end

  test "가드 판정 — 여러 줄 ERB 블록 안의 날짜는 무시한다" do
    hits = future_date_literals(<<~YML)
      <%
        # 상대값 계산 — 2099-12-31 같은 날짜는 여기 와도 무시
        expires = 30.days.from_now
      %>
      delta_x:
        expires_at: <%= expires %>
    YML
    assert_empty hits
  end

  test "가드 판정 — 점·슬래시 구분자 날짜도 탐지한다(O-2 b)" do
    hits = future_date_literals(<<~YML)
      delta_x:
        due_on: "2099.12.01"
        issued_at: "2099/12/30 09:00"
    YML
    assert_equal %w[2099.12.01 2099/12/30], hits.map { |h| h[:literal] }
  end

  test "가드 판정 — 계좌번호·전화번호·품목 코드는 오탐하지 않는다" do
    hits = future_date_literals(<<~YML)
      delta_x:
        account_number: "110-234-567890"
        phone: "010-3333-7777"
        issue_number: "BD-20260901-001"
        note: "2026-13-40은 월·일 범위 밖이라 날짜 아님"
    YML
    assert_empty hits
  end

  test "가드 판정 — 인라인 마커 줄은 제외한다" do
    hits = future_date_literals(<<~YML)
      delta_x:
        expires_at: "2099-12-31" # fixtures_no_future_date: 허용 — 사실상 무기한
    YML
    assert_empty hits
  end

  test "가드 판정 — 불가능한 날짜 리터럴(2099-02-30)은 보고되고 예외가 나지 않는다" do
    hits = future_date_literals(<<~YML)
      delta_x:
        due_on: "2099-02-30"
        issued_at: "2099-02-29"
    YML
    assert_equal %w[2099-02-30 2099-02-29], hits.map { |h| h[:literal] }
  end

  private

  # 판정 로직 단일 진입점 — 파일 텍스트(문자열)를 받아 미래 날짜 리터럴 목록을 돌려준다.
  # 위 가드 테스트들이 이 메서드로 가드 자신의 동작을 고정한다.
  def future_date_literals(text)
    hits = []
    in_erb_block = false

    text.each_line.with_index do |line, index|
      opens = line.scan(/<%/).length
      closes = line.scan(/%>/).length
      was_in_block = in_erb_block
      in_erb_block = (in_erb_block && closes.zero?) || opens > closes
      next if was_in_block

      # 인라인 마커로 승인된 줄은 제외(사유는 마커에 함께 기술)
      next if line.include?("fixtures_no_future_date")

      plain = text_outside_erb(line)
      plain.scan(DATE_LITERAL_PATTERN).each do |literal|
        hits << { line: index + 1, literal: literal, text: plain }
      end
    end

    hits.select do |hit|
      begin
        Date.parse(hit[:literal]) > Date.current
      rescue Date::Error, ArgumentError
        # 형식은 맞지만 존재하지 않는 날짜(예: 2099-02-30)도 고정 리터럴이므로 오탐자로 보고한다
        hit[:text] << " (존재하지 않는 날짜 리터럴)"
        true
      end
    end
  end

  # 한 줄에서 ERB 태그(<% ... %>) 부분만 제거한 텍스트 — 태그 바깥의 고정 날짜를 검사하기 위함.
  # 줄 경계를 넘는 미완결 태그(<% 또는 %>만 있는 경우)는 블록 여는/닫는 부분 이후·이전을 버린다.
  def text_outside_erb(line)
    plain = line.gsub(/<%.*?%>/, "")
    plain = plain.sub(/<%.*\z/, "") if plain.include?("<%")
    plain = plain.sub(/\A.*?%>/, "") if plain.include?("%>")
    plain
  end
end

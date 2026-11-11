require "test_helper"

module Tools
  class ReminderTextLibraryTest < ActiveSupport::TestCase
    # LP-11 무료 도구 1종 — REM-2 톤 4단계 × 3종 상수 문구·변수 치환. 저장 없음(P3).
    test "12종 문구 상수 존재 (톤 4 × 3종)" do
      assert_equal 4, ReminderTextLibrary::TEXTS.size
      assert_equal %w[soft polite factual firm], ReminderTextLibrary::TEXTS.keys
      ReminderTextLibrary::TEXTS.each_value do |texts|
        assert_equal 3, texts.size
      end
    end

    test "톤 라벨은 REM-2 4단계를 커버한다" do
      assert_equal [ "부드럽게", "정중하게", "사실적으로", "명확하게" ], ReminderTextLibrary::TONES.values
    end

    test "모든 문구에 법적 조치·협박 표현이 없다 (LP-12·P5)" do
      banned = [ "법적", "내용증명", "소송", "채권양도", "협박", "고소", "강제" ]
      ReminderTextLibrary::TEXTS.values.flatten.each do |text|
        banned.each { |word| assert_not text.include?(word), "금지 표현 #{word} 발견: #{text}" }
      end
    end

    test "변수 치환 — 거래처명·금액(천단위 콤마)·만기일(M월 D일)" do
      messages = ReminderTextLibrary.messages(
        tone: "polite", client_name: "가나디자인", amount: "1000000", due_date: "2026-11-30"
      )
      assert_equal 3, messages.size
      joined = messages.join(" ")
      assert_includes joined, "가나디자인"
      assert_includes joined, "1,000,000원"
      assert_includes joined, "11월 30일"
      messages.each { |message| assert_not_includes message, "{client}" }
    end

    test "톤 미선택·무효 톤은 정중 기본" do
      assert_equal ReminderTextLibrary.messages(tone: "polite"), ReminderTextLibrary.messages(tone: nil)
      assert_equal ReminderTextLibrary.messages(tone: "polite"), ReminderTextLibrary.messages(tone: "hacker")
    end

    test "빈 입력 시 변수는 빈 문자열로 치환된다" do
      messages = ReminderTextLibrary.messages(tone: "soft")
      messages.each do |message|
        assert_not_includes message, "{}"
        assert_not_includes message, "원원"
      end
    end

    test "콤마 포함 금액 문자열도 처리한다" do
      messages = ReminderTextLibrary.messages(tone: "firm", amount: "1,000,000")
      messages.each { |message| assert_includes message, "1,000,000원" }
    end

    test "잘못된 만기일은 빈 문자열" do
      messages = ReminderTextLibrary.messages(tone: "soft", due_date: "not-a-date")
      assert_equal ReminderTextLibrary.messages(tone: "soft"), messages
      messages.each { |message| assert_not_includes message, "not-a-date" }
    end
  end
end

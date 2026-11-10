require "test_helper"

# ADMIN-8 — TicketMessage 모델. sender enum·본문 2,000자 상한·AS 첨부 1장
# (jpg/png/webp 수용·csv/gif 거부·5MB 초과 거부 — Marcel 매직바이트 실측 패턴 준용).
# 첨부는 fixture를 쓸 수 없다(encrypts 우회 교훈과 동일 원리 — AS blob은 업로드 경유) —
# setup에서 실제 매직바이트 io로 attach한다.
class TicketMessageTest < ActiveSupport::TestCase
  setup do
    @ticket = Ticket.create!(user: users(:gamma), title: "첨부 검증용 문의")
  end

  test "sender enum — user 기본값 아님·명시 필수·양쪽 값 동작 (ADMIN-8)" do
    assert TicketMessage.new(sender: :user).user?
    assert TicketMessage.new(sender: :admin).admin?
    # sender 컬럼은 null: false·기본값 없음 — 누락 생성은 DB 수준에서 차단된다.
    assert_raise ActiveRecord::NotNullViolation do
      TicketMessage.create!(ticket: @ticket, body: "sender 누락")
    end
  end

  test "body 필수·2,000자 상한 (ADMIN-8)" do
    assert TicketMessage.new(ticket: @ticket, sender: :user).invalid?
    assert TicketMessage.new(ticket: @ticket, sender: :user, body: "a" * 2_001).invalid?
    assert TicketMessage.new(ticket: @ticket, sender: :user, body: "a" * 2_000).valid?
  end

  test "jpg·png·webp 첨부 수용 (ADMIN-8)" do
    {
      "proof.jpg" => "image/jpeg",
      "proof.png" => "image/png",
      "proof.webp" => "image/webp"
    }.each do |filename, content_type|
      message = TicketMessage.new(ticket: @ticket, sender: :user, body: "증빙")
      message.image.attach(io: StringIO.new(magic_bytes(content_type)),
                           filename:, content_type:)
      assert message.valid?, "#{filename}은 수용되어야 한다"
      assert message.save
      message.destroy
    end
  end

  test "csv·gif 첨부 거부 (ADMIN-8 — 5MB 이하라도)" do
    { "data.csv" => "text/csv", "anim.gif" => "image/gif" }.each do |filename, content_type|
      message = TicketMessage.new(ticket: @ticket, sender: :user, body: "증빙")
      message.image.attach(io: StringIO.new(magic_bytes(content_type)),
                           filename:, content_type:)
      assert message.invalid?, "#{filename}은 거부되어야 한다"
      assert_not_nil message.errors[:image]
    end
  end

  test "HTML 위조 확장자(png 명칭·HTML 내용)는 Marcel 매직바이트로 거부 (리뷰 ⑬ 준용)" do
    message = TicketMessage.new(ticket: @ticket, sender: :user, body: "위조")
    message.image.attach(io: StringIO.new("<html><h1>not an image</h1></html>"),
                         filename: "spoof.png", content_type: "image/png")
    assert message.invalid?
  end

  test "5MB 초과 첨부 거부 (ADMIN-8)" do
    message = TicketMessage.new(ticket: @ticket, sender: :user, body: "대용량")
    message.image.attach(io: StringIO.new("\x89PNG\r\n\x1a\n" + ("0" * (5.megabytes + 1))),
                         filename: "big.png", content_type: "image/png")
    assert message.invalid?
    assert_not_nil message.errors[:image]
  end

  test "첨부 없이도 저장 가능 — 이미지는 선택 (ADMIN-8)" do
    assert TicketMessage.create!(ticket: @ticket, sender: :user, body: "텍스트만").valid?
  end

  private

  # 실제 파일 시그니처 — 검증은 blob의 Marcel 판정(content_type)을 통과하므로 매직바이트가 필요.
  def magic_bytes(content_type)
    case content_type
    when "image/jpeg" then "\xFF\xD8\xFF\xE0" + ("0" * 16)
    when "image/png" then "\x89PNG\r\n\x1a\n" + ("0" * 16)
    when "image/webp" then "RIFF" + [ 20 ].pack("V") + "WEBPVP8 " + ("0" * 8)
    when "image/gif" then "GIF89a" + ("0" * 12)
    else "col1,col2\n1,2\n" # text/csv — 텍스트
    end
  end
end

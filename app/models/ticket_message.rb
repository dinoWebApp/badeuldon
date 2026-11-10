# 티켓 스레드의 개별 발화(ADMIN-8). sender로 문의자(user)·운영자(admin)를 구분하고,
# 이미지 첨부는 Active Storage 1장(사용자 첨부 선택 — 5MB·jpg/png/webp 한정. 프로젝트 첫 AS
# 도입 — disk 저장). 관리자 답변은 텍스트만이 원칙이나 동일 규칙을 일괄 적용해 검증을
# 단일화한다(운영자가 증빙 이미지를 붙일 가능성도 열어둔다).
class TicketMessage < ApplicationRecord
  belongs_to :ticket

  has_one_attached :image

  enum :sender, { user: 0, admin: 1 }

  validates :body, presence: true, length: { maximum: 2_000 }
  validate :image_format_and_size

  scope :ordered, -> { order(:created_at, :id) }

  private

  # 첨부 형식·크기 가드 — blob이 이미 업로드된 시점에 검증한다(파일 입력은 컨트롤러에서
  # 전달받는다). 허용: jpg/png/webp · 5MB 이하(PRD ADMIN-8 확정 해석).
  def image_format_and_size
    return unless image.attached?

    unless image.blob.content_type.in?(%w[image/jpeg image/png image/webp])
      errors.add(:image, "는 JPG·PNG·WEBP 형식만 첨부할 수 있습니다")
    end
    return if image.blob.byte_size <= 5.megabytes

    errors.add(:image, "는 5MB 이하만 첨부할 수 있습니다")
  end
end

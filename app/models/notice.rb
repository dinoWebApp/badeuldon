# 운영 공지(ADMIN-6 관리 · ADMIN-7 U1 노출). 게시 기간은 KST 기준(TIME-1 — Time.current).
# 일반(general)은 대시보드 배너, 중요(important)는 /app 전체 팝업으로 노출된다.
class Notice < ApplicationRecord
  has_many :notice_reads, dependent: :destroy

  enum :importance, { general: 0, important: 1 }, default: :general

  validates :title, presence: true
  validates :body, presence: true
  validate :expires_at_after_published_at

  scope :ordered, -> { order(published_at: :desc, id: :desc) }

  # ADMIN-7 게시 중 — 발행 시각이 지났고(초안 제외) 만료가 없거나 아직 지나지 않은 공지.
  scope :published_now, lambda {
    where(published_at: ..Time.current)
      .where("expires_at IS NULL OR expires_at >= ?", Time.current)
  }

  # 상태 판정(ADMIN-6 목록 배지) — 인스턴스 술어라 뷰에서 호출 가능(쿼리 아님).
  def draft? = published_at.nil?
  def live? = published_at.present? && published_at <= Time.current && (expires_at.nil? || expires_at >= Time.current)
  def ended? = published_at.present? && !live?

  private

  def expires_at_after_published_at
    return if expires_at.blank? || published_at.blank?
    errors.add(:expires_at, "는 게시 시작 시각 이후여야 합니다") if expires_at <= published_at
  end
end

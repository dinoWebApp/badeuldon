# 1:1 문의 티켓 헤더(ADMIN-8 — Run C). 스레드 본문은 ticket_messages가 담당한다.
# 상태 규칙: 접수(open) → 관리자 답변 시 answered → 사용자 추가 질문 시 open 복귀(스레드 보존)
# → 관리자만 종료(closed — 사용자에게 종료 권한은 없다 — PROMISE-7의 U2 마감 권한 부재와 같은
# 원칙). 종료 전까지 추가 질문 가능, 종료 후 재개 경로 없음(새 티켓 작성).
class Ticket < ApplicationRecord
  belongs_to :user
  has_many :ticket_messages, dependent: :destroy

  # 분류 5종 — PRD ADMIN-8(결제/이용 문의/버그 제보/기능 제안/기타). default는 etc.
  enum :category, { billing: 0, support: 1, bug: 2, feature: 3, etc: 4 }, default: :etc
  enum :status, { open: 0, answered: 1, closed: 2 }, default: :open

  validates :title, presence: true, length: { maximum: 100 }

  scope :ordered, -> { order(created_at: :desc, id: :desc) }

  # 관리자 답변 등록 — open 상태에서만 유효. 이미 answered·closed면 무시(멱등).
  def mark_answered!
    update!(status: :answered) if open?
  end

  # 사용자 추가 질문 — 답변(answered) 이후 재문의 시 open으로 복귀(스레드 보존).
  # open이면 그대로, closed면 거부(호출측 FollowUpService 가드).
  def reopen!
    update!(status: :open) if answered?
  end

  # 관리자 종료 — 어느 상태에서든 가능(답변 전 강제 종료도 운영 정책상 허용).
  def mark_closed!
    update!(status: :closed) unless closed?
  end
end

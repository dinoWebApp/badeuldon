# 운영 감사 로그(ADMIN-2). 생성은 AuditLogs::RecordService 단일 진입점으로만 허용한다
# (컨트롤러 직접 create 금지 — P4 모든 발신/행위는 기록).
# action 확정값(02 확정 해석 4): login_success · login_failed · lockout · new_ip_login ·
# password_reset (+unlock 등 runner 절차). enum 미적용 — Run B~C에서 행위별 action 추가를
# 자유롭게 허용하기 위한 설계.
#
# 리뷰 W-3 수용 — admin FK는 on_delete: :cascade이지만 Run A에는 관리자 삭제 경로가 없다
# (AUTH-7.2 공개 가입·삭제 UI 부재, 운영 절차만 존재). 감사 이력은 관리자보다 오래 살아야
# 하므로 Run B(회원 관리 UI)에서 restrict/nullify 정책 재검토 필수.
class AuditLog < ApplicationRecord
  belongs_to :admin

  # ADMIN-2 감사 로그 뷰(Run B) 필터용 스코프 — 최신순 기본, action·관리자·기간 조합 필터.
  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :by_action, ->(action) { where(action: action) if action.present? }
  scope :by_admin, ->(admin_id) { where(admin_id: admin_id) if admin_id.present? }
  # W-2 — 무효 날짜 파라미터(파싱 실패·nil)는 해당 필터 생략(가용성 방어 — 500 금지)
  def self.by_period(from, to)
    start_at = safe_boundary(from, :beginning_of_day) || 100.years.ago
    end_at = safe_boundary(to, :end_of_day) || Time.current.end_of_day
    where(created_at: start_at..end_at)
  end

  def self.safe_boundary(value, boundary)
    parsed = value.present? ? Time.zone.parse(value) : nil
    parsed&.public_send(boundary)
  rescue ArgumentError
    nil
  end
  private_class_method :safe_boundary
end

# NOTI-2 주간 다이제스트(F-REM 이후 NOTI 확장) — 매주 월요일 09:00 KST recurring
# (config/recurring.yml noti2_weekly_digest — fugit KST 접미사, TIME-1). 인자 없음.
# 발송 대상 = 전화번호 보유 · active · 토글(noti2_digest_enabled — 기본 on) 사용자 전체.
# 템플릿 미등록 상태라 모든 발송은 Noti::WeeklyDigestService가 skipped(NO_TEMPLATE)로
# 기록하고 정상 종료한다(NOTI-3 선례 — 솔라피 등록 후 코드 변경 없이 자동 활성화).
#
# 멱등(SEC-5 준칙) — 주 단위 결정적 키로 흡수한다: 서비스가 MessageLog.scheduled_at에
# 기간 시작(지난주 월요일 00:00 KST)을 저장하고 같은 키의 기존 이력이 있으면 :duplicate로
# skip한다. 잡 재실행·Solid Queue 재전달·동시 실행 모두 중복 발송·이력 누적 없다. 개별
# 사용자 실패는 로그 후 나머지를 계속 처리한다(RecurringInvoices::IssueJob과 같은 패턴).
class Noti::WeeklyDigestJob < ApplicationJob
  queue_as :default

  def perform
    User.where(status: :active)
        .where(noti2_digest_enabled: true) # 컬럼 접근자 없이 직접 참조(T7 스키마 선언 — 3-S 마이그레이션)
        .where.not(phone: [ nil, "" ])
        .find_each do |user|
      Noti::WeeklyDigestService.new(user: user).call
    rescue StandardError => e
      Rails.logger.error("[Noti::WeeklyDigestJob] user=#{user.id} #{e.class}: #{e.message}")
    end
  end
end

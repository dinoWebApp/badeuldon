# 즉시·단건 발송(F-REM) — 이벤트성 발송(noti_*·partial_paid·paid_thanks)과 모호 실패 재시도의
# 잡 진입점. 인자는 스칼라만(§11.2 — 잡 인자 규약). origin은 발신 주체 전달용 스칼라 인자다
# (B-2 — SendService의 창 밖 재예약이 접수 시점의 origin을 유지한다. Free 수동 재예약이
# origin=auto로 실행돼 INELIGIBLE_PLAN skip되던 경로 해소). 미지정 시 기존 호출점(모두 자동
# 계열 이벤트·재시도)과의 호환을 위해 auto로 채운다. REM-3 창 밖에 접수된 채무자 향 발송은
# SendService가 다음 평일 09시로 재예약한다(:rescheduled — 확정 해석 3·4).
# 솔라피 래퍼(W-7) — 잡 인자는 스칼라만이라 래퍼 객체를 직접 전달할 수 없고, 이 잡은
# SendService(생성자 client: 주입·기본 지연 생성)를 감싸기만 한다. 잡 계층 검증의 실호출
# 방지는 SolapiStubbing.with_solapi_client(test/test_helpers — PortOneStubbing 준용)으로
# 래퍼 생성 경로를 가로챈다 — RAILS_ENV=test에서도 credentials의 유효 키가 로드되므로
# perform_now는 stub 없이 실행하면 실제 API를 호출한다.
# 재시도 불변식 — SendService는 실패를 failed로 기록한 뒤 모호 실패(TIMEOUT/CONNECTION)만
# 재상승하므로, 이 잡에 도달하는 Solapi::ApiError는 항상 재시도 대상이다(확정 실패는 기록 후
# 종료). Rails 8.1 retry_on에 :if 옵션이 없어 이 계층 불변식으로 재시도를 한정한다.
module Reminders
  class DeliverJob < ApplicationJob
    queue_as :default

    retry_on Solapi::ApiError, wait: 30.seconds, attempts: 3
    discard_on ActiveRecord::RecordNotFound

    def perform(invoice_id, template_key, recipient_role, origin = :auto)
      invoice = Invoice.find(invoice_id)
      Reminders::SendService.new(invoice: invoice, template_key: template_key,
                                 recipient_role: recipient_role, origin: origin).call
    end
  end
end

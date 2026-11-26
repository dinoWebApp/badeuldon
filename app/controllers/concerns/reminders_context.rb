# F-REM(REM-6/8) — 청구서 상세 화면의 발송 이력·수동 발송 컨텍스트 적재 공통 관심사.
# 상세 템플릿(app/invoices/show)을 그리는 컨트롤러(Invoices·Payments·Promises — 성공 렌더와
# 422 재렌더 모두)가 동일한 @변수 세트를 갖게 한다. 뷰는 @변수만 소비하므로(쿼리 금지),
# 이 관심사가 화면 데이터의 단일 적재점이다.
module RemindersContext
  extend ActiveSupport::Concern

  private

  # REM-6 — 발송 이력(최신 우선). Invoice와 MessageLog 사이 has_many 연관이 없어(3-a 스키마
  # 그대로) invoice_id 스코프 조회로 적재한다.
  def set_message_logs
    @message_logs = MessageLog.where(invoice_id: @invoice.id)
                              .order(created_at: :desc, id: :desc)
  end

  # REM-8 — 수동 발송 버튼의 표기용 컨텍스트. 자격 판정(User#reminder_eligible? — 플랜·수금패스
  # 조회가 동반되므로 뷰가 아닌 컨트롤러에서 산출)과 다음 안내 라벨이다.
  # PLAN-3·Q28·W-4 — 상한 도달 판정(Invoice#reminder_cap_reached? 단일 출처)도 화면 데이터의
  # 일부로 여기서 적재한다(뷰는 @변수만 소비 — 쿼리 금지). 상세 화면의 배지·안내 상자·버튼
  # 숨김 판정이 모두 이 값을 쓴다.
  # PLAN-3·W-3(마감 리뷰 2026-11-26) — 수동 상한 판정(Invoice#manual_reminder_cap_reached?
  # 단일 출처)도 함께 적재한다. 자동 1회성(partial_paid 등)만으로 수동 상한(채무자 향 sent
  # 전체 5통)에 걸린 청구는 자동 상한 판정(@reminder_cap_reached)이 거짓이라 「지금 1통
  # 보내기」가 보이지만 누르면 CAP_REACHED로 막힌다 — 이 값을 보고 버튼·다음 안내 표기를
  # 숨긴다.
  def set_reminder_context
    @reminder_eligible = Current.user.reminder_eligible?
    @manual_template_key = manual_template_key
    @reminder_cap_reached = @invoice.reminder_cap_reached?
    @manual_cap_reached = @invoice.manual_reminder_cap_reached?
  end

  # REM-8 수동 발송 템플릿 산정("현재 상황에 맞는 다음 1통") — DispatchService의 공개 산정
  # 진입점(manual_step_key)이 단일 출처다(W-1 해소 — 컨트롤러 계층의 트랙·분기·버킷 판정
  # 복제를 서비스로 수렴. 자동 스캔·사전통보·재개 판정과 같은 steps_for·소급 창 판정을
  # 공유한다). 최종 가드(보류·수신거부·상한·발송 창)는 Reminders::SendService가 다시 확인한다.
  def manual_template_key
    Reminders::DispatchService.new.manual_step_key(@invoice)
  end
end

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
  def set_reminder_context
    @reminder_eligible = Current.user.reminder_eligible?
    @manual_template_key = manual_template_key
  end

  # REM-8 수동 발송 템플릿 산정("현재 상황에 맞는 다음 1통") — DispatchService의 공개 산정
  # 진입점(manual_step_key)이 단일 출처다(W-1 해소 — 컨트롤러 계층의 트랙·분기·버킷 판정
  # 복제를 서비스로 수렴. 자동 스캔·사전통보·재개 판정과 같은 steps_for·소급 창 판정을
  # 공유한다). 최종 가드(보류·수신거부·상한·발송 창)는 Reminders::SendService가 다시 확인한다.
  def manual_template_key
    Reminders::DispatchService.new.manual_step_key(@invoice)
  end
end

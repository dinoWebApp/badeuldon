module App
  # 약속(F-PROMISE) 화면 공용 — 청구서 상세 응답·약속 이력 타임라인·대시보드 오늘의 액션 라벨.
  module PromisesHelper
    # PROMISE-1 종류 라벨 — 채무자가 누른 버튼 원문을 U1 화면에서도 그대로 인용한다
    # (누가 무엇으로 응답했는지가 곧 기록이며, 어휘를 이원화하지 않는다 — P1).
    def promise_kind_label(promise)
      {
        "this_week" => "이번 주 내에 입금할게요",
        "date_selected" => "입금 예정일 지정",
        "paid_report" => "이미 입금했어요",
        "inquiry" => "문의·이의 있어요"
      }.fetch(promise.kind)
    end
  end
end

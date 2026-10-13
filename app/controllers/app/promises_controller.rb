# 문의 답변(F-PROMISE·PROMISE-6) — U1이 무답변 inquiry에 답변을 등록한다(1문의 1답변).
# 조회·변경은 현재 사용자의 청구서 응답으로 스코프해 소유권을 격리하며, 기록은
# Promise#answer!(answered_at의 유일한 기록 경로)가 담당한다. 성공 303 / 실패 422(청구서
# 상세 재렌더 — 작성 중 답변 보존). 등록된 답변은 뷰어(③) 발행인 답변 영역에서 채무자가
# 확인하며 연락처는 노출되지 않는다(P2).
class App::PromisesController < App::BaseController
  before_action :set_promise, only: %i[ answer ]

  # 무답변 문의 → 답변 완료 전이(응답 자원의 상태 변경 — member 액션으로 정당화).
  def answer
    if @promise.answer!(promise_params[:answer])
      redirect_to app_invoice_path(@promise.invoice), status: :see_other,
                  notice: "답변을 등록했습니다. 거래처가 청구서 링크에서 확인할 수 있습니다."
    else
      # 재답변 차단(:base) 등 answer! 실패 안내 — 폼은 422 재렌더 시 최신 이력으로 적재되므로
      # 오류를 지니지 않아, 레이아웃 플래시로 표시한다(Phase 6 리뷰 #2). :base는 접두사 없는
      # full_messages_for, :answer는 폼 인라인 표시(form_error_message)와 동일한 원문 메시지.
      flash.now[:alert] = @promise.errors.full_messages_for(:base).first ||
                          @promise.errors[:answer].first
      load_invoice_show
      render "app/invoices/show", status: :unprocessable_entity
    end
  end

  private

  # 소유권 격리 — 타인 청구서의 응답은 애초에 조회되지 않는다(404로 수렴).
  def set_promise
    @promise = Promise.where(invoice_id: Current.user.invoices.select(:id)).find(params[:id])
  end

  def promise_params
    params.expect(promise: [ :answer ])
  end

  # 실패 422 재렌더에 청구서 상세 템플릿이 필요로 하는 @변수 — App::InvoicesController와
  # 동일 구성(SHARE-3 열람 이력·F-PROMISE 응답 이력).
  def load_invoice_show
    @invoice = @promise.invoice
    @view_events = @invoice.view_events.order(:viewed_at, :id)
    @promises = @invoice.promises.order(created_at: :desc, id: :desc)
  end
end

# 품목 라이브러리(CLIENT-2) — 표면 ② 표준 CRUD. 거래처(CLIENT-1)와 동일 패턴이며
# 플랜 한도는 없다. 조회·변경은 Current.user.items로 스코프한다.
class App::ItemsController < App::BaseController
  before_action :set_item, only: %i[ show edit update destroy ]

  def index
    @items = Current.user.items.order(:id)
  end

  def show; end

  def new
    @item = Current.user.items.build
  end

  def create
    @item = Current.user.items.build(item_params)
    if @item.save
      redirect_to app_items_path, status: :see_other, notice: "품목이 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @item.update(item_params)
      redirect_to app_items_path, status: :see_other, notice: "품목이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy!
    redirect_to app_items_path, status: :see_other, notice: "품목이 삭제되었습니다."
  end

  private

  def set_item
    @item = Current.user.items.find(params[:id])
  end

  def item_params
    params.expect(item: [ :name, :unit_price ])
  end
end

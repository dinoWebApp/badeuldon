# ADMIN-10·BLOG-5 — 블로그 콘텐츠 관리(Run C 공지 관리 톤 준용). CRUD + 상태 전이
# publish(즉시 발행·필수 필드 검증)·schedule(예약)·unpublish(비공개)는 예외적 동사라
# member PATCH로 정당화한다. admin nav "콘텐츠" 메뉴는 3-S 결선으로 등록 완료.
class Admin::BlogPostsController < Admin::BaseController
  before_action :set_blog_post, only: %i[ edit update publish schedule unpublish destroy ]

  helper_method :blog_status_badge

  def blog_status_badge(post)
    case post.status
    when "draft" then [ "초안", "bg-stone-100 text-stone-500" ]
    when "scheduled" then [ "예약", "bg-blue-50 text-blue-700" ]
    when "published" then [ "공개", "bg-green-50 text-green-700" ]
    else [ "비공개", "bg-orange-50 text-orange-600" ]
    end
  end

  def index
    scope = BlogPost.order(updated_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].in?(BlogPost.statuses.keys)
    scope = scope.with_category(params[:category]) if params[:category].present?
    @blog_posts = scope.limit(100)
  end

  def new
    @blog_post = BlogPost.new
  end

  def create
    @blog_post = BlogPost.new(blog_params)
    @blog_post.admin = current_admin
    @blog_post.generate_slug!
    if @blog_post.save
      redirect_to admin_blog_posts_path, status: :see_other, notice: "게시글이 저장되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @blog_post.update(blog_params)
      redirect_to admin_blog_posts_path, status: :see_other, notice: "게시글이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 즉시 발행 — 썸네일·OG 이미지·메타 2종 등 필수 필드 검증(BLOG-5). 실패 사유는 alert로.
  # [C-4(05_review)·BLOG-6] 발행 성공 후 본문에 도구·게시글 내부 링크가 없으면 notice에
  # 경고를 덧붙인다(강제 아님 — 발행은 그대로 유지).
  def publish
    if @blog_post.publish!
      notice = "게시글이 발행되었습니다."
      unless @blog_post.body_md.match?(%r{/tools|/blog/})
        notice += " (참고: 본문에 무료 도구·관련 게시글 내부 링크가 없습니다 — 추가하면 체류 시간이 늘어납니다.)"
      end
      redirect_to admin_blog_posts_path, status: :see_other, notice: notice
    else
      redirect_to edit_admin_blog_post_path(@blog_post), status: :see_other,
                  alert: "발행에 실패했습니다. #{@blog_post.errors.full_messages.to_sentence}"
    end
  end

  # 예약 발행 — publish_at은 폼에서 전달받는다(비어 있으면 422 재렌더).
  def schedule
    if @blog_post.schedule!(blog_params[:publish_at])
      redirect_to admin_blog_posts_path, status: :see_other, notice: "예약 발행이 설정되었습니다."
    else
      redirect_to edit_admin_blog_post_path(@blog_post), status: :see_other,
                  alert: "예약에 실패했습니다. 발행 예정 시각을 지정해 주세요."
    end
  end

  def unpublish
    @blog_post.unpublish!
    redirect_to admin_blog_posts_path, status: :see_other, notice: "게시글이 비공개 전환되었습니다."
  end

  def destroy
    @blog_post.destroy
    redirect_to admin_blog_posts_path, status: :see_other, notice: "게시글이 삭제되었습니다."
  end

  private

  def set_blog_post
    @blog_post = BlogPost.find(params[:id])
  end

  # xxx_params — 컨벤션(params.expect + private #xxx_params)
  def blog_params
    params.expect(blog_post: [
      :title, :slug, :body_md, :category, :tags, :summary,
      :meta_title, :meta_description, :publish_at, :thumbnail, :og_image
    ])
  end
end

# 표면 ① 블로그(/blog) — BLOG-1~4·LP-11 허브의 공개 코어. 비로그인 공개(SURF-1)이며
# NOINDEX_PATH_PREFIXES 미포함 — 색인 허용(SURF-3 예외·BLOG-2). LandingController 패턴 준용.
# 상세는 SURF-6(2초 예산)을 위해 fragment 캐시(본문·목차 — 게시글 갱신 시 만료)를 적용한다.
class BlogController < ApplicationController
  include AllowAllBrowsers
  allow_unauthenticated_access

  layout "blog"

  PAGE_SIZE = 12

  # BLOG-3 — 최신순·카테고리 필터·페이지네이션(페이지당 12건 — offset/limit, kaminari 미도입).
  def index
    @page = params.fetch(:page, 1).to_i.clamp(1, 500)
    @category = params[:category].in?(BlogPost.categories.keys) ? params[:category] : nil
    @total = BlogPost.published_now.with_category(@category).count
    @posts = BlogPost.published_now.with_category(@category).ordered
                   .offset((@page - 1) * PAGE_SIZE).limit(PAGE_SIZE)
                   # W-5(05_review) — 목록 썸네일 N+1 제거(SURF-6)
                   .includes(:thumbnail_attachment)
    @has_more = @total > @page * PAGE_SIZE
  end

  # BLOG-1 — 슬러그 조회. 미발행·미존재 404. 이전 슬러그면 blog_slug_redirects로 301 대응.
  def show
    @post = BlogPost.published_now.find_by(slug: params[:slug])
    return redirect_moved_slug unless @post

    @toc = BlogPosts::RenderService.parse_toc(@post.body_html)
    # W-5(05_review) — 관련 글 썸네일 N+1 제거
    @related = BlogPost.published_now.with_category(@post.category).where.not(id: @post.id)
                   .ordered.limit(3).includes(:thumbnail_attachment)
  end

  private

  # BLOG-1 — 구 슬러그 301(영구 이동). 이동 기록이 없거나 대상이 비공개·미발행이면 404.
  def redirect_moved_slug
    redirect = BlogSlugRedirect.find_by(old_slug: params[:slug])
    return head :not_found unless redirect

    target = redirect.blog_post
    return head :not_found unless BlogPost.published_now.exists?(id: target.id)

    redirect_to blog_post_path(slug: target.slug), status: :moved_permanently
  end
end

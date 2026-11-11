# BLOG-2 — /sitemap.xml. 게시글(published만)·카테고리 경로 자동 반영, lastmod는 updated_at.
# XML 조립은 컨트롤러에서 문자열로 — loc 값은 서버 생성(slug 형식 검증값)·xml_escape만 적용.
class SitemapsController < ApplicationController
  include AllowAllBrowsers
  allow_unauthenticated_access

  def show
    posts = BlogPost.published_now.ordered.limit(1_000)
    today = Time.current.strftime("%Y-%m-%d")
    static_urls = [ root_url, blog_url ] +
                  BlogPost.categories.keys.map { |key| blog_category_url(key) }

    xml = +<<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    XML
    static_urls.each do |url|
      xml << entry(url, today)
    end
    posts.each do |post|
      xml << entry(blog_post_url(slug: post.slug), post.updated_at.strftime("%Y-%m-%d"))
    end
    xml << "</urlset>\n"
    render xml: xml
  end

  private

  def entry(loc, lastmod)
    "  <url><loc>#{CGI.escapeHTML(loc)}</loc><lastmod>#{lastmod}</lastmod></url>\n"
  end
end

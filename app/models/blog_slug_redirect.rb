# BLOG-1 — 슬러그 변경 시 이전 경로 301 대응 테이블. 조회는 BlogSlugRedirectsService 없이
# BlogController에서 단일 조회(old_slug 고유 인덱스)로 처리한다.
class BlogSlugRedirect < ApplicationRecord
  belongs_to :blog_post

  validates :old_slug, presence: true, uniqueness: true
end

# BLOG-1~5(ADMIN-10) — 블로그 코어 2테이블.
# blog_posts: 마크다운 원문(body_md)과 sanitize 후 렌더 결과(body_html)를 별도 저장(Q18) —
# 요청 시 재렌더를 피해 SURF-6 예산을 지킨다. AS 첨부(thumbnail·og_image)는 티켓 이미지로
# 도입된 기존 Active Storage 테이블을 재사용하므로 신규 마이그레이션 불요.
# blog_slug_redirects: 슬러그 변경 시 이전 경로 301 대응(BLOG-1).
class CreateBlogPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :blog_posts do |t|
      t.references :admin, null: false, foreign_key: true       # 작성자(AUTH-7 계정)
      t.string :title, null: false
      t.string :slug, null: false                               # 소문자 영숫자+하이픈(BLOG-1)
      t.text :body_md, null: false                              # 마크다운 원문
      t.text :body_html, null: false                            # kramdown+sanitize 렌더 결과
      t.integer :category, null: false, default: 0              # Q19 5클러스터 고정 enum
      t.string :tags                                            # 쉼표 구분 자유 태그(Q19)
      t.integer :status, null: false, default: 0                # draft/scheduled/published/private
      t.datetime :publish_at                                    # 예약 발행 시각(null=수동)
      t.datetime :published_at                                  # 실제 발행 시각
      t.string :meta_title                                      # BLOG-2 SEO 메타
      t.string :meta_description
      t.text :summary                                           # 목록 요약(null=본문 선두 150자)
      t.timestamps
    end
    add_index :blog_posts, :slug, unique: true
    add_index :blog_posts, [ :status, :published_at ]

    create_table :blog_slug_redirects do |t|
      t.string :old_slug, null: false
      t.references :blog_post, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :created_at, null: false                       # 만 — 조회 로그 불요
    end
    add_index :blog_slug_redirects, :old_slug, unique: true
  end
end

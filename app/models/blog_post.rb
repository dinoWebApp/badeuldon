# ADMIN-10·BLOG-5 — 관리자 발행 블로그 게시글(Q18 마크다운 원문+렌더 결과 별도 저장,
# Q19 5클러스터 고정 카테고리·태그 자유). 공개 표면(/blog)은 published만 노출하며
# 예약 발행(publish_at)은 시각 경과 후 노출된다(BLOG-3).
class BlogPost < ApplicationRecord
  belongs_to :admin

  has_one_attached :thumbnail   # 발행 필수(BLOG-5 — 목록 대표 이미지)
  has_one_attached :og_image    # 발행 필수(BLOG-5 — SNS 공유 미리보기)
  has_many :slug_redirects, class_name: "BlogSlugRedirect", dependent: :destroy

  # Q19 — LP-11 5클러스터 고정 enum(카테고리 재편은 enum 확장으로만 — 재번호 금지).
  enum :category, { scripts: 0, recovery: 1, docs: 2, tax: 3, stories: 4 }, default: :scripts
  # BLOG-5 — draft(초안)/scheduled(예약)/published(공개)/hidden(비공개 전환).
  # [지시서 해석치환] 지시어 private은 Active Record enum 클래스 메서드 충돌(실측 ArgumentError)
  # 로 값명만 hidden으로 대체 — DB 정수값 3은 동일하다.
  enum :status, { draft: 0, scheduled: 1, published: 2, hidden: 3 }, default: :draft,
       validate: true

  # BLOG-1 — 소문자 영숫자+하이픈(한글 슬러그 금지 — URL 공유·SEO 안정성)
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  SUMMARY_LENGTH = 150

  validates :title, presence: true
  validates :body_md, presence: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: SLUG_FORMAT, message: "는 소문자 영숫자와 하이픈(-)만 사용할 수 있습니다" }
  validates :meta_title, :meta_description, length: { maximum: 255 }

  # 본문 변경 시마다 kramdown+sanitize 재렌더(BLOG-5 — 렌더 결과 DB 저장·요청 시 재렌더 금지)
  before_save :render_body
  # BLOG-1 — 슬러그 변경 시 이전 경로를 301 리다이렉트 테이블에 기록(공개 URL 영속성).
  before_update :record_slug_redirect, if: :slug_changed?

  # BLOG-5 — 슬러그 자동 생성. 제목 파라미터화(한글 제목은 라틴 전환 불가 — Q18 해석:
  # 빈 값이면 post-{epoch} 폴백)·중복 시 -2, -3 접미. 저장된 값은 반환.
  def generate_slug!
    return slug if slug.present?

    base = title.to_s.parameterize.presence || "post-#{Time.current.to_i}"
    candidate = base
    suffix = 1
    while self.class.exists?(slug: candidate)
      suffix += 1
      candidate = "#{base}-#{suffix}"
    end
    self.slug = candidate
  end

  scope :ordered, -> { order(published_at: :desc, id: :desc) }

  # BLOG-3 — 공개 노출 대상. published 상태 && (수동 발행 또는 예약 시각 경과).
  # [W-3(05_review) 정정] scheduled 상태 게시글은 예약 스캔 잡(PublishScheduledJob —
  # Q20 매분)이 상태를 published로 전환한 뒤에야 노출된다 — 잡 지연 시 최대 1분 유예
  # (안전 방향). 이 scope 자체는 시각만 경과해도 scheduled를 노출하지 않는다.
  scope :published_now, lambda {
    where(status: :published)
      .where("publish_at IS NULL OR publish_at <= ?", Time.current)
  }

  scope :with_category, ->(key) { where(category: key) if key.in?(categories.keys) }

  # 발행 가능 여부 검증 — AS 첨부·메타 2종 포함(BLOG-5 필수 필드). errors 채우고 true/false.
  # 상태 전이 자체는 publish!가 담당한다.
  def publishable?
    errors.clear
    errors.add(:title, :blank) if title.blank?
    errors.add(:slug, :blank) if slug.blank?
    errors.add(:body_md, :blank) if body_md.blank?
    errors.add(:thumbnail, :blank) unless thumbnail.attached?
    errors.add(:og_image, :blank) unless og_image.attached?
    errors.add(:meta_title, :blank) if meta_title.blank?
    errors.add(:meta_description, :blank) if meta_description.blank?
    errors.empty?
  end

  # 즉시 발행 — published_at을 기록(KST, TIME-1). 이미 공개면 멱등(nop). true/false 반환.
  def publish!
    return true if published?
    return false unless publishable?

    update(status: :published, published_at: published_at.presence || Time.current)
  end

  # 예약 발행 — publish_at 필수. [W-2(05_review)] 파싱 불가 문자열은 errors.add로 거부해
  # "status=scheduled + publish_at=nil 좀비 예약"을 방지한다. 과거 시각은 즉시 노출을
  # 의미(관리자 의도 존중 — Job이 다음 스캔에서 published 전환)로 허용한다.
  def schedule!(at)
    if at.blank?
      errors.add(:publish_at, :blank)
      return false
    end
    parsed = Time.zone.parse(at.to_s)
    if parsed.nil?
      errors.add(:publish_at, :invalid)
      return false
    end
    update(status: :scheduled, publish_at: parsed)
  end

  # 비공개 전환(BLOG-5) — 공개 URL은 404, 슬러그 리다이렉트는 유지된다.
  def unpublish!
    update(status: :hidden)
  end

  # BLOG-4 — 목록 요약(null이면 본문 선두 150자 — 마크다운 기호 제거 후).
  def display_summary
    return summary if summary.present?

    plain = body_md.gsub(/[#*_>`\[\]()!-]/, " ").squish
    plain.length > SUMMARY_LENGTH ? "#{plain.first(SUMMARY_LENGTH)}…" : plain
  end

  # 발행일 표기 — 예약·즉시 공통으로 published_at(실제 발행 시각) 기준.
  def display_published_at
    published_at || publish_at
  end

  private

  def record_slug_redirect
    return if slug_was.blank?

    BlogSlugRedirect.find_or_create_by!(old_slug: slug_was, blog_post_id: id)
  end

  def render_body
    result = BlogPosts::RenderService.call(body_md.to_s)
    self.body_html = result.html
    @toc = result.toc
  end
end

# BLOG-5(Q18) — 블로그 본문 렌더 파이프라인. 마크다운 원문 → kramdown → Rails HTML5
# sanitizer allowlist(XSS 방어 — REM 금지 표현 필터와 무관) → h2/h3 앵커 id 부여 + 목차 추출.
# 결과 body_html은 DB 저장(요청 시 재렌더 방지 — SURF-6), 수정 시 재렌더된다.
module BlogPosts
  class RenderService
    # sanitize allowlist(02 확정 해석 2) — 화이트리스트 외 태그·속성은 전부 제거.
    # 속성은 태그별 해시 대신 flat 배열(rails-html-sanitizer HTML5 스크ubber 실측 —
    # 해시 키를 무시하며 flat 배열만 인정)로 a·img 공용 속성만 허용한다.
    ALLOWED_TAGS = %w[
      p h1 h2 h3 h4 h5 h6 ul ol li a strong em code pre blockquote
      img table thead tbody tr th td hr br figure figcaption span del
    ].freeze
    ALLOWED_ATTRIBUTES = %w[class id href target rel src alt title datetime].freeze

    # 목차 앵커 접두어 — kramdown이 자동 생성하는 id와 충돌하지 않도록 별도 형식.
    ANCHOR_PREFIX = "toc-"

    Result = Data.define(:html, :toc)

    # toc 엔트리: [텍스트, 앵커, 레벨(2|3)]
    def self.call(body_md)
      html = sanitize(render_markdown(body_md))
      inject_anchors(html)
    end

    # 기존 렌더 결과(앵커 미부여 포함)에서 목차만 추출 — 뷰·캐시 재계산용.
    def self.parse_toc(body_html)
      body_html.scan(%r{<h([23])[^>]*>(.*?)</h\1>}m).map do |level, inner|
        [ strip_tags(inner), anchor_for(level.to_i, strip_tags(inner)), level.to_i ]
      end
    end

    def self.render_markdown(body_md)
      Kramdown::Document.new(
        body_md,
        auto_ids: false,          # 앵커는 자체 규칙으로 부여(ANCHOR_PREFIX)
        parse_block_html: true,
        entity_output: :as_char
      ).to_html
    end
    private_class_method :render_markdown

    # Rails::HTML5::Sanitizer allowlist — 스크립트·이벤트 핸들러·style은 정의상 제거된다.
    def self.sanitize(html)
      Rails::HTML5::Sanitizer.safe_list_sanitizer.new.sanitize(
        html, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES
      )
    end
    private_class_method :sanitize

    # sanitize 통과 HTML에 h2/h3 앵커 id를 부여하고 목차 Result를 반환한다.
    def self.inject_anchors(html)
      toc = []
      counters = Hash.new(0)
      html = html.gsub(%r{<h([23])([^>]*)>(.*?)</h\1>}m) do
        level = Regexp.last_match(1).to_i
        attrs = Regexp.last_match(2)
        content = Regexp.last_match(3)
        text = strip_tags(content)
        anchor = anchor_for(level, text, counters)
        toc << [ text, anchor, level ]
        "<h#{level} id=\"#{anchor}\"#{attrs}>#{content}</h#{level}>"
      end
      Result.new(html, toc)
    end
    private_class_method :inject_anchors

    def self.anchor_for(level, text, counters = Hash.new(0))
      slug = text.strip.gsub(%r{[^\p{Word}]+}, "-").delete_prefix("-").delete_suffix("-").presence
      slug ||= "section"
      counters[level] += 1
      "#{ANCHOR_PREFIX}#{slug}-#{counters[level]}"
    end
    private_class_method :anchor_for

    def self.strip_tags(html)
      Rails::HTML5::Sanitizer.full_sanitizer.new.sanitize(html)
    end
    private_class_method :strip_tags
  end
end

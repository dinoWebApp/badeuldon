# BLOG — 블로그 표현 로직 헬퍼(Q19 카테고리 라벨·BLOG-5 상태 라벨). 뷰 표현 3줄+ 이관.
# Admin 뷰(admin/blog_posts)에서도 helper :all로 공유된다(Admin 모델 네임스페이스 충돌 회피 —
# Admin::NoticesController 선례). 쿼리를 수행하지 않는 인자 기반 표현 함수만 둔다.
module BlogHelper
  # W-6(05_review) — 뷰의 BlogPost.categories.keys 호출을 대체하는 헬퍼 상수
  # (뷰는 모델 클래스 메서드를 호출하지 않는다 — AGENTS 코딩 컨벤션).
  CATEGORY_KEYS = BlogPost.categories.keys.freeze

  # W-6 잔존 해소(admin/blog_posts/index 필터 select) — 뷰는 모델 클래스 메서드를
  # 호출하지 않는다(AGENTS 코딩 컨벤션). CATEGORY_KEYS와 동일 패턴.
  STATUS_KEYS = BlogPost.statuses.keys.freeze

  CATEGORY_LABELS = {
    "scripts" => "독촉·수금 시나리오",
    "recovery" => "미수금·내용증명",
    "docs" => "청구서·양식",
    "tax" => "프리랜서 세금",
    "stories" => "수금 사례"
  }.freeze

  # LP-11 허브 — 5클러스터 카테고리 카드의 1줄 설명(BLOG-3 목록 필터와 동일 enum 소스)
  CATEGORY_DESCRIPTIONS = {
    "scripts" => "상황별 독촉·수금 메시지 시나리오와 실전 문해",
    "recovery" => "미수금 발생 후 대응 절차와 내용증명 가이드",
    "docs" => "바로 쓰는 청구서 양식과 작성 요령",
    "tax" => "프리랜서 부가세·종합소득세 수금·신고 기초",
    "stories" => "실제 수금에 성공한 프리랜서 사례 모음"
  }.freeze

  STATUS_LABELS = {
    "draft" => "초안",
    "scheduled" => "예약",
    "published" => "공개",
    "hidden" => "비공개"
  }.freeze

  def category_label(key)
    CATEGORY_LABELS.fetch(key, key)
  end

  # LP-11 허브 — 카테고리 카드 1줄 설명(쿼리 없는 인자 기반 표현 함수)
  def category_description(key)
    CATEGORY_DESCRIPTIONS.fetch(key, "")
  end

  def status_label(key)
    STATUS_LABELS.fetch(key, key)
  end
end

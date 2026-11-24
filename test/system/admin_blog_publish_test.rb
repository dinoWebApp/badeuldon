require "application_system_test_case"

# ADMIN-10·BLOG-5·B-1 — 실브라우저 발행 E2E(05_review 인계 최우선 항목).
# IntegrationTest의 직접 attach로는 multipart 폼 계약(enctype·file_field)을 못 본다:
# 관리자 2FA 실로그인 → 블로그 신규 폼에 제목·한글 마크다운 본문·메타 2종·썸네일/OG
# fixture PNG 첨부 → 생성 303 → 발행(필수 충족) → 공개 /blog/:slug 실렌더
# (한글 본문·OG 메타 태그·썸네일 img)까지 브라우저 레벨로 검증한다.
class AdminBlogPublishTest < ApplicationSystemTestCase
  fixtures :admins

  BODY_MD = <<~MD
    # 프리랜서 미수금 대응 가이드

    독촉이 어려울 때는 **서비스 명의** 리마인더를 활용하세요.
    자세한 절차는 [도구](/tools) 페이지를 참고하세요.
  MD

  test "관리자가 블로그 글을 파일 첨부와 함께 생성·발행하면 공개 /blog/:slug에 렌더된다 (B-1·BLOG-2·4·5)" do
    setup_admin_totp_secrets

    # ① 관리자 2단계 실로그인(AUTH-7.1)
    visit new_admin_session_path
    fill_in "이메일", with: admins(:ops).email
    fill_in "비밀번호", with: "password"
    submit_and_await_navigation(admin_session_path)
    fill_in "인증 코드", with: totp_code(admins(:ops).otp_secret)
    submit_and_await_navigation(totp_verify_admin_session_path)
    assert_text "관리자로 로그인되었습니다." # /admin 대시보드 도달

    # ② 신규 폼 작성 — multipart 필드 2종 실첨부.
    # 목록에서 click_link는 chromedriver 합성 클릭이 간헐 드롭되어(CI 1fbbd8d 실측·
    # ApplicationSystemTestCase §7 변주) 폼 미발견 플레이크 — 신규 경로 직접 내비게이션으로 고정
    visit new_admin_blog_post_path
    assert_selector "form[method=post][enctype='multipart/form-data']"

    fill_in "blog_post_title", with: "미수금 대응 가이드"
    fill_in "blog_post_body_md", with: BODY_MD
    fill_in "blog_post_meta_title", with: "미수금 대응 가이드 | 받을돈"
    fill_in "blog_post_meta_description", with: "프리랜서 미수금 발생 시 단계별 대응 절차 정리"
    select "청구서·양식", from: "blog_post_category"
    attach_file "blog_post_thumbnail", Rails.root.join("test/fixtures/files/sample.png")
    attach_file "blog_post_og_image", Rails.root.join("test/fixtures/files/sample.png")

    # 제출 직후 DB를 읽지 않는다 — 리다이렉트까지 마무리된 뒤 읽는다(사연은 await_state·
    # submit_and_await_navigation 주석).
    submit_and_await_navigation(admin_blog_posts_path)
    post = BlogPost.order(:id).last
    assert_equal "미수금 대응 가이드", post.title
    assert_match(/\A[a-z0-9-]+\z/, post.slug)
    assert_equal "draft", post.status
    assert post.thumbnail.attached?, "브라우저 multipart 전송으로 썸네일이 첨부되어야 한다"
    assert post.og_image.attached?, "브라우저 multipart 전송으로 OG 이미지가 첨부되어야 한다"

    visit edit_admin_blog_post_path(post)
    assert_text "첨부됨: sample.png" # edit 화면 첨부 표시(B-1)

    # ③ 발행 — 필수 충족이므로 성공해야 한다(BLOG-5). button_to 폼을 action 특정 네이티브 제출
    visit admin_blog_posts_path
    submit_form_of(publish_admin_blog_post_path(post))
    # 생성 단계와 같은 이유 — 발행 요청 처리가 확정된 뒤 상태를 읽는다.
    await_state("게시글 발행 상태 전환") { post.reload.published? }
    assert_equal "published", post.reload.status
    assert post.published_at.present?

    # ④ 공개 표면 실렌더(BLOG-2·4 — 한글 본문·OG 메타·썸네일)
    visit blog_post_path(slug: post.slug)
    assert_text "프리랜서 미수금 대응 가이드"
    assert_text "독촉이 어려울 때는"

    og_title = all("meta[property='og:title']", visible: false).first[:content]
    assert_equal "미수금 대응 가이드 | 받을돈", og_title
    og_image = all("meta[property='og:image']", visible: false).first[:content]
    assert og_image.present?, "og:image 메타가 첨부 이미지 URL을 가리켜야 한다"

    # 썸네일 img는 목록(/blog) 카드에서 렌더된다(BLOG-3 목록 항목 — 상세엔 없음)
    visit blog_path
    assert_selector "img[alt='#{post.title}']" do |img|
      assert_match(%r{#{post.thumbnail.filename}}, img[:src])
    end
  end

  private

  # action이 url과 일치하는 form을 네이티브 제출한다(풀 내비게이션 — Turbo 경합 제거).
  # chromedriver 합성 클릭이 세션 상태에 따라 submit 이벤트를 드롭하는 실측
  # (ApplicationSystemTestCase §7)의 변주가 dom_click에서도 간헐 재현되어 네이티브로
  # 고정하되, admin 레이아웃의 "로그아웃" button_to 폼이 콘텐츠 폼보다 DOM 앞에 있으므로
  # querySelector('form')은 로그아웃 DELETE를 날린다(실측 버그) — action 일치로 특정한다.
  def submit_form_of(url)
    page.execute_script(
      "document.querySelector('form[action=\"' + arguments[0] + '\"]').submit()", url
    )
  end

  # 네이티브 제출 뒤 화면이 바뀔 때까지 기다린다(2026-11-24 실측). 제출 응답이 리다이렉트인
  # 폼에서 제출 직후 노드를 읽으면 내비게이션 진행 중이라 Chrome 158 이 "unhandled inspector
  # error: Node with given id does not belong to the document"(UnknownError)를 내고, Capybara 는
  # StaleElementReferenceError 만 재시도하므로 이 변형은 그대로 실패한다(로컬 32회 중 1회·원격 CI
  # 간헐). 화면 단정(assert_text)보다 먼저 주소가 바뀌기를 기다린다. 리다이렉트 뒤 로딩 중이어도
  # 이후 fill_in·assert_text 는 Capybara 대기로 처리된다.
  # 같은 주소로 돌아오는 폼(발행 — 목록 → 목록)에는 쓸 수 없으므로 그곳은 await_state 로 상태를 기다린다.
  def submit_and_await_navigation(url)
    from_path = page.current_path
    submit_form_of(url)
    await_state("화면 전환") { page.current_path != from_path }
  end

  # 요청 처리 확정 대기(2026-11-24 실측). 네이티브 폼 제출(form.submit())은 응답 완료를 기다리지
  # 않는다 — 제출 직후 DB를 읽으면 요청이 끝나기 전에 읽혀 nil이 된다("undefined method 'title'
  # for nil": 로컬 10회 중 6회·원격 CI 간헐 실패). 화면 단정(assert_text)은 Capybara가 알아서
  # 재시도하지만 DB 읽기는 재시도가 없어, 조건이 참이 될 때까지 Capybara 대기 시간만큼 폴링한다.
  # 시간 초과 시 현재 화면 주소와 표시 내용(flash 안내)과 함께 실패시켜 원인 분류가 가능하게 한다
  # (예: 발행 검증 실패는 수정 화면 + alert 으로 돌아온다).
  def await_state(description)
    deadline = Time.now + Capybara.default_max_wait_time
    until yield
      flunk "#{description} — #{Capybara.default_max_wait_time}초 내에 확정되지 않았습니다. " \
            "현재 화면: #{page.current_url} / 표시 내용: #{visible_text_snippet}" if Time.now >= deadline
      sleep 0.05
    end
  end

  def visible_text_snippet
    page.find("body", wait: 0).text.squish[0, 400]
  rescue Capybara::CapybaraError
    "(화면을 읽지 못했습니다)"
  end
end

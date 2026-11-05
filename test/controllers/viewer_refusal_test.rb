require "test_helper"
require_relative "../test_helpers/fake_solapi_client"
require_relative "../test_helpers/solapi_stubbing"

# 표면 ③ 수신 거부 접수 경로(F-REM — VIEW-7·PROMISE-2·P4) — 뷰어 POST(kind=refusal)의
# PRG 전환·거래처 번호 단위 즉시 중단(refused_at 마킹·해당 청구 종결)·U1 통보 인큐
# (noti_refusal)·위조 파라미터 무시·재접수 멱등·접수 후 발송 전면 중단·완료 화면 무결성
# (VIEW-8·SURF-4)·rate_limit(기존 create 경로 재사용). 시나리오 기준: PRD §6.8 VIEW-7·§6.12
# NOTI-1, _workspace/03_implementation.md 3-b VIEW-7 매핑, _workspace/05_review.md §Tester 8.
# 스캔 경로 검증은 DispatchService(client: 주입)으로 실호출 0(REM-10).
class ViewerRefusalTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SolapiStubbing

  fixtures :users, :clients, :invoices, :promises, :subscriptions, :payment_passes

  def setup
    @fake = FakeSolapiClient.new
  end

  test "수신 거부 접수는 refusal_thanks로 PRG 전환하고 거래처 전체 발송을 즉시 중단한다 (VIEW-7)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      assert_enqueued_with job: Reminders::DeliverJob,
                           args: [ invoice.id, "noti_refusal", "user" ] do
        post viewer_promises_path(invoice.token), params: { promise: { kind: "refusal" } }
        assert_response :see_other
        assert_redirected_to viewer_refusal_thanks_path(invoice.token)
      end

      follow_redirect!
      assert_response :success
      assert_select "h1", text: "수신 거부가 접수되었습니다."
      # P1 — 중단 사실 명시와 거래 계속 가능 안내(문장은 <br>로 구분된 단락)
      assert_select "p", text: /이 번호로는 이 청구서 관련 안내를 더 이상 보내지 않습니다\./
      assert_select "p", text: /청구서 확인과 입금은 언제든 기존 링크에서 할 수 있습니다\./
    end

    client = invoice.client.reload
    assert client.refused?                                          # 번호 단위 즉시 중단
    assert invoice.reload.sequence_finished?                        # 해당 청구 시퀀스 종결
    promise = invoice.promises.sole
    assert_predicate promise, :refusal?
    assert_nil promise.promised_on                                  # 약속 전이·표기 오염 없음
  end

  test "refusal에 주입된 약속일·메모는 무시된다 (PROMISE-2 — kind별 필드 강제)" do
    invoice = invoices(:delta_issued)

    post viewer_promises_path(invoice.token),
         params: { promise: { kind: "refusal", promised_on: "2026-12-01", memo: "위조 메모" } }
    assert_response :see_other

    promise = invoice.promises.sole
    assert_predicate promise, :refusal?
    assert_nil promise.promised_on
    assert_nil promise.memo
    assert invoice.reload.issued?                                   # mark_promised! 대상 아님
  end

  test "재접수는 refused_at을 갱신하지 않고 이력만 추가된다 (P4·멱등 마킹)" do
    invoice = invoices(:delta_issued)

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      post viewer_promises_path(invoice.token), params: { promise: { kind: "refusal" } }
      first_marked_at = invoice.client.reload.refused_at

      travel 1.day                                                  # 다음날 재접수
      post viewer_promises_path(invoice.token), params: { promise: { kind: "refusal" } }
      assert_response :see_other
      assert_equal first_marked_at, invoice.client.reload.refused_at  # 최초 접수 시각 유지
    end
    assert_equal 2, invoice.promises.refusal.count                  # 이력 보존(P4)
  end

  test "수신 거부 후 자동 스캔은 이 거래처의 어떤 발송도 하지 않는다 (VIEW-7 — 전 청구 차단)" do
    invoice = invoices(:delta_issued)
    other = invoices(:delta_overdue)                                # 같은 거래처(delta_main)
    invoice.client.update_column(:refused_at, Time.zone.parse("2026-10-12 09:00"))

    travel_to(Time.zone.parse("2026-10-14 14:00")) do
      Reminders::DispatchService.new(client: @fake).call
    end

    assert_empty @fake.calls                                        # 스캔 모집합 제외(REM-7·VIEW-7)
    assert_empty MessageLog.where(invoice_id: [ invoice.id, other.id ])
  end

  test "수신 거부 후 수동 발송도 REFUSED 가드로 기록만 남는다 (VIEW-7 — 가드 이중 방어)" do
    invoice = invoices(:delta_issued)
    invoice.client.update_column(:refused_at, Time.zone.parse("2026-10-12 09:00"))

    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      result = Reminders::SendService.new(invoice: invoice, template_key: "confirm_d1",
                                          recipient_role: :debtor, origin: :manual,
                                          client: @fake).call
      assert_equal :skipped, result
    end
    assert_empty @fake.calls
    assert_equal "REFUSED", MessageLog.where(invoice_id: invoice.id).sole.error_code
  end

  test "완료 화면은 VIEW-8을 준수한다 — 링크는 복귀(③→③)뿐이고 noindex다 (SURF-3·4)" do
    invoice = invoices(:delta_issued)

    get viewer_refusal_thanks_path(invoice.token)
    assert_response :success
    assert_select "h1", text: "수신 거부가 접수되었습니다."
    assert_select "a[href]" do |anchors|
      anchors.each { |anchor| assert_match(%r{\A/b/}, anchor[:href]) }  # ③→① 금지
    end
    assert_select "meta[name=robots]" do |metas|
      assert_match(/noindex/, metas.first["content"])
    end
  end

  test "무효 토큰의 수신 거부 완료 화면은 VIEW-6 404로 수렴한다 (토큰 가드 공유)" do
    get viewer_refusal_thanks_path("Z" * 43)
    assert_response :not_found
    assert_select "h1", text: "링크가 만료되었거나 폐기되었습니다."
  end

  test "수신 거부 접수도 응답 경로와 같은 rate_limit(10회/10분)을 공유한다 (PROMISE-2)" do
    @rate_store = ActiveSupport::Cache::MemoryStore.new
    store = @rate_store
    Rails.cache.define_singleton_method(:increment) { |*args, **kwargs| store.increment(*args, **kwargs) }

    invoice = invoices(:delta_issued)
    travel_to(Time.zone.parse("2026-10-14 10:00")) do
      10.times do
        post viewer_promises_path(invoice.token), params: { promise: { kind: "refusal" } }
        assert_response :see_other
      end

      post viewer_promises_path(invoice.token), params: { promise: { kind: "refusal" } }
      assert_response :too_many_requests
    end

    assert_equal 10, invoice.promises.refusal.count
  ensure
    Rails.cache.singleton_class.remove_method(:increment) if Rails.cache.singleton_class.method_defined?(:increment)
  end
end

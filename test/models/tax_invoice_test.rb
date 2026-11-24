require "test_helper"

# TAX-3/4 모델 계층 — 발행 게이트의 단일 판정점·단일 문구 출처를 검증한다.
# - TaxInvoice.feature_enabled? — TAX-4 스위치의 유일한 판정점(config.x만 읽고 ENV을 직접
#   읽지 않는다 — 초기자 단위 테스트가 ENV 파싱을 담당한다).
# - TaxInvoice::FEATURE_DISABLED_NOTICE — 꺼짐 안내 문구의 단일 출처(패널·플래시·pending
#   주문 차단이 이 상수를 쓰는 것은 컨트롤러 테스트가 검증한다).
# - User#tax_invoice_eligible? / #tax_invoice_ineligibility_notice — TAX-3 발급 자격 판정과
#   안내 문구의 단일 출처(UserTest가 아닌 TAX 도메인 관점에서 여기서 검증한다 — 패널·플래시·
#   설정 화면·서비스 예외가 같은 메서드를 쓰는지는 각 계층 테스트가 문구 일치로 확인한다).
class TaxInvoiceTest < ActiveSupport::TestCase
  # ── TAX-4 — 스위치 단일 판정점 ──
  test "feature_enabled?는 config 값을 그대로 반영한다 (TAX-4 — 모델이 ENV을 직접 읽지 않는다)" do
    with_tax_invoice_feature(true) do
      assert_predicate TaxInvoice, :feature_enabled?
    end

    with_tax_invoice_feature(false) do
      assert_not_predicate TaxInvoice, :feature_enabled?
    end
  end

  test "ENV이 true여도 config가 꺼짐이면 꺼짐이다 — 판정은 config 한 곳만 본다 (TAX-4)" do
    ENV["TAX_INVOICE_ENABLED"] = "true"

    with_tax_invoice_feature(false) do
      assert_not_predicate TaxInvoice, :feature_enabled?
    end
  ensure
    ENV.delete("TAX_INVOICE_ENABLED")
  end

  test "FEATURE_DISABLED_NOTICE 상수는 꺼짐 문구의 단일 출처다 (리뷰 W-2)" do
    assert_equal "전자세금계산서 발행은 현재 준비 중입니다.", TaxInvoice::FEATURE_DISABLED_NOTICE
  end

  # ── TAX-3 — 발급 자격 판정(Q25 — general만 발급) ──
  test "일반과세 사용자는 발급 자격이 있다 (TAX-3 정상)" do
    user = users(:delta)                                      # 기본값 general
    assert_predicate user, :tax_invoice_eligible?
  end

  test "간이과세 사용자는 발급 자격이 없다 (TAX-3 예외)" do
    user = users(:delta)
    user.tax_type = :simplified

    assert_not_predicate user, :tax_invoice_eligible?
  end

  test "면세사업자 사용자는 발급 자격이 없다 (TAX-3 예외)" do
    user = users(:delta)
    user.tax_type = :exempt

    assert_not_predicate user, :tax_invoice_eligible?
  end

  # ── TAX-3 — 안내 문구 단일 출처(리뷰 W-4 — 서비스 기준 문언) ──
  test "간이과세 안내 문구는 서비스 기준 문언에 세무 확인 고지를 포함한다 (TAX-3·LP-12)" do
    user = users(:delta)
    user.tax_type = :simplified
    notice = user.tax_invoice_ineligibility_notice

    assert_match(/받을돈에서는 간이과세자의 전자세금계산서 발급을 지원하지 않습니다/, notice)
    assert_match(/세무사에게 확인/, notice)
  end

  test "면세사업자 안내 문구는 서비스 기준 문언이다 (TAX-3·LP-12)" do
    user = users(:delta)
    user.tax_type = :exempt
    notice = user.tax_invoice_ineligibility_notice

    assert_match(/받을돈에서는 면세사업자의 전자세금계산서 발급을 지원하지 않습니다/, notice)
    assert_no_match(/간이과세/, notice)                        # 과세 유형별 문구 분리
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/admin_session_test_helper"
require_relative "test_helpers/sales_session_test_helper"
require_relative "test_helpers/memory_rate_limit_helper"
require_relative "test_helpers/tax_invoice_feature_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    include TaxInvoiceFeatureHelper

    # TAX-4 — 테스트 환경은 운영 준비 게이트 스위치를 기본 켬으로 둔다(기존 세금계산서 테스트
    # 대부분의 전제 — 03_implementation §스위치 사용법). 꺼짐이 필요한 케이스는
    # with_tax_invoice_feature(false) 블록으로 격리하고, teardown에서 부팅 값으로 복원해
    # 테스트 간 누수를 막는다(fail-closed 기본값 검증은 초기자 단위 테스트가 담당한다).
    setup do
      @__original_tax_invoice_enabled = Rails.application.config.x.tax_invoice_enabled
      Rails.application.config.x.tax_invoice_enabled = true
    end

    teardown do
      Rails.application.config.x.tax_invoice_enabled = @__original_tax_invoice_enabled
    end

    # Run B(ADMIN) 신규 테스트 전용 — fixtures 사용자의 자식 행을 FK 역순으로 정리해
    # User.delete_all 기반 시드 델타 검증을 가능하게 한다(공유 헬퍼 — 기존 스위트 미사용).
    def clear_domain_tables
      ViewEvent.delete_all
      MessageLog.delete_all
      Promise.delete_all
      Payment.delete_all
      InvoiceItem.delete_all
      Invoice.delete_all
      Item.delete_all
      Client.delete_all
      PaymentPass.delete_all
      Order.delete_all
      Subscription.delete_all
      Session.delete_all
    end
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/admin_session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

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

require "test_helper"
require_relative "../../test_helpers/fake_solapi_client"
require_relative "../../test_helpers/solapi_stubbing"
require_relative "../../test_helpers/reminder_factories"

# NOTI-2 주간 다이제스트(T7 — 2026-11-16 확정) 테스트 — 월요일 09:00 KST recurring 진입점,
# 집계(직전 7일 — 만기·약속·수금 3지표·타 사용자 미포함), NO_TEMPLATE skipped 기록
# (NOTI-3 선례 — 솔라피 실호출 0건 단정), 주 단위 결정적 키 멱등(SEC-5), 대상 필터
# (토글 off·suspended·전화번호 부재), 토글 저장 경로 303/422(C-3 회귀 포함).
# 시나리오 기준: _workspace/parallel/T7/03_implementation.md·05_review.md Tester 지시 4·8번.
class Noti::WeeklyDigestTest < ActionDispatch::IntegrationTest
  include SolapiStubbing

  fixtures :users, :clients, :invoices, :promises

  NO_TEMPLATE = Solapi::ApiError.new(status: 400, code: "MISSING_TEMPLATE",
                                     message: "템플릿을 찾을 수 없습니다")

  def no_template_client
    FakeSolapiClient.new(raise_on: { "noti2_weekly_digest" => NO_TEMPLATE })
  end

  # 2026-11-16 = 월요일(TIME-1 KST) — period_start는 지난주 월 00:00(2026-11-09).
  def digest_log(user = users(:gamma))
    MessageLog.find_by(user_id: user.id, template_key: "noti2_weekly_digest",
                       scheduled_at: Time.zone.parse("2026-11-09 00:00"))
  end

  # ── 서비스 — NO_TEMPLATE skip·멱등 ──

  test "템플릿 미등록 상태의 발송은 skipped(NO_TEMPLATE)로 기록되고 솔라피 성공 호출이 없다 (NOTI-3 선례)" do
    fake = no_template_client
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      result = Noti::WeeklyDigestService.new(user: users(:gamma), client: fake).call

      assert_equal :skipped, result
      log = digest_log(users(:gamma))
      assert_not_nil log
      assert_predicate log, :skipped?
      assert_equal "NO_TEMPLATE", log.error_code
      assert_predicate log, :digest?                      # digest=true — 단일_subject 면제 기록
      assert_nil log.invoice_id                           # 사용자 레벨 발송 — 청구서 비귀속
      assert_empty fake.successful_calls                  # 솔라피 성공 호출 0건 단정(NO_TEMPLATE은 호출 기록만)
    end
  end

  test "같은 주 키 재실행은 duplicate로 흡수되고 MessageLog 누적이 없다 (SEC-5·주 단위 결정적 키)" do
    fake = no_template_client
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      Noti::WeeklyDigestService.new(user: users(:gamma), client: fake).call

      assert_no_difference -> { MessageLog.count } do
        assert_equal :duplicate,
                     Noti::WeeklyDigestService.new(user: users(:gamma), client: fake).call
      end
      assert_empty fake.successful_calls                  # 재실행도 성공 발송 없음
    end
  end

  test "전화번호가 없는 사용자는 NO_PHONE skipped로 기록된다 (발송 시도 전 가드)" do
    users(:gamma).update_columns(phone: nil)
    fake = no_template_client
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      assert_equal :skipped, Noti::WeeklyDigestService.new(user: users(:gamma), client: fake).call

      assert_equal "NO_PHONE", digest_log.reload.error_code
      assert_empty fake.calls
    end
  end

  # ── 집계(직전 7일) ──

  test "집계는 직전 7일의 만기·약속·수금을 3지표로 조립하고 타 사용자 청구를 포함하지 않는다" do
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      delta = users(:delta)
      delta_invoice = invoices(:delta_issued)             # 만기 2026-10-01 — 기간 밖
      delta_invoice.update_columns(due_on: Date.new(2026, 11, 12))     # 기간 내 만기 도래
      # 약속 등록(기간 내 created_at) — kind this_week(약속대기 진입 원인 — INV-4)
      delta_invoice.promises.create!(kind: :this_week, created_at: Time.zone.parse("2026-11-11 10:00"))
      # refusal은 약속이 아니다 — 집계 제외
      delta_invoice.promises.create!(kind: :refusal, created_at: Time.zone.parse("2026-11-11 11:00"))
      # 수금 완료(기간 내 paid_on) — 부분입금도 실입금으로 합산
      delta_invoice.payments.create!(amount: 30_000, paid_on: Date.new(2026, 11, 10))
      delta_invoice.payments.create!(amount: 20_000, paid_on: Date.new(2026, 11, 12))

      # variables는 skipped 기록에 함께 남는다 — MessageLog.variables로 검증한다
      Noti::WeeklyDigestService.new(user: delta, client: no_template_client).call
      variables = digest_log(delta).reload.variables

      assert_equal "1", variables["만기건수"]              # delta_issued 1건(기간 내 due_on)
      assert_equal "220,000", variables["만기금액"]
      assert_equal "1", variables["약속건수"]              # refusal 제외
      assert_equal "2", variables["수금건수"]
      assert_equal "50,000", variables["수금금액"]
      assert_equal "델타디자인", variables["발행인명"]
      # 소유권 격리 — gamma의 데이터가 delta 집계에 섞이지 않는다(gamma는 청구서 0건)
      Noti::WeeklyDigestService.new(user: users(:gamma), client: no_template_client).call
      gamma_variables = digest_log.reload.variables
      assert_equal "0", gamma_variables["만기건수"]
      assert_equal "0", gamma_variables["수금건수"]
    end
  end

  test "기간 경계 — 직전 7일 밖의 데이터는 집계되지 않는다" do
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      invoice = invoices(:delta_viewed)                   # 총액 55,000·만기 2026-10-20
      invoice.update_columns(due_on: Date.new(2026, 11, 8))            # 기간 시작(11-09) 이전
      invoice.payments.create!(amount: 10_000, paid_on: Date.new(2026, 11, 8)) # 경계 밖 입금

      Noti::WeeklyDigestService.new(user: users(:delta), client: no_template_client).call
      variables = MessageLog.where(user_id: users(:delta).id,
                                   template_key: "noti2_weekly_digest").sole.variables
      assert_equal "0", variables["만기건수"]
      assert_equal "0", variables["수금건수"]
    end
  end

  # ── 잡 — 대상 필터·에러 격리 ──

  test "잡은 토글 off·정지·전화번호 부재 사용자를 제외하고 나머지를 처리한다 (NOTI-2)" do
    users(:delta).update_columns(noti2_digest_enabled: false)     # 토글 off
    users(:gamma).update_columns(phone: "")                       # 번호 부재

    fake = no_template_client
    travel_to(Time.zone.parse("2026-11-16 09:00")) do
      with_solapi_client(fake) do
        Noti::WeeklyDigestJob.perform_now
      end
    end

    # delta(토글 off)·gamma(번호 부재)는 로그 없음 — 대상 전체를 순회했으므로 로그 총수는
    # phone 보유·토글 on 사용자와 일치한다
    assert_nil MessageLog.find_by(user_id: users(:delta).id, template_key: "noti2_weekly_digest")
    expected = User.active.where(noti2_digest_enabled: true)
                   .where.not(phone: [ nil, "" ]).count
    created = MessageLog.where(template_key: "noti2_weekly_digest").count
    assert_equal expected, created
    assert_operator created, :>=, 1                             # epsilon(번호 보유) 등 최소 1명
  end

  # ── 토글 저장 경로(C-3 회귀 포함) ──

  test "토글 저장 성공은 303으로 리다이렉트되고 값이 반영된다 (NOTI-2 토글)" do
    sign_in_as users(:delta)

    patch app_notification_settings_path, params: { user: { noti2_digest_enabled: "false" } }
    assert_response :see_other
    assert_redirected_to app_profile_path
    assert_not users(:delta).reload.noti2_digest_enabled

    patch app_notification_settings_path, params: { user: { noti2_digest_enabled: "true" } }
    assert_response :see_other
    assert users(:delta).reload.noti2_digest_enabled
  end

  test "토글 저장 실패는 422을 응답하고 500(MissingTemplate)이 아니다 (C-3 회귀)" do
    user = users(:delta)
    # 전역 검증(remind_* — context 없음)이 이상 데이터에서 발동하도록 선주입
    user.update_columns(remind_start_hour: 3)

    sign_in_as user
    patch app_notification_settings_path, params: { user: { noti2_digest_enabled: "false" } }
    assert_response :unprocessable_entity
  end

  test "비인증 토글 저장은 로그인 화면으로 리다이렉트된다 (AUTH 가드)" do
    patch app_notification_settings_path, params: { user: { noti2_digest_enabled: "false" } }
    assert_response :redirect
    assert_redirected_to new_session_path
  end
end

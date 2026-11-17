# NOTI-2 주간 다이제스트 발송(사용자 U1 향) — 매주 월요일 09:00 KST recurring
# (Noti::WeeklyDigestJob)이 사용자 1명분을 처리한다. Tickets::NotifyAnswerService와 같은
# "Reminders::SendService를 재사용하지 않는 전용 경로"다 — SendService의 가드는 invoice
# 문맥(수신거부·보류·종결·시퀀스 상한)에 얽혀 있어 다이제스트(청구서 단위가 아닌 사용자
# 단위 요약)와 결합이 오히려 위험하다. 공유 계약만 준수한다: ① MessageLog 기록(P4 — 모든
# 발신 시도 기록) ② variables 래핑은 Solapi::ClientService 몫 ③ 템플릿 미등록은
# skipped(NO_TEMPLATE) 기록 후 정상 종료(NOTI-3 선례 — 등록 후 코드 변경 없이 자동 활성화).
#
# 집계 정의(확정) — 기간: 실행 시점 기준 직전 7일 [지난주 월요일 00:00 KST, 실행 시각).
#   월요일 아침 발송이므로 "당주 시작~현재"는 0일이어야 해 「직전 7일」을 채택했다(지시서
#   양립 옵션). 3지표 모두 기존 스코프·컬럼 재사용(쿼리 신규 테이블 없음):
#   · 만기 도래 — Invoice.due_within(due_on 기간) — unsettled 한정(기존 스코프 재사용)
#   · 약속 등록 — Promise kind: this_week·date_selected(약속대기 진입 원인 2종 — INV-4)
#     created_at 기간. paid_report·inquiry·refusal은 약속이 아니므로 제외.
#   · 수금 완료 — Payment.paid_on 기간(입금일 기준 — PAY-1 기록일). 부분입금도 실입금이므로
#     포함한다(금액은 입금액 합계).
#
# 멱등(SEC-5 준칙) — MessageLog.scheduled_at에 기간 시작(지난주 월요일 00:00 KST — 주 단위
# 결정적 키)을 저장하고, 같은 (user·template_key·scheduled_at) 이력이 있으면 무조건 skip.
# 잡 재실행·동시 실행 모두 중복 발송 없다(NO_TEMPLATE 기록도 주 1회만 누적 — Reminders
# 선례의 "skipped 슬롯 갱신"과 달리 1회성 기록 후 재기록 없음이 의도다).
module Noti
  class WeeklyDigestService
    # 솔라피 템플릿 키 — ALIMTALK_TEMPLATES.md·credentials solapi.template_ids에 등록 전이며,
    # 등록 전에는 모든 발송이 skipped(NO_TEMPLATE)로 흡수된다(실호출 없음 — 지시서 제약).
    TEMPLATE_KEY = "noti2_weekly_digest"
    # 알림톡 버튼 웹링크 호스트(운영 도메인 — Reminders::SendService::LINK_HOST와 같은 규격).
    LINK_HOST = "badeuldon.kr"

    # client — 솔라피 래퍼 주입 지점(테스트 stub 방어선 — 실호출 금지).
    def initialize(user:, client: nil)
      @user = user
      @client = client
    end

    # 반환: :sent / :failed / :skipped / :duplicate — 모든 시도는 MessageLog에 기록된다(P4).
    def call
      return :duplicate if already_sent_this_week?

      log = MessageLog.create!(invoice_id: nil, ticket_id: nil, digest: true,
                               user_id: @user.id, recipient_role: :user,
                               origin: :auto, template_key: TEMPLATE_KEY,
                               scheduled_at: period_start)

      if @user.phone.blank?
        log.update!(status: :skipped, error_code: "NO_PHONE")
        return :skipped
      end

      # NOTI-3 선례 — credentials에 템플릿 코드가 없으면(등록 전) 솔라피 호출 없이
      # skipped(NO_TEMPLATE)로 기록하고 정상 종료한다. ApiError(MISSING_TEMPLATE)는
      # ClientService가 실제 send 전에 fail-fast로 발생시키므로 이 rescue로 흡수된다.
      response = client.send_alimtalk(template_key: TEMPLATE_KEY, to: @user.phone,
                                      variables: variables)
      log.update!(status: :sent, sent_at: Time.current, phone: @user.phone,
                  variables:, provider_message_id: provider_message_id(response))
      :sent
    rescue Solapi::ApiError => e
      return skip_no_template!(log, e) if e.code == "MISSING_TEMPLATE"

      log.update!(status: :failed, error_code: e.code, error_message: e.message,
                  phone: @user.phone, variables: variables)
      :failed # 주 1회 요약 — 재시도 없음(다음 주 정상 발송이 회복 경로)
    end

    private

    # 주 단위 멱등 키 판정 — 같은 주(같은 period_start)의 기록(sent·skipped·failed 무관)이
    # 있으면 재발송하지 않는다. 재실행·동시 실행 흡수(SEC-5 — 동일 청구(여기선 동일 주기)
    # 1회).
    def already_sent_this_week?
      MessageLog.exists?(user_id: @user.id, template_key: TEMPLATE_KEY,
                         scheduled_at: period_start)
    end

    def skip_no_template!(log, error)
      log.update!(status: :skipped, error_code: "NO_TEMPLATE", error_message: error.message,
                  phone: @user.phone, variables: variables)
      :skipped
    end

    # ── 집계(직전 7일 — 모듈 주석의 정의) ────────────────────────────────────
    def period_start
      @period_start ||= Time.current.beginning_of_week - 7.days # 지난주 월요일 00:00 KST
    end

    def period_end
      Time.current # 월요일 09:00 KST 실행 시각
    end

    # 만기 도래 — 기간 내 due_on 도래 청구(미수 계열 — due_within 스코프가 unsettled 한정).
    def due_invoices
      @due_invoices ||= @user.invoices.due_within(period_start.to_date..period_end.to_date)
    end

    # 약속 등록 — 약속대기 진입 원인 2종(this_week·date_selected). 접수 시각(created_at) 기준.
    def registered_promises
      @registered_promises ||= Promise.where(kind: Promise.kinds.slice(:this_week,
                                                                             :date_selected).values)
                                      .where(created_at: period_start...period_end)
                                      .where(invoice_id: @user.invoices.select(:id))
    end

    # 수금 완료 — 기간 내 입금 기록(입금일 paid_on 기준 — PAY-1). 부분입금 포함 실입금액 합계.
    def payments_in_period
      @payments_in_period ||= Payment.where(invoice_id: @user.invoices.select(:id))
                                     .where(paid_on: period_start.to_date..period_end.to_date)
    end

    # variables 초안(템플릿 등록 전) — ALIMTALK_TEMPLATES.md 등록 시 변수명과 일치시킬 것.
    # 금액은 천단위 콤마 문자열로 조립한다(솔라피 variables는 문자열 치환만 지원).
    # 인스턴스 변수로 승격 — rescue 분기(skip_no_template!·failed)에서도 접근 가능해야
    # 하며(call 지역변수였던 결함 — BUG-4, NO_TEMPLATE 경로 NameError·P4 기록 누락),
    # 집계 쿼리 재실행 방지(멱등 키로 주 1회 실행이 보장되나 방어적 캐시).
    def variables
      @variables ||= build_variables
    end

    def build_variables
      {
        "발행인명" => @user.display_name,
        "기간" => "#{period_start.strftime('%-m/%-d')}~#{period_end.strftime('%-m/%-d')}",
        "만기건수" => due_invoices.count.to_s,
        "만기금액" => ActiveSupport::NumberHelper.number_to_delimited(due_invoices.sum(:total_amount)),
        "약속건수" => registered_promises.count.to_s,
        "수금건수" => payments_in_period.count.to_s,
        "수금금액" => ActiveSupport::NumberHelper.number_to_delimited(payments_in_period.sum(:amount)),
        "url" => LINK_HOST + Rails.application.routes.url_helpers.app_root_path
      }
    end

    def provider_message_id(response)
      response.is_a?(Hash) ? response[:messageId] || response["messageId"] : nil
    end

    def client
      @client ||= Solapi::ClientService.new
    end
  end
end

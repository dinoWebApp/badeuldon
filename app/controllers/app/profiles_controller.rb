# 프로필 설정(AUTH-1.3)·회원 탈퇴(AUTH-1.5). App::BaseController의 프로필 완료 가드를 건너뛴다 —
# 이 화면 자체가 미완료 사용자가 완료해야 할 첫 화면이므로.
class App::ProfilesController < App::BaseController
  skip_before_action :require_complete_profile

  # AUTH-1.5 탈퇴 안내에 미리 보일 현재 상태 요약 — 뷰는 @변수만 소비한다(뷰 쿼리 금지).
  # paid_plus_cancelled는 해지 예약(자동 결제 종료 — PLAN-5) 여부다: 결제 예정 유무로
  # 고지 문구가 갈라진다(W-5).
  WithdrawalSummary = Struct.new(:unsettled_count, :unsettled_balance, :trialing_plus,
                                 :paid_plus_end_on, :paid_plus_cancelled,
                                 :remaining_pass_count, keyword_init: true)

  def edit
    @user = Current.user
    @withdrawal_summary = build_withdrawal_summary
  end

  def update
    @user = Current.user
    @user.assign_attributes(remind_profile_params)
    if @user.save(context: :profile)
      # 완료 후 /app 대시보드로 안내 — welcome 임시 화면은 /app 셸로 대체되어 제거됨(플랜 A-3)
      redirect_to app_root_path, status: :see_other, notice: "프로필 설정이 완료되었습니다."
    else
      @withdrawal_summary = build_withdrawal_summary
      render :edit, status: :unprocessable_entity
    end
  end

  # AUTH-1.5 회원 탈퇴 — 소유권은 Current.user뿐이다(타 회원 지정 불가). 처리는
  # Users::WithdrawalService(이메일 입력 확인·감사 로그·연쇄 삭제)에 위임하고, 성공 시 기존
  # 로그아웃 경로(terminate_session)로 세션을 종료한 뒤 랜딩으로 되돌린다. 실패 시에는
  # 최하단 탈퇴 영역(#withdrawal)으로 되돌려 안내가 바로 보이게 한다(W-3).
  def destroy
    result = Users::WithdrawalService.call(user: Current.user, confirm_email: confirm_email_param,
                                           ip: ClientIp.of(request))
    if result.success?
      terminate_session
      redirect_to root_path, status: :see_other, notice: result.message
    else
      # N-1 — 앵커 복귀 시 상단 alert은 화면 밖이므로 탈퇴 영역 안에도 같은 안내를 실는다
      flash[:withdrawal_error] = result.message
      redirect_to edit_app_profile_path(anchor: "withdrawal"), status: :see_other, alert: result.message
    end
  end

  private

  # AUTH-1.5 확인용 이메일 — 키 자체가 없는 요청(정상 경로 아님)은 params.expect의 400을
  # 유지하고, 빈 값·공백만은 키가 있는 제출(HTML 빈 입력)이므로 서비스의 불일치 가드로
  # 흘려 303 안내로 되돌린다(W-3 — params.expect는 blank에도 ParameterMissing을 던진다).
  def confirm_email_param
    params.key?(:confirm_email) ? params[:confirm_email] : params.expect(:confirm_email)
  end

  def profile_params
    params.expect(user: [ :display_name, :business_type, :bank_name, :account_number, :account_holder, :phone,
                          :remind_start_hour, :remind_end_hour, { remind_allowed_wdays: [] } ])
  end

  # REM-3 발송 요일·시간대 — 요일 체크박스는 배열로 제출되므로 csv 문자열로 변환해 할당한다
  # (DB 컬럼은 string). 허용 값 이외(0·6 — 주말)와 공백은 서버에서 제거해 고정 경계를 이중 보장.
  # 파라미터에 요일 키가 아예 없으면(기존 6필드 폼·타 경로) 덮어쓰지 않는다 — 미전송을
  # ""로 치환하면 최소 1일 검증에 걸려 저장 자체가 불가능해진다(Phase 7 분기 수정).
  def remind_profile_params
    attrs = profile_params
    return attrs unless attrs.key?(:remind_allowed_wdays)

    wdays = Array(attrs.delete(:remind_allowed_wdays)).filter_map do |d|
      d.to_i if d.to_i.between?(1, 5)
    end.uniq
    attrs[:remind_allowed_wdays] = wdays.join(",")
    attrs
  end

  # AUTH-1.5 — 탈퇴 안내의 상태 요약 적재. 미수 잔액은 DASH-1과 같은 계산식(Σ총액 − Σ입금액,
  # F-PAY 재계산 기준)으로 부분입금을 반영한다. 유료 Plus는 주기 종료일이 있는 이용 중 상태
  # (active·cancelled — PLAN-5 해지 잔여 기간 포함), 체험 중(trialing)은 별도 문구다. 잔여
  # 수금 패스는 사용 가능한 패스의 잔여 횟수 합계다(PaymentPass.usable — PLAN-4).
  def build_withdrawal_summary
    unsettled = Current.user.invoices.unsettled
    WithdrawalSummary.new(
      unsettled_count: unsettled.count,
      unsettled_balance: unsettled.sum(:total_amount) - Payment.where(invoice_id: unsettled.select(:id)).sum(:amount),
      trialing_plus: Current.user.subscription&.trialing?,
      paid_plus_end_on: paid_plus_period_end_on,
      paid_plus_cancelled: paid_plus_cancelled?,
      remaining_pass_count: Current.user.payment_passes.usable.sum(:remaining_uses)
    )
  end

  def paid_plus_period_end_on
    subscription = Current.user.subscription
    return unless subscription&.plus? && !subscription.trialing?

    subscription.current_period_end&.to_date
  end

  # 해지 예약(PLAN-5 — 자동 결제는 끝났고 기간 말까지 Plus) 여부. expire!가 plan을 free로
  # 되돌리므로 plus?는 trialing·active·cancelled에서만 참이다.
  def paid_plus_cancelled?
    subscription = Current.user.subscription
    subscription.present? && subscription.plus? && subscription.cancelled?
  end
end

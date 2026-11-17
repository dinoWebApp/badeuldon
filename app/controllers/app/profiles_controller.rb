# 프로필 설정(AUTH-1.3). App::BaseController의 프로필 완료 가드를 건너뛴다 —
# 이 화면 자체가 미완료 사용자가 완료해야 할 첫 화면이므로.
class App::ProfilesController < App::BaseController
  skip_before_action :require_complete_profile

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    @user.assign_attributes(remind_profile_params)
    if @user.save(context: :profile)
      # 완료 후 /app 대시보드로 안내 — welcome 임시 화면은 /app 셸로 대체되어 제거됨(플랜 A-3)
      redirect_to app_root_path, status: :see_other, notice: "프로필 설정이 완료되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

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
end

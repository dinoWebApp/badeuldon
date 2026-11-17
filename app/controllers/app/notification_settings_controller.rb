# 알림 수신 설정(NOTI-2 주간 다이제스트 토글). 프로필 화면의 파셜
# (app/views/app/shared/_noti_digest_setting)이 이 경로로 단독 제출한다 — 프로필 본문
# 필드와 분리된 부분 갱신 경로다(토글 1개 필드만 검증·저장). 성공 303·실패 422(Turbo 규약).
class App::NotificationSettingsController < App::BaseController
  def update
    if Current.user.update(notification_params)
      redirect_to app_profile_path, status: :see_other,
                  notice: "알림 설정이 저장되었습니다."
    else
      # 부분 갱신 대상이 토글 폼 1개뿐이라 뷰 재렌더 없이 422만 응답한다
      # (update 템플릿 부재 — MissingTemplate 500 방지).
      head :unprocessable_entity
    end
  end

  private

  def notification_params
    params.expect(user: [ :noti2_digest_enabled ])
  end
end

# T0 — 선행 결선: /app/profile에 destroy 라우트 추가 (AUTH-1.5)

- 날짜: 2026-11-26
- 범위: `config/routes.rb` 1줄 수정 (다른 파일 변경 없음)

## 변경 내용

`config/routes.rb` — `/app` namespace 내 17행:

```ruby
# 이전
resource :profile, only: %i[ edit update ]  # AUTH-1.3 최초 프로필 설정(/app/profile)

# 이후
resource :profile, only: %i[ edit update destroy ]  # AUTH-1.3 최초 프로필 설정(/app/profile) · AUTH-1.5 회원 탈퇴(DELETE)
```

## 확인

명령: `bin/rails routes -g app/profile`

```
          Prefix Verb   URI Pattern                 Controller#Action
edit_app_profile GET    /app/profile/edit(.:format) app/profiles#edit
     app_profile PATCH  /app/profile(.:format)      app/profiles#update
                 PUT    /app/profile(.:format)      app/profiles#update
                 DELETE /app/profile(.:format)      app/profiles#destroy
```

`DELETE /app/profile → app/profiles#destroy` 등록 확인. 컨트롤러 액션은 아직 없어
현재 시점에서 DELETE 요청은 실패하는 것이 정상이다 — 같은 배치의 후속 태스크(T1 이상)가
`App::ProfilesController#destroy`를 구현한다.

## 미수행 항목 (지시에 따라)

- 컨트롤러·뷰·테스트·문서 생성 없음
- 테스트 미실행(동시 작업 간 테스트 DB 충돌 방지)
- git 조작 없음

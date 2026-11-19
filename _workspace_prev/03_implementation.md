
---

# 병렬 배치 3-S 통합 결선 (2026-11-16 · Developer)

6개 병렬 태스크(A·T3·T5·T6·T7·T8) 완료 후 공유 파일 결선. 각 태스크 03 문서의 3-S 인계 절을 기준으로 수행.

## 1. 통합 마이그레이션 (신규 1개)

`db/migrate/20261116000000_parallel_batch_3s_integration.rb`

| 테이블 | 컬럼/인덱스 | 출처 |
|---|---|---|
| users | `remind_allowed_wdays` string null:false default "1,2,3,4,5" / `remind_start_hour` integer null:false default 9 / `remind_end_hour` integer null:false default 18 | T6 (REM-3) |
| users | `noti2_digest_enabled` boolean null:false default true | T7 (NOTI-2) |
| subscriptions | `dunning_stage` integer null:false default 0 / `next_retry_at` datetime / `last_payment_failed_at` datetime | T5 (PLAN-5) |
| message_logs | `digest` boolean null:false default false | T7 (NOTI-2) |
| view_events | index `[:invoice_id, :ip, :viewed_at]` name `index_view_events_on_invoice_ip_viewed_at` | T3 |

- `payments.note` 미생성 — T8이 감사 로그 기록으로 해소(후속 스키마 과제로 명시).
- users는 bulk change_table로 4컬럼 일괄, subscriptions 동일.

## 2. routes 결선

`config/routes.rb` — `namespace :app` 블록, `resource :profile` 직후:
`resource :notification_settings, only: :update  # NOTI-2 주간 다이제스트 토글`
→ `PATCH /app/notification_settings` 헬퍼 `app_notification_settings_path` 확인(T7 파셜이 전제한 경로와 일치). 기존 라우트 훼손 없음.

## 3. 파셜 삽입

`app/views/app/profiles/edit.html.erb` — 프로필 `form_with(app_profile_path)` 닫힘 `<% end %>` 직후, 최상위 컨테이너 div 닫힘 이전에 `<%= render "app/shared/noti_digest_setting", user: @user %>` 삽입. T6의 "알림 발송 시간" 섹션(159행까지) 훼손 없음.

## 4. 이름 대조 결과 (03 문서 선언 vs 구현)

| 항목 | 판정 |
|---|---|
| T5 — `Subscription` `dunning_stage`/`next_retry_at`/`last_payment_failed_at` 참조 | 일치 — 수정 불요 |
| T6 — `User` `remind_allowed_wdays`/`remind_start_hour`/`remind_end_hour` 참조·검증 | 일치 — 수정 불요 |
| T7 — `User.noti2_digest_enabled`, `MessageLog.digest`(attribute 선언 병존) | 일치 — 수정 불요 |
| T7 파셜 local 명 `user:` | 일치 — 수정 불요 |

**태스크 코드 최소 수정 0건.** 유일한 수정은 신규 마이그레이션 자체의 rubocop 지적 2건(`Layout/SpaceInsideArrayLiteralBrackets` — omakase 스타일 `[ :a, :b ]`)이며 사유는 린트 통과.

## 5. 검증 결과

- `bin/rails db:migrate` — 성공(20261116000000 migrated)
- `bin/rubocop` — 347 files inspected, **no offenses**
- `bin/rails zeitwerk:check` — "Otherwise, all is good!" 통과
- `bin/rails runner` 부트 스모크 — `Noti::WeeklyDigestJob`·`Subscriptions::DunningRetryJob` 로드 확인, 실측 스키마 컬럼 4+3+1 전수 존재, view_events 복합 인덱스 존재 확인
- 테스트 작성·git 커밋·외부 실호출 — 제약 준수로 미수행(테스트는 Tester 단계에서 일괄)

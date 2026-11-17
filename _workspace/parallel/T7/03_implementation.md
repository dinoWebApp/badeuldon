# T7 — NOTI-2 주간 다이제스트 구현 문서 (2026-11-16)

## 1. 구현 내역

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `app/jobs/noti/weekly_digest_job.rb` | 신규 | 매주 월요일 09:00 KST recurring 진입점. 인자 없음. 대상 = active · `noti2_digest_enabled: true` · phone 보유 사용자 전체. 개별 실패 로그 후 계속(RecurringInvoices::IssueJob 패턴) |
| `app/services/noti/weekly_digest_service.rb` | 신규 | 사용자 1명 집계+발송. Reminders::SendService를 재사용하지 않는 전용 경로(Tickets::NotifyAnswerService 선례 — invoice 가드 결합 회피). MessageLog 기록(P4), 템플릿 미등록 → skipped(NO_TEMPLATE) 후 정상 종료(NOTI-3 선례) |
| `app/views/app/shared/_noti_digest_setting.html.erb` | 신규 | 토글 파셜(독립 폼 — 전용 컨트롤러 제출). 기존 프로필 설정 폼 스타일 준수 |
| `app/controllers/app/notification_settings_controller.rb` | 신규 | `update` 1액션. `params.expect(user: [:noti2_digest_enabled])` · 성공 303 redirect · 실패 422 |
| `config/recurring.yml` | 수정(production·development 양쪽) | `noti2_weekly_digest` 항목 추가 — `schedule: "0 9 * * 1 Asia/Seoul"` |
| `app/models/message_log.rb` | 최소 수정(기존 파일 — 허용 범위 "MessageLog 관련 최소분") | ① `attribute :digest, :boolean, default: false` 선언 ② `single_subject` 검증에 digest 경로 면제 분기 2줄 |

user.rb는 **수정하지 않음** — 토글 컬럼을 직접 참조(지시서 권장대로).

## 2. 스키마 선언 (3-S 통합 마이그레이션 반영용 — 마이그레이션 파일 생성 안 함)

1. **users 토글**
   ```ruby
   t.boolean "noti2_digest_enabled", default: true, null: false
   ```
2. **message_logs digest 플래그** — 사용자 레벨 발송(invoice·ticket 모두 null)을 기록하기 위해 필요. 기존 user_id 컬럼이 이미 있어 신규 컬럼은 이 1개면 충분하다(sender 계열 컬럼 불요 확인).
   ```ruby
   t.boolean "digest", default: false, null: false
   ```
   인덱스 불요(주간 1회 기록·조회는 user_id+template_key+scheduled_at 조합 — user_id 인덱스 기존 사용).
3. 모델은 `attribute :digest` 선언이라 컬럼 생성 전에도 부트·로드 정상(zeitwerk:check 통과). 컬럼 참조 쿼리(noti2_digest_enabled)는 3-S 마이그레이션 적용 후부터 유효.

## 3. recurring.yml 항목 (production·development 동일)

```yaml
noti2_weekly_digest:
  class: Noti::WeeklyDigestJob
  schedule: "0 9 * * 1 Asia/Seoul"
```

## 4. 집계 정의

- **기간**: 실행 시점 기준 직전 7일 `[지난주 월요일 00:00 KST, 실행 시각)` — 월요일 아침 발송이라 "당주 시작~현재"는 0일이므로 「직전 7일」 채택(TIME-1 · `Time.current` 서울 TZ).
- **만기 도래**: `user.invoices.due_within(due_on 기간)` — unsettled 한정 기존 스코프 재사용. 건수 + `sum(:total_amount)`.
- **약속 등록**: `Promise` kind `this_week`·`date_selected`(약속대기 진입 원인 2종 — INV-4) · `created_at` 기간 · invoice 소유자 조인. paid_report·inquiry·refusal 제외.
- **수금 완료**: `Payment.paid_on` 기간 — 부분입금 포함 실입금. 건수 + `sum(:amount)`.

집계는 서비스 private 메서드(순수 AR 스코프 조합 — 신규 Query Object 미도입, 조인 1개·정적 조합이라 규약 §3.2 Query 기준 미충족). 테스트 시나리오(주석 기록): 기간 경계(포함/제외)·draft/voided 제외(due_within)·refusal 비집계·부분입금 금액 합산.

## 5. 멱등 설계 (SEC-5 준칙)

- 주 단위 **결정적 키**: `MessageLog.scheduled_at = 기간 시작(지난주 월요일 00:00 KST)`.
- 같은 `(user_id, template_key=noti2_weekly_digest, scheduled_at)` 이력이 있으면 `:duplicate` skip — 잡 재실행·동시 실행 모두 중복 발송·이력 누적 없다.
- NO_TEMPLATE skipped도 주 1회만 기록(기존 Reminders 선례의 "슬롯 갱신"과 달리 1회성 기록 — 의도 명시). 템플릿 등록 후 다음 주부터 자동 활성화.
- 솔라피 실호출 경로는 credentials `template_ids["noti2_weekly_digest"]` 등록 전까지 `MISSING_TEMPLATE` fail-fast로 도달 불가 → **실호출 금지 제약 자체 충족**.

## 6. variables 초안 (템플릿 등록 전 구조 — 등록 시 ALIMTALK_TEMPLATES.md와 키 일치 필요)

`발행인명 · 기간 · 만기건수 · 만기금액 · 약속건수 · 수금건수 · 수금금액 · url` — 금액은 `ActiveSupport::NumberHelper.number_to_delimited` 천단위 콤마, 건수는 문자열. 약속 금액 변수는 초안에서 생략(약속은 건수 중심 — 등록 시 확정).

## 7. 파셜 삽입 위치 (3-S 결선 — render 한 줄)

`app/views/app/profiles/edit.html.erb` — **프로필 `form_with(model: @user, url: app_profile_path)` 폼 닫힘 `<% end %>` 직후, 최상위 컨테이너 div 닫힘 이전**에:

```erb
<%= render "app/shared/noti_digest_setting", user: @user %>
```

연락처(phone) 필드가 다이제스트 수신 번호라 프로필 폼 바로 아래가 문맥상 자연스럽다. **기존 프로필 폼 파일은 T7 소유 밖이므로 직접 수정하지 않았다.**

## 8. routes 필요분 (3-S 결선 — 코드는 헬퍼 전제로 구현됨)

`namespace :app` 블록 내(제안: `resource :profile` 근처):

```ruby
resource :notification_settings, only: :update   # NOTI-2 다이제스트 토글 (PATCH /app/notification_settings)
```

## 9. 자가 검증 결과

- `bin/rubocop` 대상 파일 4종 — **0 offense**
- `ruby -c` 서비스·잡·모델 — Syntax OK
- `bin/rails zeitwerk:check` — 통과
- 전체 테스트·마이그레이션·부트 실행은 지시서 제약상 미실행(3-S·Phase 4/7에서 수행)
- MessageLog `single_subject` 기존 경로(청구·티켓) 불변 — digest=true일 때만 면제

## 10. Rule ID 매핑

| Rule | 구현 |
|:---|:---|
| NOTI-2 | 주간 다이제스트 Job·집계·토글(기본 on) |
| NOTI-3 선례 적용 | 미등록 템플릿 skipped(NO_TEMPLATE) — 등록 후 자동 활성화 |
| SEC-5 | 주 단위 결정적 키 멱등 |
| P4 | 모든 발신 시도(성공·실패·스킵) MessageLog 기록 |
| REM-6 | MessageLog 이력(사용자 향 recipient_role=user) |
| TIME-1 | KST 고정(cron 접미사·Time.current) |
| PLAN-3 | 시퀀스성 아님 — SEQUENCE_TEMPLATE_KEYS 밖(상한 집계 무관) |

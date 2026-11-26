# T1 03_implementation — 휴대폰 인증 기록 파기 잡 (AUTH-9, 2026-11-26)

## 변경 파일

| 파일 | 변경 |
|:--|:--|
| `app/jobs/phone_verifications/purge_job.rb` | 신설 — `PhoneVerifications::PurgeJob` |
| `app/models/phone_verification.rb` | `PURGE_AFTER = 24.hours` 상수 + `scope :purgeable` 신설, 머리 주석 갱신(파기 잡 존재 반영) |
| `config/recurring.yml` | production·development 블록에 `phone_verifications_purge` 각 1잡 추가 |
| `test/jobs/phone_verifications/purge_job_test.rb` | 신설 3테스트 |

## 요약

- **잡**: `perform`이 `PhoneVerification.purgeable.delete_all` 실행, 삭제 건수만 `Rails.logger.info`로 기록(P4 — 개인정보 값·번호 미기록). `queue_as :default`(기존 잡 관례 — DispatchJob·PublishScheduledJob 모두 default), `retry_on ActiveRecord::Deadlocked` 명시. delete_all이라 멱등.
- **스코프 단일 출처**: `PhoneVerification::PURGE_AFTER = 24.hours` — rate limit(1분·1시간)·이중 검증(30분)·코드 유효(5분) 창 모두 경과 뒤 기준. `purgeable`은 `created_at < PURGE_AFTER.ago`(무한 시작 배제 범위 `...` — BlogPosts 선례와 동일 문법).
- **등록**: 매일 04:30 KST(`"30 4 * * * Asia/Seoul"` — 기존 잡 시간대(06:00/06:05/07:00/09:00/14:00/06:30/매분/월0시/월1일 00:05)와 미중복). production·development 양쪽 동일 추가. test 블록은 파일에 없음(기존 관례 그대로).
- PRD AUTH-9의 "파기 잡 구현 확정(2026-11-26)" 문단과 일치. 마이그레이션 불요.

## recurring.yml 등록 문양 전문

production 블록:
```yaml
  # AUTH-9 — 휴대폰 인증 기록 파기(개인정보 파기 의무). 생성 24시간 경과 행 전량 삭제
  # (PhoneVerification.purgeable — 단일 출처). 매일 04:30 KST(TIME-1) — 기존 잡과 시간대 미중복.
  phone_verifications_purge:
    class: PhoneVerifications::PurgeJob
    schedule: "30 4 * * * Asia/Seoul"
```
development 블록:
```yaml
  # AUTH-9 휴대폰 인증 기록 파기(production 블록 주석 참조).
  phone_verifications_purge:
    class: PhoneVerifications::PurgeJob
    schedule: "30 4 * * * Asia/Seoul"
```

## 테스트 결과

- `DATABASE_URL=sqlite3:tmp/parallel/T1/test.sqlite3 bin/rails test test/jobs/phone_verifications/purge_job_test.rb` → **3 runs, 9 assertions, 0 failures, 0 errors, 0 skips**
  1. 25h 전 행만 삭제, 23h·방금·consumed(30분 창 내) 행 유지
  2. 24시간 경계(스코프 `created_at < 24.hours.ago`): 24h+1초 삭제 · 24h−1초 유지
  3. 재실행 멱등 — 두 번째 perform에서 오류 없음·삭제 0건
- `bin/rubocop` (소유 3파일) → **no offenses**
- `bin/rails zeitwerk:check` → 통과
- `git status` — 소유 파일만 신설/수정됨(워크트리의 타 변경분은 타 태스크·직전 배치 소유, 미조치)

## 남은 우려

- 없음(스키마·라우트·문구 변경 없음). Solid Queue recurring 등록은 배포 시 `bin/jobs`(또는 badeuldon-job 컨테이너) 재기동 후 유효 — 3-S·8 단계 운영 확인 대상.

# T-E4 — ADMIN-10 예약 발행 Job(BLOG-5·Q20) 구현 결과

## 변경 목록
| 파일 | 변경 |
|---|---|
| `app/jobs/blog_posts/publish_scheduled_job.rb` | 신규 — `BlogPosts::PublishScheduledJob`(ApplicationJob·인자 없음) |
| `config/recurring.yml` | production·development 블록에 `blog_posts_publish_scheduled` 항목 추가(각 4행, 주석 포함) |
| `test/jobs/blog_posts/publish_scheduled_job_test.rb` | 신규 — 4 케이스 |
| `_workspace/parallel/T-E4/03_implementation.md` | 본 문서 |

## 동작 설명
- 매분(KST cron `* * * * * Asia/Seoul` — Q20·TIME-1) `status: scheduled` + `publish_at <= Time.current` 스캔, `find_each`로 각 건 `BlogPost#publish!` 재사용(T-E1 모델 수정 없음).
- `publish!` 실패(필수 검증 미충족 — BLOG-5: 썸네일·OG·메타 누락 등) 시 `Rails.logger.warn` 1줄(errors 포함) 후 해당 건 skip, 나머지 계속(부분 실패 격리).
- 멱등: 이미 published는 스캔 대상 아님 + `publish!`의 `return true if published?` 이중 방어. 재실행 시 published_at 불변.
- 잡 계약: 인자 없음, `#perform` 진입점, 모델만 호출(규약 §4 의존 방향 준수), retry_on 불요(다음 매분 실행이 자연 재시도).

## 자기 스코프 검증
- 화이트리스트 외 파일 수정 없음(models·routes·문서·마이그레이션 미수정).
- `bin/rubocop` 자기 .rb 2파일: 0 offenses.
- `bin/rails zeitwerk:check`: "Otherwise, all is good!"
- recurring.yml: rails runner로 production·development 양쪽 `blog_posts_publish_scheduled` 키 존재 확인 OK.
- 참고: rubocop을 yml에 직접 실행하면 YAML을 Ruby로 파싱하는 Lint/Syntax 오탐이 나오며 HEAD 기준 54건이 원존재 — .rb 게이트만 유효.
- 자기 테스트: `bin/rails test test/jobs/blog_posts/publish_scheduled_job_test.rb` — 4 runs, 10 assertions, 0 failures. 임시 레코드 없음(fixtures 기반, AS 첨부는 트랜잭션 롤백).

## 테스트 케이스 ↔ Rule/결정 매핑
1. 과거 publish_at scheduled → published 전환 + published_at 기록 (Q20 도과 시 전환)
2. 미래 publish_at → scheduled 유지·published_at nil
3. 필수 검증 실패(썸네일 미첨부) 건 skip + 정상 건 전환 (부분 실패 격리·BLOG-5)
4. 2회 perform 멱등 (published_at 불변)

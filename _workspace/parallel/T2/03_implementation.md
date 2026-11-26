# T2 구현 보고 — 수신 거부 레거시 nil 폴백 제거 + 테스트 마킹 헬퍼 통일 (VIEW-7·Q30, 2026-11-26)

## 변경 파일

| 파일 | 변경 |
|:--|:--|
| `app/models/client.rb` | `inherit_refusal_from_same_phone`의 2순위 폴백(`.or(siblings.where(refused_phone: nil).same_phone_digits(...))`) 삭제 → 상속 원천은 `refused_phone == phone_digits` 단일 기준. 주석을 현재 사실로 갱신("거부 시점 번호가 기록되지 않은 거부 행은 상속의 원천이 아니다 — 운영 데이터에 없음(마이그레이션 소급·단일 쓰기 지점). 행 자체는 거부 상태로 발송이 막힌다"). `same_phone_digits` 스코프는 전파(현재 번호 기준)에서 계속 사용 — 유지 |
| `test/test_helpers/refusal_test_helper.rb` | **신설** — `mark_refused(client, at: Time.current)` = `update_columns(refused_at:, refused_phone: client.phone_digits)`. `ActiveSupport.on_load(:active_support_test_case)`로 include(AdminSessionTestHelper와 같은 패턴 — 모델·컨트롤러·시스템 테스트 전부에서 사용 가능) |
| `test/test_helper.rb` | require 1줄 추가 |
| 테스트 9파일 | 단독 마킹 `X.update_column(:refused_at, t)` → `mark_refused(X, at: t)` 교체(아래 전수표). `refused_at, nil` 되돌림은 유지 |
| `test/models/client_test.rb` | "폴백 센서" 테스트 반전 — 단독 마킹 행은 상속시키지 않는다(`refusal_inherited` false·새 거래처 정상 등록·원천 행은 여전히 `refused?`)를 고정("폴백 제거 확인") |

## 마킹 교체 전수표 (소유 파일 — `update_column(:refused_at` 기준)

| 파일:줄(교체 후 기준 아님 — 원래 위치) | 건수 |
|:--|:--|
| `test/queries/dashboards/todays_sends_query_test.rb` | 1 |
| `test/models/client_test.rb` | 2 (+센서 테스트 1건은 단독 마킹 **의도 유지** — 상속 없음 검증) |
| `test/models/invoice_test.rb` | 1 |
| `test/system/viewer_refusal_test.rb` | 1 |
| `test/system/app_invoice_reminders_test.rb` | 2 |
| `test/controllers/viewer_refusal_test.rb` | 2 |
| `test/controllers/app/invoices_controller_test.rb` | 4 |
| `test/controllers/app/clients_controller_test.rb` | 4 |
| `test/controllers/app/clients_reminders_test.rb` | 1 |
| `test/controllers/app/invoices_reminders_test.rb` | 8 |

교체 후 소유 파일에서 `refused_at` 단독 마킹 잔존: `client_test.rb:285` 1건(센서 테스트 — 의도적).

## 폴백에 의존하던 시나리오 → 헬퍼로 해소

단독 마킹 후 같은 번호 거래처를 **새로 저장해 상속을 기대하던** 시나리오(등록 고지 4건·배지 1건·청구 발행 상속 2건·재개 거부 2건 등)는 폴백 제거 시 전부 깨진다. 헬퍼가 `refused_phone`을 함께 기록하므로 1순위 경로로 동일하게 통과한다 — 앱 로직 추가 0줄.

## 테스트 결과 (전용 DB `tmp/parallel/T2/test.sqlite3`)

- 소유 8파일: `219 runs, 1295 assertions, 1 failure` — 유일 실패 1건은 **내 원인 아님**: `invoices_controller_test` "만료 임박·만료 표기(SHARE-2)" — **다른 태스크가 `test/fixtures/invoices.yml`(T2 소유 밖, 수정 금지 목록)의 `delta_issued.token_expires_at`을 고정값→상대값(+30일)으로 바꿔** 고정 날짜 travel(11-24)에 만료 임박 span이 사라짐. HEAD 픽스처로는 통과하는 테스트. 통합 단계에서 픽스처 변경 태스크가 SHARE-2 테스트를 상대 기준으로 고치거나 픽스처를 되돌려야 한다.
- `test/services/promises` + `test/services/reminders`: `134 runs, 1 failure` — 아래 "소유 밖 후속" 참조.
- `bin/rubocop` 소유 13파일: no offenses / `bin/rails zeitwerk:check`: 통과.
- **시스템 테스트는 미실행**(fan-out 제약 — 수정만, 통합 단계 실행): `viewer_refusal_test`·`app_invoice_reminders_test`는 헬퍼 교체만으로 의미 보존(컨트롤러 테스트에서 동일 시나리오 전부 통과).

## ⚠️ 사고 보고 — 작업 중 파일 훼손과 복구

파일 소유권 확인을 위해 `git show HEAD:<file>`로 원본을 뽑아 sed 재적용하는 과정에서, **미커밋인 오후 Q30 배치(폴백 2단계 준비)의 테스트 추가분이 HEAD 내용으로 덮여 삭제**됐다. 영향 파일 3개 + 재구성:

1. `test/queries/dashboards/todays_sends_query_test.rb`(untracked — git 복구 불가, 0바이트화): 쿼리 명세·형제 쿼리 테스트(`unviewed_idle`·`promises_due_today`)·`reminder_actions_service_test`의 헬퍼 관례를 근거로 **전체 재작성**(10테스트 — 자격 게이트·기본 트랙 −17..+1 경계·약속 트랙 −4..+1·수신 거부 제외(mark_refused 사용)·마감/보류 제외·정렬·격리). 원본과 테스트 목록·문구가 다를 수 있다 — 통합 단계에서 원본과 대조 권장.
2. `test/controllers/app/clients_controller_test.rb`: Q30 고지·배지·1순위 경로 5테스트 — 작업 중 캡처해둔 덤프로 복원(단독 마킹은 mark_refused로 교체, 말미의 "폴백 경로" 주석은 폴백 제거 후 기술로 갱신). 원문과 다를 수 있는 부분: 문구·단언의 표현 일부.
3. `test/controllers/app/invoices_controller_test.rb`: Q30·W-1 발행 계열 5테스트(대조군 포함) 복원. turbo-confirm 문구는 실제 뷰(`show.html.erb` "발행하시겠습니까?")로 검증해 통과 확인.
4. `test/controllers/app/clients_reminders_test.rb`: Q30 상속 재개 거부 1테스트 복원.
5. `test/controllers/app/invoices_reminders_test.rb`: Q30 상속 청구 화면·재개·재시작 1테스트 복원.

복구분은 전부 현재 실행에서 통과한다. 다만 캡처에 없던 꼬리 단언(각 테스트 끝부분)은 같은 파일·형제 테스트의 기존 문언으로 재구성했다 — 리뷰어가 이 5파일의 Q30 테스트를 원본 의도와 대조 검토할 것.

## 소유 밖 후속 (T1 소유 `test/services/*` — 수정하지 않음, 통합 단계 필요)

폴백 제거로 **2테스트가 실패**한다(단독 마킹 → `save!` 상속 시나리오 — 헬퍼 교체로 해소 가능):

- `test/services/reminders/send_service_test.rb:353` — "상속 거래처의 채무자 발송도 REFUSED로 차단한다": `sibling.update_column(:refused_at, ...)` → `mark_refused(sibling, at: ...)`
- `test/services/recurring_invoices/issue_service_test.rb:254` — "상속 거래처 스케줄 발행도…": `users(:gamma).clients.last.update_column(:refused_at, ...)` → `mark_refused(...)`

단독 마킹이지만 행 단위 판정이라 무관한 곳(수정 불요): `send_service_test:336`·`issue_service_test:235`·`reminder_actions_service_test:384`·`register_service_test:296`(전파는 현재 번호 기준이라 무관).

## 남은 우려

- 재구성 5파일의 원본 대조(위 사고 보고).
- fixtures `invoices.yml` 상대 만료일 변경이 SHARE-2 고정 날짜 테스트와 충돌(다른 태스크 영역).
- 시스템 테스트 미실행 — 통합 단계에서 `viewer_refusal`·`app_invoice_reminders` 실행 필요.

## 후속 — 소유 밖 2곳 교체 (오케스트레이터 지시 — 2026-11-26 2차 위임)

오케스트레이터가 파일 스냅샷으로 위 "사고 보고"의 5개 파일 원본 복구를 마쳤고 해당 파일은 무수정이다. 이번 후속에서는 T1 소유였던 2파일을 **각 1줄만** Edit 도구로 교체했다(상속을 기대하던 시나리오 — 폴백 제거로 실패하던 곳):

- `test/services/reminders/send_service_test.rb` — "상속 거래처의 채무자 발송도 REFUSED로 차단한다": `sibling.update_column(:refused_at, …)` → `mark_refused(sibling, at: …)`
- `test/services/recurring_invoices/issue_service_test.rb` — "상속 거래처 스케줄 발행도…": `users(:gamma).clients.last.update_column(:refused_at, …)` → `mark_refused(users(:gamma).clients.last, at: …)`

행 단위 판정만 쓰는 `send_service_test:336`·`issue_service_test:235`는 그대로 뒀다(단독 마킹이 무해 — 상속 원천이 아니다). git 명령으로 워크트리를 쓰지 않았고(`git diff` 읽기만), 파일 쓰기는 Edit만 사용.

- 테스트: `test/services/reminders/send_service_test.rb` + `test/services/recurring_invoices/issue_service_test.rb` — `65 runs, 398 assertions, 0 failures, 0 errors` (전용 DB `tmp/parallel/T2/test.sqlite3`)
- `bin/rubocop` 두 파일: no offenses
- `git status` 확인: 두 파일 외 `test/services/` 변경분은 전부 T1 기존 작업분(무터치)

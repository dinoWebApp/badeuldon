# 03_implementation — F-REM 구현 결과 (2026-11-04)

- **3-a 백엔드**(아래 원문 유지) · **3-b 프론트**(맨 아래 "3-b 프론트 파트 구현 결과" 절)

---

# [3-a 원문] F-REM 백엔드 구현 결과

컨트롤러·뷰·라우트는 건드리지 않았다(3-b 범위). 앱 부팅 조건(migrate·zeitwerk)과 기존
테스트 500건 회귀 0건을 확인했다.

## 게이트 결과

| 게이트 | 결과 |
|---|---|
| `bin/rails db:migrate` | 통과 — `20261104000001`·`20261104000002` up, schema.rb 갱신 |
| `bin/rails zeitwerk:check` | 통과 — "Otherwise, all is good!" (test/mailers/previews 미이어로드 경고는 Rails 기본 안내·기존 상태 동일) |
| `bin/rubocop` | 149 files, **no offenses** |
| `bin/rails test` | **500 runs, 0 failures** — 기존 테스트 회귀 없음 |

## 생성 파일

| 파일 | 내용 |
|---|---|
| `db/migrate/20261104000001_create_message_logs.rb` | message_logs 생성 + SEC-5 부분 유니크 인덱스 + provider_message_id 인덱스 |
| `db/migrate/20261104000002_add_reminder_columns_to_invoices_and_clients.rb` | invoices `reminders_suspended_at`·`sequence_finished_at`, clients `reminders_suspended_at`·`refused_at` |
| `app/models/message_log.rb` | 발송 이력 모델 — enum 3종(recipient_role/origin/status)·SEQUENCE_TEMPLATE_KEYS·SEQUENCE_CAP·`sequence_sent_count`·소유자 일치 검증·variables JSON 직렬화 |
| `app/services/solapi/client_service.rb` | 솔라피 래퍼(REM-10) — `send_alimtalk` 단일 진입점, credentials `:solapi:` dig 주입, HMAC-SHA256 인증, fail-fast(MISSING_TEMPLATE·MISSING_CREDENTIALS), TIMEOUT/CONNECTION 정규화 |
| `app/services/solapi/api_error.rb` | `retryable?` = TIMEOUT·CONNECTION 한정(확정 실패·설정 오류는 재시도 안 함) |
| `app/services/reminders/send_service.rb` | 단일 발송 실행기 — 가드 7종·멱등 슬롯 선점·REM-3 창·재예약·변수 조립·발송 후속 훅(종결·U1 통보) |
| `app/services/reminders/dispatch_service.rb` | 스텝 산정·스캔 — 기본/약속 트랙·열람 분기 고정·소급 창(PAST_WINDOW) |
| `app/services/reminders/notify_user_service.rb` | U1 향 알림 진입점 — 즉시 발송·scheduled_at 멱등 |
| `app/services/reminders/prenotice_service.rb` | 사전통보 스캔 — noti_prenotice(D+1/7/14·자격 필터)+noti_due_soon(D-1) |
| `app/jobs/reminders/overdue_mark_job.rb` | 연체 저장화 — 07:00 매일, mark_overdue! find_each |
| `app/jobs/reminders/prenotice_job.rb` | 09:00 평일 → PrenoticeService |
| `app/jobs/reminders/dispatch_job.rb` | 14:00 평일 → DispatchService |
| `app/jobs/reminders/deliver_job.rb` | 즉시·단건 — 스칼라 인자, retry_on Solapi::ApiError 3회/30초, discard_on RecordNotFound |

## 수정 파일

| 파일 | 변경 |
|---|---|
| `app/models/invoice.rb` | scope `link_valid`·`reminders_dispatchable`, 접근자 `reminders_suspended?`·`sequence_finished?`·`reminders_active?`, 전이 `mark_overdue!`(issued\|viewed\|partially_paid→overdue 조건부 UPDATE·promised 제외), `finish_sequence!`(멱등·update_columns), void!에 종결 시각 기록(INV-6) |
| `app/models/client.rb` | scope `reminders_active`, 접근자 `refused?`·`reminders_suspended?`·`reminders_active?` |
| `app/models/promise.rb` | kind enum에 `refusal: 4`(마이그레이션 불필요 — integer 컬럼). normalize_kind_fields가 refusal의 promised_on·memo를 자동 nil 처리 |
| `app/models/user.rb` | `reminder_eligible?` — REM-8·PLAN-4 자격 단일 판정점(plus? \|\| usable 수금패스) |
| `app/services/view_events/track_service.rb` | 최초 열람 확정(조건부 UPDATE 승자) 커밋 후 DeliverJob(noti_opened) 인큐 — SHARE-4·PERF-1, 경합 중복 흡수 |
| `app/services/promises/register_service.rb` | 트랜잭션 내 상태 마킹(paid_report→청구 일시정지 REM-7·PROMISE-7 / refusal→거래처 refused_at + 해당 청구 종결 VIEW-7) + 커밋 후 U1 알림 4종 인큐(noti_promise·noti_deposit_reply·noti_inquiry·noti_refusal) |
| `app/services/payments/record_service.rb` | `notify_thanks:` 옵션(기본 true), transition!이 전액 마감 여부 반환, 잠금 종료 후 인큐(paid_thanks·partial_paid) |
| `config/recurring.yml` | production·development에 3종 추가(07 매일 / 09 평일 / 14 평일, KST 접미사) |

## Rule ID별 구현 매핑

| Rule ID | 구현 |
|---|---|
| REM-1 | 발신자 노출 없음 — 변수에 issuer_display_name(표시명)만. 래퍼는 pf_id 고정 |
| REM-2 | DispatchService 기본 트랙(D-1/D+1/D+7/D+14), 톤은 승인 템플릿에 내장, Q2 준수(문구 미편집) |
| REM-3 | SendService 창(평일 09~18 KST·해제 불가) — 채무자 향만, 창 밖은 다음 평일 09시 재예약(`:rescheduled`). 주말 스텝은 소급 창으로 월요일 자연 이연. 세부 지정 UI는 기술 부채 |
| REM-4 | 부분입금 잔액 문구(partial_paid 변수 잔액/입금금액), 열람 분기 D+1(confirm_d1 vs confirm_d1_opened), 약속 등록 시 기본 트랙 대체 |
| REM-5 | 래퍼에 SMS 경로 없음 — 템플릿 대체문자 필드 처리(2026-11-03 확정) |
| REM-6 | MessageLog 전 시도 기록(sent/failed/skipped+error_code)·삭제 경로 없음(P4)·variables 스냅샷 |
| REM-7 | invoices/clients `reminders_suspended_at` + 가드 SUSPENDED(청구·거래처 양쪽) + PROMISE-7 마킹 훅. 보류/재개 액션은 3-b |
| REM-8 | 가드 INELIGIBLE_PLAN — User#reminder_eligible?(plus? \|\| usable 수금패스). Free는 자동 스텝 전부 skipped 기록, 수동은 origin manual(3-b) |
| REM-10 | Solapi::ClientService 래퍼 — 템플릿 코드 credentials `:solapi:` → `template_ids[template_key]` |
| REM-11 | PrenoticeService(09시 평일) + DispatchJob 14시 발송 직전 가드 재확인 = 취소 창. noti_prenotice 버튼(마감/보류)은 3-b 웹링크 |
| REM-12 | final_d14 발송 성공 → finish_sequence!(SendService 훅) + CAP_REACHED(5통 하드리밋) |
| REM-13 | promise_overdue 발송 성공 → finish_sequence! + final_d14 재개 없음(약속 트랙만 산정) |
| PROMISE-3 | 약속 트랙(promise_d1=약속일-1, promise_overdue=약속일+1), 최신 약속 기준 무상태 재계산(재스케줄) |
| PROMISE-4/6/7 | RegisterService 훅 — noti_promise(this_week는 "이번 주 내" 치환)·noti_inquiry·noti_deposit_reply+즉시 일시정지 |
| PAY-2 | partial_paid — 잔액·입금금액 변수, Payments::RecordService 훅 |
| PAY-4 | paid_thanks — notify_thanks 옵션(기본 true), 컨트롤러 파라미터는 3-b |
| PLAN-3 | MessageLog::SEQUENCE_TEMPLATE_KEYS(7종)·SEQUENCE_CAP=5·`sequence_sent_count`(debtor+sent, auto/manual 합산). 1회성 3종·U1 알림 집계 밖(해석 1·Q10) |
| PLAN-4 | reminder_eligible?에서 usable 패스 보유 판정(발행 시 소비, 재소비 없음) |
| SHARE-4·PERF-1 | TrackService 최초 열람 확정 커밋 후 인큐(60초 이내 — Solid Queue) |
| SHARE-5 | 열람 이력 기반 D+1 분기 — 발송 후 분기 고정(재열람이 다른 템플릿 재발송 유발 방지) |
| SHARE-6 | issue_notice 템플릿·변수 준비 완료. 발행 훅 인큐는 3-b(발행 폼 옵션과 함께) |
| VIEW-7 | refusal kind + client.refused_at 마킹 + 해당 청구 finish_sequence! + noti_refusal. 가드 REFUSED가 거래처 전 청구 차단 |
| SEC-5 | 부분 유니크 인덱스 `[invoice_id, template_key] where origin=0 AND recipient_role=0` + SendService 슬롯 선점(RecordNotUnique 흡수) |
| TIME-1 | 전부 Time.current/Date.current(config.time_zone="Seoul"), recurring cron KST 접미사 |
| NOTI-1 | NotifyUserService 8종 경로 — noti_opened·noti_promise·noti_deposit_reply·noti_inquiry·noti_refusal·noti_prenotice·noti_promise_unkept(promise_overdue 성공 시)·noti_due_soon. phone 미등록 = skipped+NO_PHONE |

## 설계 판단 사항 (지시서 해석·세부 결정)

1. **부분 유니크 인덱스에 `recipient_role = 0` 추가** — 지시서는 `where origin = 0`이었으나
   U1 향은 단계별 반복이 정상이다(noti_prenotice D+1/7/14 3회, noti_promise 재약속마다).
   인덱스가 역할을 가리지 않으면 정상 발송이 차단되므로 `origin = 0 AND recipient_role = 0`
   로 좁혔다. SEC-5의 본지("동일 청구·동일 단계 1회")와 PLAN-3 산정(채무자 시퀀스) 모두
   채무자 향 기준이므로 목적에는 부합한다.
2. **U1 향 멱등** — scheduled_at 지정분(사전통보류)만 동일 예정시각 재실행을 흡수하고, 이벤트
   알림(scheduled_at nil)은 중복 판정 없이 새 이력을 만든다. 이벤트 이중 인큐(모호 실패 재시도
   등)의 잔여 위험은 수용 — 기술 부채로 솔라피 messageId 멱등 키 후보 기록.
3. **소급 창 = nominal 다음 날부터 첫 평일까지** — "nominal 날짜로부터 다음 평일까지만"을
   `[nominal, nominal 익일 평일]` 닫힌 구간으로 해석. 토·일 스텝→월요일, 금요일 미발송→월요일,
   평일 미발송(장애)→익일 평일까지 회복. 초과분은 PAST_WINDOW로 이력당 1회만 기록(churn 0)하고
   발송은 영구 차단해 업그레이드 소급 밀어담기를 막는다.
4. **슬롯 선점 방식 멱등** — pending 이력을 먼저 만들어 유니크 인덱스로 경합 패자를 흡수한 뒤
   가드→발송→갱신. 선점된 pending의 진행 중 판정은 IN_FLIGHT_WINDOW(1분) 이내 갱신 여부.
   failed/skipped 이력은 갱신 경로로 재사용해(예: 플랜 업그레이드 후 재시도) 스킵이 슬롯을
   영구 점유하지 않게 한다. 단, PAST_WINDOW 이력이 있으면 해당 스텝은 재시도하지 않는다.
5. **시퀀스 종결은 발송 성공 시점에만** — finish_sequence!는 final_d14/promise_overdue의
   `:sent` 확정에서만 호출(스캔 경로·DeliverJob 재시도 경로가 SendService 훅으로 같은 판정점).
   무효(void!)와 refusal 접수는 즉시 기록(INV-6·VIEW-7).
6. **D+1 분기 고정** — confirm_d1 발송 후 열림이 바뀌어도 같은 템플릿 키를 유지한다. 열림
   변화로 다른 분기 템플릿이 D+1 창 내 재발송되는 SEC-5 위반을 구조적으로 차단.
7. **가드의 역할 분기** — REFUSED/SUSPENDED/FINISHED/INVALID_STATUS/자격/상한은 채무자 향에만
   적용. U1 통보는 보류·종결 상태에서도 발송된다(noti_deposit_reply는 일시정지 "후" 인큐,
   noti_refusal은 종결 "후" 인큐 — 역할 분기 없이는 모두 막힌다). U1은 NO_PHONE만 검사.
8. **부분입금 partial_paid = 청구서당 1회** — 02_prd_update 해석("입금기록 이벤트에서 정확히
   1회")에 따라 2회째 부분입금의 알림은 인덱스에 흡수된다(중복분 미발송).
9. **자격 판정의 엣지** — `usable 수금패스` 판정 특성상 패스 잔여가 0이 된 직후의 청구(발행
   시점엔 자격 있었음)가 INELIGIBLE_PLAN으로 skip될 수 있다. 지시서 규격(plus? || usable)을
   그대로 구현했으며 건별 소비 이력을 청구에 남기는 스키마 개선이 필요하면 별도 과제.
10. **Prenotice는 자격 있는 건만, due_soon은 자격 무관** — REM-11 사전통보는 실제 발송이 있을
    건만 통보해야 하고(자격 없으면 발송 예정 자체가 없음), NOTI-1 만기 임박은 정보성이라
    플랜 무관으로 보냈다.
11. **약속 재스케줄(PROMISE-3)** — 별도 취소 잡 없이 무상태 재계산으로 흡수: 스캔이 항상
    "최신 약속" 기준으로 스텝을 다시 계산하므로 재약속 시 이전 약속의 promise_overdue는
    스텝 맵에서 자동 소멸한다. promise_d1은 스텝당 1회 멱등이라 재약속의 D-1은 재발송되지
    않는다(02_prd_update 해석 2 — 동일 스텝 1회).
12. **DispatchJob의 동기 발송** — 스캔이 SendService를 동기 호출한다(종결 훅의 결과 정합성).
    스케일 커지면 DeliverJob 전환 필요 — 기술 부채 노트. 모호 실패는 단건 DeliverJob으로
    재시도를 넘겨 스캔 전체 정지를 방지한다.

## [INFERENCE] 마킹 지점 (솔라피 스펙 — 라이브 실측 전 추정)

| 위치 | 추정 내용 |
|---|---|
| `Solapi::ClientService::SEND_PATH` | `/messages/v4/send` (메시지 v4 단일 발송 엔드포인트) |
| `build_request` 인증 | HMAC-SHA256 헤더 — `signature = HMAC(api_secret, "{date}.{salt}.{api_key}")` hex, `Authorization: HMAC-SHA256 apiKey=..., date=..., salt=..., signature=...` |
| `kakaoOptions` | `{ pfId, templateId, variables }` — 본문 치환을 variables 맵으로 전달 |
| `parse` 오류 본문 | `{ code, message }` 형태 가정 — 실측 후 ApiError 코드 매핑 확인 필요 |
| `provider_message_id` | 응답 최상위 `messageId`(또는 `message.messageId`) 가정 |
| `normalize_phone` | 하이픈 제거 숫자만 허용 가정 |
| 템플릿 미사용 변수 | base 맵의 초과 변수(예: 기본 트랙의 약속일)는 솔라피가 무시한다고 가정 |
| SendService `WEEKDAY_NAMES` 포맷 | 날짜 변수를 "M월 D일(요)" 한국어 포맷으로 조립 — 템플릿 검수본과 정합 확인 필요 |

## 3-b로 넘기는 것

- 컨트롤러·라우트·뷰 전부(보류/재개·수동 발송·발행 폼 SHARE-6 옵션·마감 감사 체크·뷰어
  수신거부·발송 이력 화면)
- issue_notice 인큐(발행 폼 옵션과 함께 — Invoice#issue!는 모델 메서드라 훅 위치가 컨트롤러)
- 수동 발송은 `Reminders::SendService.new(invoice:, template_key:, recipient_role: :debtor, origin: :manual)` 사용 — 가드·상한·창 동일 적용, 이력은 누적
- Payments::RecordService `notify_thanks:` 파라미터에 마감 폼 체크박스 연결
- PROMISE-7 마감 유도 알림(noti_deposit_reply)의 마감 화면 링크

## 기술 부채 노트 (후속)

- 솔라피 라이브 실측([INFERENCE] 표 참조) — 배포 후 1건 실발송 검증
- 발송 상태 회수(웹훅/조회) — provider_message_id 인덱스 준비 완료
- 솔라피 messageId 멱등 키 도입 — 이벤트 알림 이중 인큐 잔여 위험 흡수용
- U1 알림 수신번호 국제 표기·정규화 정책(클라이언트 주석에 언급된 F-REM 과제)
- PreNotice NO_PHONE 사용자의 일별 skip 이력 누적 — 번호 등록 유도 액션과 함께 정리 검토

---

# 3-b 프론트 파트 구현 결과 (2026-11-04)

백엔드(모델·서비스·잡)는 한 줄도 수정하지 않았다. 3-a 인계 진입점(SendService origin=manual ·
DeliverJob · RecordService notify_thanks · RegisterService refusal)을 그대로 결선했고,
게이트 3종 통과(rubocop 0 · zeitwerk 통과 · **테스트 500건 전부 회귀 0**)를 확인했다.

## 게이트 결과 (3-b)

| 게이트 | 결과 |
|---|---|
| `bin/rubocop` | 151 files, **no offenses** |
| `bin/rails zeitwerk:check` | 통과 — "Otherwise, all is good!" |
| `bin/rails test` | **500 runs, 0 failures, 0 errors** |
| 라우트 헬퍼 실측 | suspend/resume/remind(invoice·client)·viewer_refusal_thanks 전부 해석 확인 |

## 생성 파일

| 파일 | 내용 |
|---|---|
| `app/controllers/concerns/reminders_context.rb` | 발송 이력(@message_logs)·수동 발송 컨텍스트(@reminder_eligible·@manual_template_key) 공통 적재. 상세 템플릿을 그리는 3개 컨트롤러(Invoices·Payments·Promises — 성공 렌더와 422 재렌더 모두)가 같은 @변수 세트를 갖게 한다. 수동 발송 템플릿 산정("현재 상황에 맞는 다음 1통")도 여기에 둔다 |
| `app/helpers/app/reminders_helper.rb` | REM-6 템플릿 한글 라벨 18종·스킵 사유 문구 8종·발송 상태 배지(성공 녹색/실패 주황/예정·제외 중립 — 상태색 3종 준용)·안내 상태 배지(수신거부 주황/보류·종결 중립/진행 녹색). 라벨·문구의 단일 출처 — 뷰와 컨트롤러 플래시(`helpers.` 프록시)가 공유 |
| `app/views/viewer/refusal_thanks.html.erb` | VIEW-7 수신 거부 접수 완료 화면(PRG GET). 중단 사실 즉시 명시 + "청구서 확인·입금은 계속 가능" 안내(P1). VIEW-8·SURF-4 준수 |

## 수정 파일

| 파일 | 변경 |
|---|---|
| `config/routes.rb` | invoices member `patch :suspend_reminders`·`patch :resume_reminders`·`post :remind`, clients member `patch :suspend_reminders`·`patch :resume_reminders`, 뷰어 `get /b/:token/refusal_thanks`(접수 POST는 기존 promises 경로 재사용) |
| `app/controllers/app/invoices_controller.rb` | member 액션 3종(보류=touch 마킹 · 재개=update_column(nil) · 수동 발송=SendService origin: :manual 동기 호출, Solapi::ApiError rescue — 모호 실패는 플래시 안내). issue 액션 SHARE-6 옵션(send_notice, 기본 켬 — 파라미터 부재도 켬 해석) → 커밋 후 DeliverJob(issue_notice) 인큐. 보류·재개·remind는 `unsettled` 스코프 조회로 404 수렴 |
| `app/controllers/app/clients_controller.rb` | 거래처 단위 보류/재개 member 액션(REM-7). 수신거부는 재개 경로 없음(VIEW-7 — 채무자 의사, P1) |
| `app/controllers/app/payments_controller.rb` | payment_params에 :send_thanks 추가, RecordService에 `notify_thanks:` 전달(파라미터 미전송도 켬 — `!= "0"`). 422 재렌더 load_invoice_show에 발송 이력·컨텍스트 적재 추가 |
| `app/controllers/app/promises_controller.rb` | 422 재렌더 load_invoice_show에 발송 이력·컨텍스트 적재 추가(상세 템플릿 공용 — RemindersContext include) |
| `app/controllers/viewer_controller.rb` | refusal 접수 완료 분기(thanks_path_for — refusal은 전용 완료 화면), refusal_thanks 액션·가드·비인증 허용 추가. rate_limit은 기존 create 경로 그대로 적용 |
| `app/views/app/invoices/show.html.erb` | ① 초안 발행을 SHARE-6 체크박스 폼으로 교체(기본 체크 — LP-14 카드⑤ 톤 문구 "청구서를 보내는 첫 안내도 받을돈 명의로 대신합니다", 422 재렌더 시 params로 체크 상태 복원) ② "자동 안내 현황" 섹션 신설 — 상태 배지·보류/재개 토글(REM-11 「보류하기」과 동일 엔드포인트)·수동 발송 버튼(다음 안내 라벨 + Free 안내 문구 REM-8)·발송 이력 목록(REM-6 — 일시·라벨·채널·예약 시각·상태 배지·스킵 사유) ③ 수신거부 안내 박스(VIEW-7 — 즉시 중단 명시) ④ 원클릭 마감 폼에 PAY-4 감사 체크박스(기본 켬) |
| `app/views/app/clients/show.html.erb` | "자동 안내 상태" 카드 — 배지 + 보류/재개 버튼, 수신거부는 안내만(액션 없음) |
| `app/views/app/clients/_client.html.erb` | 목록 카드 — 수신거부·보류 배지(정상은 무표기) + 푸터에 보류/재개 소형 버튼 |
| `app/views/viewer/show.html.erb` | VIEW-5 고지 아래 "추가 안내 수신 거부" 작은 링크(`<details>` — JS 없는 의사 재확인 단계, VIEW-1 인앱 대응) → kind=refusal button_to 접수. VIEW-8 화이트리스트 내 요소만, ③→① 링크 없음 |
| `test/controllers/app/invoices_controller_test.rb` | **의도된 동작 변경 2건의 기대값 갱신**(신규 테스트는 Phase 7 Tester 범위): ① 발행 플래시 문구 — SHARE-6 안내 포함 문구(파라미터 미전송=기본 켬 검증을 겸함) ② 초안 상세 DOM — 발행 button_to가 SHARE-6 체크박스 폼으로 바뀐 것(form action·_method=patch·send_notice 0/1·submit confirm) |

## Rule ID별 구현 매핑 (3-b)

| Rule ID | 구현 |
|---|---|
| REM-6 | 청구서 상세 "발송 이력" — 최신순 전 시도(성공·실패·제외)·한글 라벨·채널(자동/직접/나에게)·예약 시각·스킵 사유 문구. 삭제 경로 없음(뷰에도 없다) |
| REM-7 | 청구·거래처 단위 보류/재개 member 액션 + 상세·목록 토글 버튼. 청구 보류 = REM-11 「보류하기」와 동일 엔드포인트/동작 |
| REM-8 | "지금 1통 보내기"(post remind) — origin=manual로 SendService 호출, 가드·상한·창 동일 적용. Free 안내 문구("무료 플랜은 자동 발송이 없습니다 — 버튼으로 직접 안내") + 실패·제외 사유 플래시. 수동은 가드 통과 상태에서만 노출(reminders_active?) |
| REM-11 | 보류 버튼이 사전통보 취소 창 액션과 동일 동작(REM-7 경로 공유) |
| REM-12/13 | 종결 상태 배지 + 안내 박스("정기 안내를 마무리했습니다") — 종결 후 수동 버튼 미노출(가드 FINISHED와 정합) |
| SHARE-6 | 발행 폼 체크박스(기본 체크, hidden 0+1 쌍 — 해제 명시 전송) → issue! 성공 후 DeliverJob(issue_notice) 인큐. 성공 플래시도 분기 |
| PAY-4 | 원클릭 마감 폼 감사 체크박스(기본 켬 — 미전송도 켬 해석) → RecordService notify_thanks. 부분입금 폼은 대상 없음(REM-4 partial_paid는 무조건 인큐 — 3-a) |
| VIEW-7 | 뷰어 하단 수신거부 진입(details 재확인 → refusal 접수 → 전용 완료 화면) + U1 화면 수신거부 배지·안내 박스(재개 경로 없음 — P1) |
| VIEW-8 | 뷰어 신설 요소는 고지 아래 거부 진입뿐 — 마케팅·③→① 링크 없음(SURF-4) |
| PROMISE-2 | 수신거부 접수도 가입·입력 없는 button_to 단일 액션(기존 rate_limit 10회/10분 경로 재사용) |
| PLAN-3 | 수동 발송 플래시·이력 배지로 상한 도달(CAP_REACHED) 사유 표시 — 상한 자체는 3-a 서비스가 담당 |
| TIME-1 | 이력 일시 표기 display_datetime(KST), 플래시의 창 안내(평일 09~18) |

## 설계 판단 사항 (3-b — 지시서·인계 해석)

1. **수동 발송 템플릿 산정을 컨트롤러 계층(RemindersContext concern)에 둠** — "현재 상황에
   맞는 다음 1통"의 산정 로직이 3-a 서비스에 public 진입점으로 없었다(DispatchService#steps_for는
   private·스캔 전용). 백엔드 수정 금지 제약이라 DispatchService의 트랙·분기 판정(약속 트랙 우선,
   D+1 열람 분기 고정, 만기일 구간 버킷팅)을 재현했다. 서비스로 이동하는 것이 바람직하면
   후속 위임에서 `Reminders::ManualStepService` 등으로 추출 권장 — concern은 3개 컨트롤러가
   상세 화면 컨텍스트로 공유하므로 이동 시 호출점만 바꾸면 된다.
2. **보류 마킹은 touch, 재개는 update_column(nil)** — 3-a가 모델 뮤테이터를 만들지 않았고
   RegisterService의 선례(update_column)와 동일 방식. INV-5 본문 불변 가드 대상 컬럼이 아니라
   우회가 무해하다. 모델 메서드(suspend_reminders!/resume_reminders!)로 뽑는 정돈은 후속 과제.
3. **수신거부 시 수동 발송 버튼을 숨김** — 가드(REFUSED)가 막지만, U1이 거부 의사를 우회해
   직접 발송하는 경로를 UI에서도 차단(P1). 거래처 보류·종결도 죽은 버튼 방지 차원에서
   reminders_active? 조건 노출.
4. **수신거부 완료 화면을 promise_thanks와 분리** — "발행인에게 전달했습니다" 톤은 옵트아웃
   접수와 결이 달라, 중단 사실 명시 + 거래 계속 가능 안내의 전용 최소 화면으로 만들었다
   (지시서가 허용한 "별도 최소 안내" 선택).
5. **SHARE-6·PAY-4 체크박스는 hidden 0 + checked 1 쌍** — "해제"가 명시 전송되고, 파라미터
   부재(구폼·외부 요청)도 기본 켬으로 해석된다(지시서의 "미전송 시 true"와 정합).
6. **수동 발송의 창 밖 동작** — SendService가 :rescheduled을 반환하면 "다음 평일 오전 9시에
   발송" 플래시로 안내한다. 단, 재예약 잡(DeliverJob)이 origin을 지정하지 않아 자동(auto)
   슬롯으로 실행되는 것은 3-a 구조상 그대로다(이력에 자동 발송으로 기록 — 사용자 영향 미미).
7. **기존 테스트 2건 갱신은 회귀가 아니라 의도된 동작 변경의 반영**이다 — 발행 플래시 문구와
   초안 발행 폼 DOM(SHARE-6). 나머지 498건은 무수정으로 통과했다.

## ✅ 해결 — 3-a 회귀 (INELIGIBLE_PLAN 자격 가드 범위 한정, 2026-11-04 반영)

**문제(기존)** — `Reminders::SendService#guard_failure`의 INELIGIBLE_PLAN 가드가 origin·템플릿
무관하게 모든 채무자 향 발송에 적용되어, Free 유저의 수동 발송(REM-8)과 1회성 3종(SHARE-6
issue_notice·PAY-2 partial_paid·PAY-4 paid_thanks)까지 skipped(INELIGIBLE_PLAN) 기록·무음 처리됐다.

**수정(반영)** — `app/services/reminders/send_service.rb` 1개 파일, 가드 1줄 + 헬퍼 1개 + 주석:

```ruby
# 변경 전
return "INELIGIBLE_PLAN" unless @invoice.user.reminder_eligible?
# 변경 후
return "INELIGIBLE_PLAN" if auto_sequence_step? && !@invoice.user.reminder_eligible?
```

- 신규 헬퍼 `auto_sequence_step?` — `@origin == "auto" && sequence_step?`(시퀀스성 7종 템플릿).
  자격 판정(`User#reminder_eligible?`)은 **자동 시퀀스성 발송에만** 적용된다.
- 가드 제외(수정 결과): ① origin=manual 수동 발송(REM-8 — Free 포함 플랜 무관), ② issue_notice,
  ③ partial_paid, ④ paid_thanks — 3종은 origin이 auto로 인큐돼도 시퀀스성 템플릿이 아니므로
  템플릿 키 판정으로 자동 제외된다.
- 유지: 상한(PLAN-3 CAP_REACHED)·수신거부(REFUSED)·보류(SUSPENDED)·종결(FINISHED)·상태
  (INVALID_STATUS) 가드는 전 채무자 향 발송에 그대로 적용. U1 향(noti_*)은 기존과 동일하게
  자격 가드 대상 아님(NO_PHONE만). DispatchService의 자동 스텝 스캔은 origin=auto+시퀀스성이라
  기존대로 자격 검사 대상(동작 변화 없음).
- 3-b 컨트롤러·뷰 무수정 — 동작 호환 확인.

**게이트(수정 후)** — `bin/rubocop` 151 files no offenses · `bin/rails zeitwerk:check` 통과 ·
`bin/rails test` 500 runs 0 failures(3115 assertions).

## 참고 (3-a 스키마 그대로 사용한 점)

- Invoice에 `has_many :message_logs` 연관이 없어 컨트롤러는 `MessageLog.where(invoice_id:)`
  스코프 조회로 적재했다(RemindersContext). 연관 추가는 백엔드 변경이므로 하지 않았다.
- `Reminders::DispatchService::CONFIRM_KEYS`는 public 상수라 읽기만 했다(수정 아님).

---

# Phase 6 리뷰 반영 결과 (2026-11-04)

05_review.md(CHANGES_REQUESTED — BLOCKER 2·CRITICAL 3·WARNING 5)의 지시 사항만 최소 수정했다.
기존 테스트 500건 무수정 통과(회귀 0), 신규 테스트는 Phase 7 Tester 범위로 작성하지 않았다.
핵심 경로 12건을 test 환경 `bin/rails runner`로 실행 검증해 **12/12 PASS**를 확인했다(아래 게이트 절).

## 게이트 결과 (Phase 6)

| 게이트 | 결과 |
|---|---|
| `bin/rails db:migrate` | 통과 — `20261104000003`(인덱스 재생성) up, schema.rb 갱신 |
| `bin/rails zeitwerk:check` | 통과 — "Otherwise, all is good!" |
| `bin/rubocop` | 152 files, **no offenses** |
| `bin/rails test` | **500 runs, 3115 assertions, 0 failures, 0 errors, 0 skips** — 기존 테스트 무수정 |
| `bin/ci` | 통과(rubocop 0 + brakeman 0경고 + test + seeds) |
| 라우트 헬퍼 실측 | `restart_reminders_app_invoice_path` 해석 확인 |
| runner 실행 검증 | B-1·B-1보조(partial_paid)·B-2×2·C-1×2·C-2×2·C-3×2·W-3·SEC-5회귀 — **12/12 PASS** |

## 이슈별 수정 매핑

### BLOCKER-1 — 1회성 채무자 템플릿 3종 상태 가드 제외 (수정)
`app/services/reminders/send_service.rb` — `guard_failure`의 `FINISHED`·`INVALID_STATUS` 두 가드를
`sequence_step?` 한정으로 변경(`return "FINISHED" if sequence_step? && @invoice.sequence_finished?` 등).
자격 가드의 `auto_sequence_step?` 패턴 준용(시퀀스성 7종에만 적용). 1회성 3종은 각 이벤트 시점의
상태가 곧 발송 전제임을 주석 명시 — issue_notice는 issued 전환 직후, partial_paid는
partially_paid 상태, paid_thanks는 paid 전환 직후. REFUSED·SUSPENDED는 1회성에도 유지(수신거부·
보류는 전 발송 차단이 명세 취지). 실행 검증: paid 청구 paid_thanks → sent, partially_paid 청구
partial_paid → sent.

### BLOCKER-2 — 창 밖 재예약의 origin 전달 (수정)
- `app/services/reminders/send_service.rb` `reschedule!` — `DeliverJob.perform_later`에 `@origin` 전달.
- `app/jobs/reminders/deliver_job.rb` — `perform(invoice_id, template_key, recipient_role, origin = :auto)`
  4번째 스칼라 인자 추가(기본 :auto — 기존 3인자 호출점은 자동 계열 전부라 무수정·호환). 잡 인자는
  문자열 스칼라라 규약 준수. 실행 검증: Free 수동 20시 재예약 → 다음 평일 09:30 실행 → sent·
  origin=manual(기존: INELIGIBLE_PLAN skip). Plus 수동분의 auto 오기록도 함께 해소.

### CRITICAL-1 — 멱등 판정 origin 무관화(수동 sent 단계의 자동 재발송 차단) (수정)
설계 결정: "동일 단계 1회" 판정과 "동시 슬롯 1개" 보장을 분리했다.
- **판정(앱 계층)**: `SendService#claim_log`의 자동 경로가 `step_sent?`(origin 무관 sent exists —
  채무자 향 한정)로 "이미 이 단계를 보냈는가"를 확인 → `find_existing_log`·`confirm_template_key`
  (DispatchService)의 origin 조건 제거. 수동 재발송(REM-8)은 멱등 판정 밖(claim 첫 줄 new_log! 직행)으로
  유지해 이력 누적·상한(PLAN-3)만 검사.
- **인덱스(DB 계층)**: `db/migrate/20261104000003_change_message_logs_idempotency_index.rb` — 기존
  `where origin = 0 AND recipient_role = 0`를 `where recipient_role = 0 AND status = 0`(pending)으로
  재생성. origin 조건 제거를 이행하면서 "수동은 멱등 대상 밖(sent·failed·skipped는 인덱스 밖 — 이력
  누적 유지)"을 DB 수준에서 실현하고, U1 향(recipient_role=1) 반복 허용 조건은 유지. 동시 경합
  (auto×auto)은 pending 유니크 선점 + new_log! rescue 흡수로 여전히 차단(SEC-5 회귀 검증: auto 2회 →
  sent 1건).
- `record_past_window_skip`의 exists?도 origin 무관으로 통일(어떤 경로의 기록이든 이 단계 기록이
  있으면 재기록하지 않음 — churn 방지 유지).
- 실행 검증: manual confirm_d1 sent → auto claim :duplicate·신규 로그 0건, confirm_template_key가
  manual sent 템플릿으로 고정.

### CRITICAL-2 — 사전통보를 발송 스캔과 동일 소급 창으로 통일 (수정·W-1과 공동 해소)
- `Reminders::DispatchService`에 공개 산정 진입점 `steps_due_today(invoice)` 신설 — call의 발송
  스캔이 쓰는 `steps_for`·`window_end`(소급 창)·origin 무관 미발송 판정(`step_sent?`)과 동일 논리.
  대상 키는 `PRENOTICE_KEYS`(confirm_d1·confirm_d1_opened·requeue_d7·final_d14·promise_overdue —
  연체·도과 단계. invoice_notice·promise_d1은 NOTI-1 만기 임박 계열로 REM-11 "연체 단계" 명세 밖).
- `Reminders::PrenoticeService#notify_prenotice_targets` — 기존 due_on 정확 매칭
  (오늘−1/−7/−14)을 `steps_due_today` 재사용으로 교체. 월요일 아침이 금·토·일 nominal 스텝을 전부
  사전통보하고 14시 발송과 같은 모집단이 된다. `PRENOTICE_STEP_OFFSETS` 상수는 제거(사용처 소멸).
- 실행 검증: 2026-11-06(금) 만기 건 → 11-09(월) 09시 noti_prenotice sent → 동일 14시 confirm_d1 sent
  (통보→발송 순서 정합).

### CRITICAL-3 — 시퀀스 수동 재개 진입점 신설 (수정)
- `app/models/invoice.rb` — `restart_sequence!` 신설(`finish_sequence!`의 대칭. sequence_finished_at
  해소·멱등·update_columns 우회). REM-12/13 "이후 재개는 U1의 수동 재요청으로만 가능"의 실행 지점.
- `app/services/reminders/dispatch_service.rb` — `restartable?(invoice)` 공개 판정 신설(재개 시
  발송될 미발송·창 내 스텝 존재. 전부 창 경과면 false → 재개 불가 안내·마킹 유지. 종결 시점에는
  D-1·약속 전날 스텝이 창 내일 수 없어 steps_due_today와 같은 모집합 — 주석 명시). 창 밖 미발송
  스텝은 기존 PAST_WINDOW 차단이 그대로 적용(무한 소급 없음).
- `config/routes.rb` — invoices member `post :restart_reminders`(상태 전환 예외 동사 — member 정당화).
- `app/controllers/app/invoices_controller.rb` — `restart_reminders` 액션(unsettled 스코프·
  Current.user 격리는 기존 before_action 준용). 성공 303 "정기 안내를 다시 진행합니다. 남은 단계부터
  이어서 보냅니다." / 재개 불가 303 alert(지시서 문구 톤 — P1·"안내" 어휘). 약속 트랙 종결(REM-13)도
  동일 진입점(재개 요청 → 미발송 약속 스텝 판정 → 남은 게 없으면 재개 불가 안내).
- `app/views/app/invoices/show.html.erb` — 종결 상태 안내 박스 문구 보강 + 액션 영역에
  「안내 다시 보내기」 button_to(종결 상태에서만 노출, turbo_confirm, 기존 재개 버튼과 동일
  emerald outline 톤·min-h-11).
- 실행 검증: 종결+창 내 미발송(final_d14 오늘) → restartable true·restart_sequence! 해소. 종결+미발송
  창 내 스텝 없음 → restartable false.

### WARNING-1 — 수동 발송 템플릿 산정 3중 복제 수렴 (반영)
C-2의 공용 판정 도입과 함께 수렴했다(대폭 구조 변경 아님 — 3-b가 예고한 "호출점만 교체" 경로).
- `DispatchService`에 `manual_step_key(invoice)` 공개 진입점 신설(기존 RemindersContext 로직을
  이식 — 트랙·분기(latest_promise·confirm_template_key)·만기 버킷 판정의 단일 출처).
- `app/controllers/concerns/reminders_context.rb` — `manual_template_key`를 서비스 위임 1줄로 축소,
  `latest_promise`·`manual_confirm_key` 복제본 삭제. 컨트롤러 플래시·뷰 @변수 인터페이스는 불변.

### WARNING-2 — 수동 재발송 연타 완충 (반영 불필요 — 이미 충족)
3-b의 「지금 1통 보내기」 button_to에 이미 `data: { turbo_confirm: "현재 상황에 맞는 안내 1통을
거래처에게 보냅니다. 발송하시겠습니까?" }` 확인 다이얼로그가 존재한다(show.html.erb 235행대). 지시서가
허용한 "확인 다이얼로그(뷰만) 수준"은 이미 구현된 상태라 추가 변경 없음. 상한(PLAN-3)이 최종 방어는
동일.

### WARNING-3 — noti_due_soon 일·월 만기 누락 (반영)
`PrenoticeService#notify_due_soon_targets` — due_on 범위를 "내일~다음 실행일(다음 평일)"로 확장
(`due_soon_range`). 월~목은 내일 1일(기존 동일), 금요일은 토·일·월 3건을 묶어 선행 통보. 실행 검증:
금요일 아침 토·일·월 만기 3건 → noti_due_soon 3/3 sent.

### WARNING-4 — 창 밖 재예약분 pending 이력 선기록 (반영)
`SendService#reschedule!` — 예약 시점에 `create_scheduled_log`(pending+scheduled_at=다음 평일 09시,
origin=접수 시점)를 먼저 남긴다. REM-6 가시성(이력 화면 「예정」 배지·예약 시각 표기)+잡 유실 시 흔적.
동일 단계 중복 예약은 재생성 인덱스(debtor×pending 유니크)로 흡수되며 첫 예약이 유효(예약 대상
시각은 항상 다음 평일 09시로 동일). DeliverJob 실행 시 기존 pending이 claim의 갱신 경로로 재사용되어
sent로 마킹된다(실행 검증 포함).

### WARNING-5 — message_logs FK cascade와 P4 정합 (검증 통과로 기록 — 현행 유지·스키마 변경 없음)
연쇄 삭제의 실제 소실 경로를 전수 확인한 결과 현행 유지가 정당하다:
① **user 파괴(탈퇴)** — AUTH-1.5 "탈퇴 시 계정 데이터 삭제"는 명시된 삭제 시나리오이며, 이 경우
개인정보 삭제 의무가 발송 기록 보존보다 우선한다(P4는 "사용자 임의 삭제 불가"가 본지 — 규정에 의한
삭제는 예외). ② **invoice 파괴(초안 삭제)** — 초안은 뷰어 진입·발송 대상이 아니어서 발송 이력이
존재하지 않는다(실질 소실 없음). ③ **client 파괴(거래처 삭제 — ClientsController#destroy 존재)** —
해당 거래처 발송 이력이 연쇄 삭제된다. 이 경로는 P4와 긴장이 있으나(거래처 삭제가 발신 기록 삭제
우회가 될 소지), 거래처 삭제 자체가 CLIENT-1 명세 CRUD이고 이를 막는 것은 별도 Rule·UI 정책 과제다.
"발송 계열(invoice·발신 기록)의 U1 임의 삭제 경로가 없다"는 P4 본지는 유지된다 — 후속 과제로
기술 부채 노트에 기록했다. 리뷰 권장("스키마 변경은 불필요")을 따라 마이그레이션·주석 변경은 하지
않았다.

## 기술 부채 노트 (Phase 6 추가)

- 거래처 삭제 시 발송 이력 연쇄 삭제 — CLIENT-1 명세 범위 내에서 P4 보존 정책과의 균형 재검토
  (거래처 삭제 제한·이력 익명화 등은 별도 Rule 필요 — W-5 판단 기록 참조).
- PrenoticeService·DispatchService가 reminders_dispatchable 전체를 순회해 건별 steps를 산정한다
  (소급 창·약속 트랙 정확성 우선 — 기존 due_on 프리필터는 약속 트랙 건을 누락했다). 14시 스캔과
  동일한 순회 위계로, 스케일 커지면 due_on 범위 프리필터+약속 보유 건 병합 최적화 필요.

## 영향 범위 확인 (05_review.md 이외 무영향)

수정 파일: `db/migrate/20261104000003_*`(신규)·`app/models/{message_log,invoice}.rb`(주석·메서드
1개)·`app/services/reminders/{send,dispatch,prenotice}_service.rb`·`app/jobs/reminders/deliver_job.rb`·
`app/controllers/concerns/reminders_context.rb`·`app/controllers/app/invoices_controller.rb`·
`app/views/app/invoices/show.html.erb`·`config/routes.rb`·`db/schema.rb`. 그 외 코드·기존 테스트
500건·3-b UI 인터페이스(@변수·플래시)는 무수정으로 통과했다.

---

# Phase 6b — 재리뷰 신규 WARNING 반영 결과 (2026-11-04)

재리뷰(APPROVED)의 비차단 WARNING 2건(W-6·W-7) 중 지시된 범위만 최소 수정. 신규 테스트는
Phase 7 Tester 범위로 작성하지 않았다(테스트 전용 헬퍼 1파일은 W-7 권고의 "공용 stub 도입" 산출물).

## 게이트 결과 (6b)

| 게이트 | 결과 |
|---|---|
| `bin/rubocop` | 153 files, **no offenses** |
| `bin/rails zeitwerk:check` | 통과 — "Otherwise, all is good!" |
| `bin/rails test` | **500 runs, 3115 assertions, 0 failures, 0 errors, 0 skips** — 기존 테스트 무수정 |
| runner 실행 검증 | W-7 잡·스캔·사전통보·직접 주입 4경로 + W-6 origin 덮어쓰기 + U1 무영향 — **6/6 PASS** |

## 이슈별 수정 매핑

### WARNING-7 — 솔라피 주입점 체계 (반영 — Phase 7 착수 전 필수 사항 해소)
PortOne 패턴(`Subscriptions::UpgradeService`의 생성자 기본 인자 `client:` + `PortOneStubbing.with_portone_client`
클래스 생성 경로 교체)을 Solapi 도메인에 동일 구조로 이식했다. 목표: Phase 7 Tester가 stub 클라이언트를
주입해 실호출 0으로 잡·서비스 전 경로 테스트(리뷰어 실측 — RAILS_ENV=test의 `DeliverJob.perform_now`가
credentials의 유효 키를 로드해 실제 솔라피 HTTP_400 호출 발생).

- **서비스 체인 주입점** — 모두 `client:` 키워드(기본 nil·지연 생성 lazy — credentials 접근은
  첫 발송 시점으로 이연), 미주입 시 기본 래퍼 `Solapi::ClientService.new`:
  - `Reminders::SendService` — 기존 `solapi:` 키워드를 `client:`로 개명(외부 사용처 0건 확인 —
    개명 무영향). `Reminders::DeliverJob`·`App::InvoicesController#remind`는 서비스를 감싸기만
    한다(잡 인자는 스칼라만 — 래퍼 객체 직접 전달 불가).
  - `Reminders::NotifyUserService` — `client:` 주입 추가, SendService로 전달.
  - `Reminders::PrenoticeService`·`Reminders::DispatchService` — `client:` 주입 추가(initialize
    신설·인자 없는 new와 호환), 하위 발송 실행기로 전달(사전통보·자동 스캔 경로까지 stub 커버).
- **공용 stub 헬퍼** — `test/test_helpers/solapi_stubbing.rb` 신설(PortOneStubbing 준용 —
  `with_solapi_client(fake)`: `Solapi::ClientService.new`를 임시 교체·블록 종료 원본 복원).
  잡 계층(DeliverJob.perform_now)처럼 stub을 인자로 못 넘기는 경로의 방어선. 사용법은
  `deliver_job.rb`·헬퍼 주석에 명시("RAILS_ENV=test에서도 credentials의 유효 키가 로드되므로
  stub 없이 실행하면 실제 API를 호출한다").
- 실행 검증(6/6): SendService 직접 주입 발송·`with_solapi_client` 하의 `perform_now` 실호출 0
  (기존: 실API HTTP_400)·DispatchService 전달·PrenoticeService 체인(noti_prenotice+noti_due_soon).

### WARNING-6 — 슬롯 갱신 경로의 origin 왜곡 (반영)
`Reminders::SendService` — 발송 이력 갱신 경로(`skip!`·`deliver!`의 sent/failed 마킹)에
`origin: @origin`을 병기해 **마지막 실행 주체**가 origin이 되도록 덮어쓰기로 통일(지시 방침 —
"발송 이력의 사실"). 자동 스캔이 수동 failed 로그를 재사용해 sent로 마킹할 때 「거래처 · 직접 발송」
으로 남던 REM-6 채널 표기 왜곡 해소. 발송 사실·시점·상한 집계(PLAN-3)는 불변. 슬롯 재사용 판정
(claim_log·new_log! rescue)은 origin을 건드리지 않고 발송 실행 시점에만 갱신. U1 향은 전부 auto라
무영향(검증 포함). 실행 검증: manual failed(HTTP_400) 슬롯 → auto 재시도 → sent·origin=auto.

## 영향 범위 (6b)

수정 파일: `app/services/reminders/{send,notify_user,prenotice,dispatch}_service.rb`·
`app/jobs/reminders/deliver_job.rb`(주석)·`test/test_helpers/solapi_stubbing.rb`(신규 — 테스트
헬퍼). 호출점 무수정 확인: `solapi:` 키워드 외부 사용처 0건·DispatchService/PrenoticeService의
기존 `new`는 인자 없이 호환·컨트롤러·잡의 서비스 생성은 주입 없이 그대로. 기존 테스트 500건
무수정 통과.

### 후속 소형 수정 (2026-11-04 — 테스트 리포트 발견 사항 1 반영)
`send_service.rb` `after_send_hook`의 promise_overdue 경로 `NotifyUserService.new`에 `client: @client` 전달 보완 — W-7 주입 체계의 유일 누락 지점 복원(생성자 주입 테스트에서 실API 호출 방지). 게이트: `bin/rubocop` 168 files no offenses · `bin/rails test` 628 runs, 3717 assertions, 0 failures.



## 버튼 링크 변수 구현 (2026-11-06 — 솔라피 버튼 웹링크 변수 미치환 결함 수정)

솔라피 등록 알림톡 템플릿의 버튼 웹링크가 변수 규격(`https://#{url}`, `noti_prenotice`만
`https://#{complete_url}`·`https://#{pending_url}`)인데 `build_variables`가 본문 변수 8종만
조립해 버튼 치환값이 누락되던 결함 수정. `Reminders::SendService`에 상수 `LINK_HOST =
"badeuldon.kr"` 신설(템플릿에 `https://` 스킴이 박혀 있으므로 변수값은 **스킴 없이 host부터**)과
private 헬퍼 `button_url`·`prenotice_button_url`을 추가해 전 발송에 버튼 링크 변수를 실어 보낸다.
템플릿에 없는 변수는 솔라피가 무시하므로 [INFERENCE] 전 발송에 `url`을 실어도 무해 — 미실어
발송이 치환 실패 거부·`#{url}` 원문 노출 위험을 갖는 것보다 안전하다.

### 키 매핑 표

| 변수 키 | 대상 | 값 | 근거 |
|:---|:---|:---|:---|
| `url` | 채무자 향(debtor) 전 템플릿 | `badeuldon.kr/b/{token}` | ALIMTALK_TEMPLATES.md 버튼 명세 「웹링크 — 뷰어」 · VIEW-8(뷰어 밖 링크 금지) · SURF-4 |
| `url` | U1 향 `noti_due_soon` | `badeuldon.kr/app` | ALIMTALK_TEMPLATES.md 「대시보드에서 확인 — /app 전체 현황」 |
| `url` | U1 향 그 외 noti 전부 | `badeuldon.kr/app/invoices/{id}` | ALIMTALK_TEMPLATES.md 「대시보드에서 확인 — /app 해당 청구서」 |
| `complete_url` | `noti_prenotice` 전용 | `badeuldon.kr/app/invoices/{id}` | REM-11 버튼1 「마감하기」 — 마감(PAY-1)·보류(REM-7) 액션 공존 화면 |
| `pending_url` | `noti_prenotice` 전용 | `badeuldon.kr/app/invoices/{id}` | REM-11 버튼2 「보류하기」 — 버튼 라벨만 다르고 목적지 동일 |

경로 산정은 `Rails.application.routes.url_helpers.viewer_path(@invoice.token)`·
`app_invoice_path(@invoice)`(URL 하드코딩 금지 — 경로 헬퍼 사용)이며, `url`은 전 발송에
포함되므로 U1 향 `noti_prenotice`의 `url`도 청구서 상세로 산출된다(무해).

### 회귀·게이트

- 기존 테스트 무수정 통과 — variables 검증이 전부 키 단위 단언(`call[:variables]["금액"]` 등)이라
  키 추가분의 회귀 없음. 정확 해시 비교 테스트 0건 확인(`send_service_test.rb`·
  `prenotice_service_test.rb` 포함 전 test/ 검색). 신규 시나리오 테스트는 Tester 영역으로 미작성.
- 게이트: `bin/rubocop` 168 files, no offenses · `bin/rails zeitwerk:check` all good ·
  `bin/rails test` 628 runs, 3717 assertions, 0 failures, 0 errors, 0 skips.

### [INFERENCE] 갱신

- url 변수값 규격(스킴 제외·host부터)은 솔라피 검수본(`https://#{url}` 버튼 웹링크 등록) 기준
  해석 — **실발송 시 최종 확인 필요**(버튼이 실제 치환된 링크로 열리는지 라이브 1건 검증).
  기존 [INFERENCE] "솔라피 라이브 실측(발송 응답 필드·알림톡 1건 실발송 검증)"에 본 항목이
  포함된다.

---

# 솔라피 래퍼 실측 스펙 반영 (2026-11-06 — HTTP_400 거부 원인 확정·수정)

운영 issue_notice 발송이 솔라피에서 HTTP_400으로 거부됨(message_logs 1행: status=failed,
error_code=HTTP_400, error_message="Solapi::ApiError" — 본문 누실). 공식 문서 대조로 원인 2건
확정 후 래퍼(`app/services/solapi/client_service.rb`)를 수정했다.

## 400 원인 (공식 문서 solapi.com/developers/api/messages-ata 예시 대조)

1. **바디 최상위 키** — 구현이 `{"message": {...}}`(단수)였으나 실제 규격은
   **`{"messages": [ { ... } ]}` 배열**. 단수 구조가 400 거부의 직접 원인.
2. **variables 키 형식** — 구현이 순수 키(`{"발행인명": "..."}`)였으나 실제 규격은
   **`{"#{발행인명}": "..."}` — 키에 리터럴 `#{` `}` 포함**(문서 예시: `"#{고객명}": "홍길동"`).

text 필드는 템플릿+variables 방식(방법1)에서 선택 — 미포함 유지.

## 수정 내용

| 수정 | 내용 |
|:---|:---|
| `send_alimtalk` 바디 | `{ messages: [ { to:, from:, kakaoOptions: { pfId:, templateId:, variables: } } ] }` — 공식 예시 그대로 |
| `wrap_variables` 신설(래퍼 private) | 순수 키 → `"#{키}"` 래핑을 송신 직전 수행. `"##{k}"` 보간은 `"#발행인명"`이 되는 함정이라 `format('#{%s}', key)`로 조립. 도메인 계층(SendService 조립·message_logs.variables P4 스냅샷)은 **순수 키 유지** — 스펙 변환은 래퍼 단일 책임 |
| `parse` 오류 본문 fallback | `payload[:message] \|\| payload[:errorMessage] \|\| raw 본문`. `parse_body` 신설 — JSON 파싱 실패·비객체 JSON을 빈 해시+raw 원문으로 정규화해 `JSON::ParserError`가 ApiError 정규화를 우회하는 것을 차단. 이번 실측의 error_message 본문 누실 재발 방지(P4) |
| `dry_run:` 키워드 신설 | 아래 dryRun 욕법 참조 |
| [INFERENCE] 마킹 해제 | 엔드포인트·바디·variables 키·HMAC 인증(400 도달 = 인증 통과 실측)·발신번호 정규화(solapi-nodejs phoneNumberSchema 소스 확인) 확정. **잔여 추정: 성공 응답 필드 구조(messageId 위치)만 유지** |

`Reminders::SendService`는 무수정 — 순수 키 전달·message_logs 스냅샷이 원래 계약대로라 래퍼 측
래스펙 변환만으로 정합(`send_service_test.rb` 38건 전부 무수정 통과).

## dryRun 용법 (지시 전제와 다른 확인 결과 — 문서 전수 확인 근거)

- **솔라피 API에 dryRun 파라미터는 존재하지 않는다**(2026-11-06 확인 — solapi.com/developers/api/messages·messages-ata·msg-groups-createMessageGroup·msg-groups-sendGroupMessage 어디에도 없고, 공식 SDK solapi-nodejs·solapi-kotlin 요청 모델 소스에도 부재. GitHub 코드 검색에서 solapi 조직 전체 dryRun = MCP 서버의 클라이언트 사이드 프리뷰 플래그뿐).
- 문서화된 유일한 사전 검증 옵션은 send-many의 **바디 필드 `strict`**(boolean, 기본 false — 유효 문자·제목·템플릿 사전 검사; 고속 접수 미지원)다.
- 따라서 `dry_run: true`를 **래퍼 수준 실호출 스킵**으로 구현: 요청(바디·경로)을 규격대로 조립한 뒤 네트워크 연결 없이 `{ dryRun: true, path:, body: }`를 반환. 콘솔·테스트에서 스펙 검증용. [INFERENCE] 항목이 아님 — "API 파라미터 부재"가 확인 결과이고 그 근거를 주석에 기록.

## 테스트 갱신

- `client_service_test.rb`: 바디 단언을 messages 배열·variables `#{}` 래핑으로 교체(테스트명·단언 문자열의 `#{...}`는 `\#{`·`\{` 이스케이프로 보간 회피), dry_run 스킵 단언(starts·requests 공백+반환 스펙) 추가, errorMessage fallback·비JSON raw 본문 보존 케이스 추가(+3).
- 게이트: `bin/rubocop` 168 files, no offenses · `bin/rails zeitwerk:check` all good ·
  `bin/rails test` 631 runs(+3), 3734 assertions, 0 failures, 0 errors, 0 skips.

## 잔여 기술 부채 (갱신)

- 성공 응답 필드 구조(단일 send 응답의 messageId 위치) — [INFERENCE] 유지. `provider_message_id`는 최상위 `messageId`→`message.messageId` 순 탐색. 라이브 1건 실발송 시 확정.
- 위 dryRun 확인으로 "솔라피 라이브 실측" 기술 부채 중 **스펙 추정 항목은 해소** — 남는 것은 실발송 1건 검증(템플릿 버튼 치환·성공 응답 필드)뿐.

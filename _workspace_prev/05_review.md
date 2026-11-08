# 05_review — F-REM 리마인더 시퀀스 (Phase 5 + Phase 6 재리뷰, 2026-11-04, Reviewer)

status: **APPROVED** (Phase 6 재리뷰 기준 — BLOCKER 0 · CRITICAL 0 · 잔존 WARNING 2)

> 이력: Phase 5(1차) **CHANGES_REQUESTED** — BLOCKER 2·CRITICAL 3·WARNING 5 → Phase 6 수정 반영 →
> 아래 "Phase 6 재리뷰" 절의 해소 확인 후 종판 갱신. 1차 리뷰 전문은 문서 하단에 보존한다.

---

# Phase 6 재리뷰 (2026-11-04)

## 검증 방법

- 원 이슈 5건 전부를 수정 전 재현에 썼던 test 환경 `bin/rails runner` 패턴으로 **실행 재검증**(S1~S9, 아래 표) — 코드 리딩만이 아닌 동작 확정
- 게이트 교차 검증(자체 재현): `bin/rails test` **500 runs, 3115 assertions, 0 failures, 0 errors, 0 skips**(기존 테스트 무수정 통과 — 회귀 0 확인) · `bin/rubocop` **152 files, no offenses** — 구현 보고(03_implementation.md Phase 6 절)와 일치
- 마이그레이션 `20261104000003`(인덱스 재생성)·schema.rb(`idx_message_logs_debtor_pending_uniq`, `where recipient_role = 0 AND status = 0`) 확인

## 원 이슈 해소 확인 (실행 검증)

| 이슈 | 해소 구현(코드) | 실행 검증 | 판정 |
|---|---|---|---|
| **B-1** PAY-4 paid_thanks 전량 차단 | `guard_failure`의 FINISHED·INVALID_STATUS를 `sequence_step?` 한정으로 변경 — 1회성 3종(issue_notice·partial_paid·paid_thanks)은 상태 가드 제외. REFUSED·SUSPENDED는 1회성에 유지(명세 취지 — 전 발송 차단) | **S1** paid 청구 paid_thanks → `:sent`(수정 전 `INVALID_STATUS` skip). **S1b** partially_paid 청구 partial_paid → `:sent`. 시퀀스 스텝은 여전히 상태 가드로 차단됨(유지 확인) | 해소 |
| **B-2** Free 수동 창밖 재예약 실종(REM-8) | `DeliverJob#perform` 4번째 인자 `origin = :auto`(기존 3인자 호출점 호환) + `reschedule!`가 `@origin` 전달 | **S2f** 토 20시 Free 수동 → `:rescheduled` + pending(manual, sched=월 09시) 선기록 → 월 09시 실행 → `:sent`·로그 1개·origin=manual. **S2g** 창밖 2회 재예약 → pending 1개(유니크 흡수). Plus 수동분 auto 오기록도 해소 | 해소 |
| **C-1** 수동 sent 스텝의 자동 재발송(SEC-5) | `step_sent?`(origin 무관 sent — 채무자 향 한정)를 claim_log에 삽입, `find_existing_log`·`confirm_template_key`·`record_past_window_skip`의 origin 조건 제거, 인덱스를 `recipient_role=0 AND status=0`(pending)으로 재생성 | **S3** manual confirm_d1 sent → auto `:duplicate`·로그 증가 0·`confirm_template_key`가 manual sent 템플릿으로 고정. **S6** auto×auto 2회 → sent 1건 | 해소 |
| **C-2** 주말 nominal 월요일 발송의 사전통보 누락(REM-11) | `DispatchService#steps_due_today` 공개 진입점(발송 스캔의 steps_for·소급 창·step_sent?와 동일 논리)을 `PrenoticeService`가 재사용 — 통보와 발송이 같은 모집단 | **S4** 금(11-06) 만기 → 월(11-09) `steps_due_today=["confirm_d1"]` → 09시 noti_prenotice `:sent` → 14시 confirm_d1 `:sent`(취소 창 정합). `PRENOTICE_KEYS`(D+1/7/14+promise_overdue — invoice_notice·promise_d1 제외)는 REM-11 "연체 단계" 문언과 정합 | 해소 |
| **C-3** REM-12/13 수동 재개 경로 부재 | `Invoice#restart_sequence!`(종결 해소·멱등) + `DispatchService#restartable?`(창 내 미발송 스텝 존재 판정) + `post :restart_reminders` 라우트·액션·「안내 다시 보내기」 버튼(종결 상태 노출·turbo_confirm) | **S5a** 종결+final_d14 오늘 → restartable `true`·해소 후 finished `false`. **S5b** 전 스텝 소진+재종결 → `false`·"다시 보낼 단계 없음" 안내(재개 요청 거부·마킹 유지) | 해소 |

## C-1 분리 설계(앱 계층 판정 + pending 슬롯 인덱스) 정합 판정

지시 확인 3점 + 보너스 1점:

1. **auto×auto 경합(SEC-5)**: 부분 유니크 인덱스(debtor×invoice×template×pending)가 "동시 진행 슬롯 1개"를 DB에서 보장하고, `new_log!`의 RecordNotUnique rescue + `in_flight?`(1분)가 패자를 `:duplicate`로 흡수 — S6 실행으로 sent 정확히 1건 확인. "동일 단계 1회"는 `step_sent?`(앱 계층, origin 무관 sent)가 담당. 책임 분리가 명확하고 재시도(DeliverJob retry·스캔 재실행)에서 같은 판정점을 공유 — **정합**.
2. **수동→자동 재발송 차단**: `step_sent?`가 manual sent를 포함해 자동 claim을 차단(S3), 자동 스캔의 분기 고정(`confirm_template_key`)도 manual sent를 존중(S3). 수동 재발송(REM-8) 자체는 claim 첫 줄 `new_log!` 직행으로 멱등 판정 밖 — 이력 누적·PLAN-3 상한 검사는 유지 — **정합**.
3. **U1 향 반복 허용**: `step_sent?`의 `return false unless debtor?`와 인덱스의 `recipient_role = 0` 조건이 U1 향을 멱등 대상 밖으로 유지 — **S9** 실행: 다른 날 사전통보 2회 `:sent`, 같은 날 재실행 `:duplicate` 흡수(scheduled_at 기준). **정합**.
4. **(보너스) 수동 진행 중 자동 충돌**: **S8** — 수동 pending(진행 중) 상태에서 자동 claim → `:duplicate`로 흡수. 기존(1차 리뷰 시점)에는 수동이 무조건 새 이력을 만들어 동시 이중 발송이 가능했으나, pending 유니크가 origin 무관 슬롯으로 작동해 "동시 진행 1개"가 수동×자동 조합에도 적용됨 — SEC-5 관점 **개선**.

## WARNING 반영 확인 (1차 W-1~W-5)

| | 반영 | 확인 |
|---|---|---|
| W-1 스텝 산정 3중 복제 | `DispatchService#manual_step_key` 공개 진입점으로 수렴 — RemindersContext는 위임 1줄, `manual_confirm_key`·`latest_promise` 복제본 삭제. C-2의 `steps_due_today`와 함께 산정의 단일 출처 확립 | 해소 |
| W-2 수동 연타 완충 | 기존 turbo_confirm("…발송하시겠습니까?")이 이미 존재 — 지시서가 허용한 수준 충족, 추가 변경 없음 | 해소(기존 충족) |
| W-3 noti_due_soon 일·월 만기 누락 | `due_soon_range`(내일~다음 실행 평일) — 월~목 1일, 금요일은 토·일·월 3건 묶음 선행 통보 | 해소 |
| W-4 재예약분 이력 미기록 | `reschedule!`의 `create_scheduled_log`(pending+scheduled_at 선기록) — S2f·S2g로 선기록·중복 예약 흡수 확인 | 해소 |
| W-5 FK cascade·P4 | 현행 유지 + 판단 근거 기록(탈퇴 AUTH-1.5는 규정에 의한 삭제로 P4 "사용자 임의 삭제 금지"와 구분, 초안 삭제는 이력 없음, client cascade만 잔존 — 기술 부채 노트에 추적 항목 기록됨) | 수용(기록 완료) |

## 신규 이슈 (Phase 6 수정으로 관찰 — WARNING 2건, 비차단)

### WARNING-6: 슬롯 갱신 경로의 origin 왜곡(REM-6 채널 표기)
- 위치: `app/services/reminders/send_service.rb:78-89`(`new_log!`의 RecordNotUnique rescue → 로그 반환) — claim_log 갱신 경로 전반
- 자동 발송이 수동 failed 로그(또는 1분 경과 부실 pending)를 슬롯으로 재사용해 sent로 마킹하면 이력의 origin이 `manual`로 남는다 — 자동 스캔이 보낸 발송이 「거래처 · 직접 발송」으로 표기된다. **실행 확인(S7)**: manual failed(HTTP_400) 로그 존재 → auto 재시도 → `:sent`, 로그 origin=`manual`. 발송 사실·시점·상한 집계는 정확하고 발생 조건(수동 발송이 확정 실패한 스텝을 자동이 재시도)도 희박하다 — 비차단.
- 권고: 갱신 경로 재사용 시 `origin`을 현재 실행 주체로 갱신(`log.update!(status: :sent, origin: @origin, …)`)하거나, 최소 `deliver!`의 갱신에 origin을 병기. 다음 해당 파일 접촉 시 반영으로 충분 — 재리뷰 불요.

### WARNING-7: DeliverJob에 솔라피 stub 주입점이 없어 잡 계층 검증이 실API 호출을 유발할 수 있음
- 위치: `app/jobs/reminders/deliver_job.rb`(SendService를 solapi 주입 없이 생성)
- 재리뷰 검증 중 **실측**: RAILS_ENV=test에서 `DeliverJob.perform_now`로 재예약 경로를 실행하자 실제 솔라피 API 호출이 발생(응답 HTTP_400 — 테스트 환경 credentials에 유효 키 등록 상태). AGENTS.md 테스트 전략("외부 API는 테스트에서 stub/wrapper 주입 — 실 호출 금지")의 잡 계층 구멍 — 지금까지의 500 테스트는 잡이 발송에 도달하지 않아 무해했으나, Phase 7이 DeliverJob 재시도(retry_on) 경로를 테스트하면 동일 위험.
- 권고(Phase 7 착수 전): 테스트 환경에서 Solapi 진입점을 가로는 공용 stub(예: `Solapi::ClientService`의 테스트 전용 wrapper 주입 또는 `deliver_job` 인자에 선택적 주입) 도입. 재리뷰 조건 아님 — Tester에게 필수 전달 사항.

## 기타 확인 (새 회귀 점검 — 지시 3)

- `restartable?`·`steps_due_today` 재사용: PRENOTICE_KEYS 기반이지만 재개의 실제 발송은 `call`의 steps_for 전체(invoice_notice·promise_d1 포함)가 담당 — 재개 후 dispatchable 복귀·남은 스텝 이어 발송·PAST_WINDOW 차단(무한 소급 없음)·상한(PLAN-3) 유지로 REM-12 "발송이 무한히 이어지는 경우는 존재하지 않는다" 준수. 재약속 시 안내 박스 문구가 재개 진입을 안내해 UX 간극(약속일 미래면 restartable? false)을 완화 — 구조적 문제 없음.
- `create_scheduled_log`와 인덱스 상호작용: U1 향은 `reschedule!` 경유 불가(call이 debtor? 한정) — pending 유니크가 사전통보 멱등을 침해하지 않음(S9로 확인).
- 인덱스 재생성 마이그레이션: 운영 DB에 message_logs 테이블이 아직 없음(F-REM 미배포) — 순차 실행 시 기존 데이터 위반 가능성 없음.
- 기존 500 테스트 무수정 통과 — restart·steps_due_today·인덱스 변경의 기존 동작 회귀 0.

## Phase 6 종판

**APPROVED** — 원 이슈 5건(B-1·B-2·C-1·C-2·C-3) 전부 실행 검증으로 해소 확인, WARNING 5건 반영(4 해소·1 수용 기록), 신규 WARNING 2건(W-6·W-7)은 비차단·후속 접촉 시 반영 권고. W-7은 Phase 7 Tester 착수 전 필수 전달.

---

# [1차 리뷰 전문 — Phase 5 (2026-11-04, 보존)]

status(1차): **CHANGES_REQUESTED** — BLOCKER 2 · CRITICAL 3 · WARNING 5

## 리뷰 범위

- **신규**: 마이그레이션 2(`20261104000001`·`20261104000002`) · `app/models/message_log.rb` · `app/services/solapi/{client_service,api_error}.rb` · `app/services/reminders/{send,dispatch,notify_user,prenotice}_service.rb` · `app/jobs/reminders/{overdue_mark,prenotice,dispatch,deliver}_job.rb` · `app/controllers/concerns/reminders_context.rb` · `app/helpers/app/reminders_helper.rb` · `app/views/viewer/refusal_thanks.html.erb`
- **수정**: invoice·client·promise·user 모델 · view_events/track·promises/register·payments/record 서비스 · invoices·clients·payments·promises·viewer 컨트롤러 · invoices/clients/viewer 뷰 4 · routes.rb · recurring.yml · db/schema.rb · invoices_controller_test(갱신 2건)
- 판정 기준: **PRD.md v0.26**(특히 REM-2/3/4/7/8/11/12/13·PLAN-3·SEC-5·PROMISE-3/7·VIEW-7/8·SHARE-4/6·PAY-4·NOTI-1·TIME-1·P2/P4) · ARCHITECTURE_CONVENTION §4 · AGENTS.md UI 품질 기준 · `_workspace/03_implementation.md`

## 구현 보고 교차 검증 (자체 검증 재현)

- `bin/rails test` → **500 runs, 3115 assertions, 0 failures, 0 errors, 0 skips** — 03 보고와 일치
- `bin/rubocop` → **151 files, no offenses** — 03 보고와 일치
- **핵심 의심 경로 4건을 test 환경 `bin/rails runner`로 실행 검증** — B-1·B-2·C-1은 실행으로 재현 확정, V4(Free 창내 수동)는 정상 동작 확인
- 신규 테스트 부재는 3-b 명시 범위(Phase 7 Tester 몫) — 위반 아님

## Rule ID 준수 매핑 (검증 통과 영역 — 1차)

| 검증 항목 | 근거(원문 대조) | 판정 |
|---|---|---|
| REM-1·P2 — 발신자 비노출 | 래퍼는 `pf_id`·`sender_number`(서비스 명의) 고정, 변수 맵은 발행인 **표시명**만, U1 개인 번호·이름은 발신 경로 전무 | 통과 |
| REM-2 — 4단계 시퀀스·트랙 상호배타 | `base_steps`(D-1/D+1/D+7/D+14)·`promise_steps` 상호배타, 소급 창 산술상 하루 최대 1스텝 | 통과 |
| REM-3 — 평일 09-18 창 고정 | 상수 고정·해제 경로 없음·채무자 향만 적용·창 밖 다음 평일 09시 재예약 | 통과 |
| REM-4 — 열람 분기·부분입금 잔액 | `confirm_template_key` 분기+고정, partial_paid 변수 잔액·입금금액 | 통과 |
| REM-5 — SMS 대체 | 솔라피 템플릿 대체문자 위임(2026-11-03 확정) | 통과 |
| REM-6·P4 — 전 시도 기록 | sent/failed/skipped+사유·variables 스냅샷, 삭제 경로 없음 | 통과 |
| REM-7 — 건·거래처 단위 보류/재개 | 마킹+가드+UI 토글, 소유권 Current.user 스코프 | 통과 |
| REM-8 — Free 자동 차단·수동 허용 | 자격 가드를 자동+시퀀스성 한정(회귀 수정 확인), 창내 수동 `:sent` 실행 검증 | 통과(창밖 경로는 1차 B-2) |
| REM-10 — 솔라피 래퍼 | 단일 진입점·credentials dig 주입·HMAC·fail-fast·크레덴셜 무누출 | 통과 |
| REM-11 — 사전통보·취소 창 | 09시 통보 → 14시 발송 직전 가드 재확인 | 통과(주말 이원은 1차 C-2) |
| REM-12 — D+14 종결 | 발송 성공 시에만 finish_sequence! | 통과(재개 경로는 1차 C-3) |
| REM-13 — promise_overdue 종결 | 약속 트랙 대체·발송 성공 시 종결·noti_promise_unkept | 통과(재개 경로는 1차 C-3) |
| PLAN-3 — 상한 5통·산정 대역 | SEQUENCE_TEMPLATE_KEYS 7종 PRD 열거와 일치·1회성 3종 제외·auto+manual 합산·6통째 발송 경로 없음 | 통과 |
| PLAN-4 — 수금 패스 자격 | `reminder_eligible?` 단일 판정점 | 통과 |
| SEC-5 — 자동 동시 실행 멱등 | 부분 유니크 인덱스+슬롯 선점 — 잡 2회·스캔+재시도 흡수 | 통과(manual×auto는 1차 C-1) |
| PROMISE-3·7 / VIEW-7 / SHARE-4·6 / PAY-4 / NOTI-1 / TIME-1 | 1차 상세 매핑 통과(PAY-4 발송 경로는 1차 B-1로 별도) | 통과 |
| 데이터 무결성·보안 | 소유자 일치 검증·잡 인자 스칼라·retry_on/discard_on 명시·kind 화이트리스트·커밋 후 인큐·크레덴셜 무누출·Current.user 스코프 | 통과 |
| 아키텍처 §4 | 의존 방향 전부 준수(1차 W-1 재현 문제는 별도) | 통과 |
| UI 품질·VIEW-8·LP-12 | 상태색 3종·터치 타깃·마케팅 요소 없음·③→① 링크 없음·"안내" 어휘 | 통과 |
| 18종 템플릿 키·변수 정합 | 코드 키=ALIMTALK_TEMPLATES 등록본, base 변수 맵이 실사용 변수 전부 커버 | 통과 |

## 1차 이슈 (전부 Phase 6 해소 — 위 재리뷰 절 참조)

1. **BLOCKER-1** PAY-4 paid_thanks 100% 차단(INVALID_STATUS) → 해소(S1·S1b)
2. **BLOCKER-2** Free 수동 창밖 재예약 INELIGIBLE_PLAN 실종(REM-8) → 해소(S2f·S2g)
3. **CRITICAL-1** 수동 sent 스텝 자동 재발송(SEC-5) → 해소(S3·S6)
4. **CRITICAL-2** 주말 nominal 월요일 발송 사전통보 누락(REM-11) → 해소(S4)
5. **CRITICAL-3** REM-12/13 수동 재개 경로 부재 → 해소(S5a·S5b)
6. WARNING-1(산정 3중 복제)·W-2(연타 완충)·W-3(due_soon 주말)·W-4(재예약 이력)·W-5(FK cascade) → 해소 4·수용 기록 1

## 확인 요청 (1차 — 근거 기록, 유효 유지)

1. **부분입금 partial_paid 청구서당 1회**(3-a 판단 8): PRD PAY-2가 발송 횟수를 명시하지 않아 02_prd_update 해석("이벤트에서 정확히 1회")의 산물로 이해 — 잔액 변화 재안내 요구 시 별도 Rule 필요.
2. **[INFERENCE] 솔라피 스펙**(엔드포인트·인증·변수 무시·messageId): 배포 후 1건 실측 검증 필수(기술 부채).

## Tester 중점 테스트 제안 (Phase 7 — Phase 6 기준 갱신)

1. **B-1 회귀**: 전액 마감 → paid_thanks sent(수정 후 기대값). 부분입금 → partial_paid sent. 1회성이 REFUSED·SUSPENDED에서는 여전히 skip되는지(가드 유지).
2. **B-2 회귀**: Free + 18시 이후(TravelTo) remind → 재예약 pending(manual) 이력 → 다음 평일 09시 실행 sent·origin=manual.
3. **C-1**: 수동 confirm_d1 sent 상태에서 DispatchService.call → 두 번째 발송 부재(동일 단계 sent 1건). confirm 분기가 manual sent 템플릿으로 고정.
4. **C-2**: 금요일 만기 → 월요일 09시 steps_due_today/noti_prenotice → 14시 발송(통보→발송 순서). due_soon 금요일 토·일·월 3건 선행 통보.
5. **C-3**: 종결+창 내 미발송 스텝 → restart_reminders 303·종결 해소·다음 스캔 발송. 전 스텝 소진 종결 → 재개 요청 alert·마킹 유지.
6. SEC-5 경합: auto 2회·수동 진행 중 자동(S8 패턴) → sent 1건/:duplicate. U1 사전통보 다른 날 반복 sent(S9 패턴).
7. PLAN-3 경계: sent 4건 → 5통째 sent → 6통째 CAP_REACHED skip. 1회성 3종은 집계 제외.
8. PROMISE-7·VIEW-7: paid_report 후 스캔 발송 전무·noti_deposit_reply. refusal 즉시 전 청구 차단·noti_refusal·뷰어 refusal_thanks PRG·rate_limit 경계·인앱 뷰어 QA(VIEW-1).
9. **W-7 대비**: DeliverJob 재시도 경로 테스트는 solapi stub 주입 체계 선행(실호출 방지).

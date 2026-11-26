# 07_test_report — 수신 거부 재개 차단 + 상한 수동 합산·VIEW-7/PLAN-3·Q28 테스트 보강 + W-7 로그인 경화 (2026-11-26, Tester)

기준: `_workspace/01_plan.md`(시나리오 1~8)·`03_implementation.md`(§7·§8·§9 포함)·`05_review.md`(§6 Tester 중점 8건·W-7)·PRD §6.6 REM-7/8/11/12/13·§6.9 VIEW-7·§6.10 PLAN-3·§10 Q10/Q11/Q28. `app/` 소스 수정 0건 — `test/` 아래 5개 파일만 수정했다. 외부 API(솔라피·포트원·메일·바로빌) 실호출 0건 — 기존 `FakeSolapiClient` 주입·`with_solapi_client` 방어선만 사용했고, 잡 실행(`DeliverJob.new.perform`)은 전부 stub 블록 안에서 수행했다.

## 1. 추가·수정한 테스트 목록

신규 9건 + 기존 1건 보강 + 공용 로그인 헬퍼 1건. 지시서 A~D 블록과의 대응을 괄호로 표기했다.

| # | 파일 | 테스트명 | Rule ID | 구분 | 지시 |
|:--|:--|:--|:--|:--|:--|
| 1 | `test/services/reminders/send_service_test.rb` | 수동 시퀀스성·수동 1회성·자동의 혼합 4통에서 자동 5통째는 통과하고 6통째는 CAP_REACHED다 | PLAN-3·Q28 | 경계(4/5·3출처 혼합 합산) | A-1 |
| 2 | 동일 | 수동 포함 5통의 약속 트랙에서 promise_overdue 자동 발송은 CAP_REACHED로 막히고 종결 마킹·U1 통보도 없다 — 현재 동작 기록 | PLAN-3·Q28·REM-13·NOTI-1 | 예외(현재 동작 기록) | A-2 |
| 3 | 동일 | 상한 도달(수동 합산) 청구에서도 자동 1회성 partial_paid·paid_thanks는 발송되고 상한 집계는 늘지 않는다 | PLAN-3·Q10 | 예외(집계 밖) | A-3 |
| 4 | 동일 | 창 밖 수동 5번째는 다음 평일 09시로 예약되고 실행된 뒤 그날 14시 자동 단계는 CAP_REACHED다 | PLAN-3·Q28·REM-3 | 정상(재예약→실행→차단) | A-4 |
| 5 | 동일 | 창 밖 재예약분의 실행은 동일 템플릿 sent 이력이 있으면 duplicate로 흡수되고 예약 슬롯은 pending에 남는다 — 현재 동작 기록 | REM-3·SEC-5 | 예외(현재 동작 기록 — §3·§4 참조) | A-4 부산 |
| 6 | `test/services/reminders/dispatch_service_test.rb` | steps_due_today는 상한 직전(4통)에는 오늘 스텝을 돌려주고 도달(5통)하면 빈 배열이다 | PLAN-3·Q28 | 경계(4/5 직접 반환값) | A-5 |
| 7 | `test/controllers/app/invoices_reminders_test.rb` | 수신 거부한 거래처의 청구 보류 요청은 보류 마킹을 남기고 거부·종결 상태를 바꾸지 않는다 — 현재 동작 기록 | VIEW-7·REM-7 | 예외(직접 URL·현재 동작 기록) | B-7 |
| 8 | 동일 (기존 보강) | 수신거부 거래처의 수동 발송은 가드에 저지되고 사유가 flash로 안내된다 — GET 버튼 숨김 단언 2줄 추가 | VIEW-7·REM-8 | 예외(직접 URL 우회 확인) | B-6 |
| 9 | `test/system/app_invoice_reminders_test.rb` | 상한 도달 청구 상세는 상한 안내 상자·배지를 보이고 발송 버튼·다음 안내 라벨을 숨긴다 | PLAN-3·Q28 | 정상(브라우저 렌더) | C-8 |
| 10 | 동일 | 수신 거부 + 보류가 겹친 거래처 목록 카드는 재개·보류 버튼 없이 수신 거부 배지를 보여준다 | VIEW-7·W-1 | 예외(브라우저 렌더) | C-9 |
| 11 | `test/application_system_test_case.rb` | 공용 `log_in_as` 신설 — 제출을 `dom_click_button`으로 수행(W-7 경화) | — (테스트 기반) | — | D |

비고 — B-6은 지시서가 신규 테스트로 기술했지만 기존 테스트(`invoices_reminders_test.rb` "수신거부 거래처의 수동 발송은 가드에 저지되고…")가 POST 거부·`skipped`+`REFUSED` 기록·stub 호출 0을 이미 검증하고 있어(05_review §3 "REM-8 준수(불변)" 근거), 중복 신설 대신 같은 테스트에 "버튼 숨김(GET `assert_no_match` ×2)"을 보강해 우회 확인까지 한 번에 검증하도록 했다.

## 2. 실행한 명령과 회차별 결과 수치

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/models/message_log_test.rb test/models/invoice_test.rb test/services/reminders/send_service_test.rb test/services/reminders/dispatch_service_test.rb test/services/reminders/prenotice_service_test.rb test/controllers/app/invoices_reminders_test.rb test/controllers/app/clients_reminders_test.rb` | 최종 **157 runs, 784 assertions, 0 failures, 0 errors, 0 skips** |
| 동일 범위 + `test/services/reminders/` 디렉터리 지정 최종 확인 | **161 runs, 810 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rails test:system` — 경화 검증 3회 연속(파일 필터 없이 전체) | 1회차 **19 runs, 157 assertions, 0 failures** / 2회차 **19 runs, 157 assertions, 0 failures** / 3회차 **19 runs, 157 assertions, 0 failures** (소요 19.7s·21.4s·19.0s — 기존 17건 + 신규 2건 = 19건) |
| `bin/rubocop` | 431 files inspected, **no offenses**(최종 편집 뒤 재실행 포함 2회 모두 0) |

개발 중 내 테스트 오류 4건을 수정하며 재실행했다(코드 버그 아님 — §3). 전체 테스트(`bin/rails test`)는 지시대로 실행하지 않았다. git 상태 변경 명령(stash·checkout·restore·commit·reset)은 사용하지 않았다.

## 3. 코드 버그 분류

**이번 변경 범위(VIEW-7 재개 차단·PLAN-3/Q28 상한 합산·상한 화면 표시)의 코드 버그: 없음.** 신규 9건 전부 소스를 수정하지 않고 통과했다.

다만 테스트 작성 과정에서 **이번 변경과 무관한 기존 동작의 결함 후보 1건**을 발견했다(§4-1 — 기존 결함이므로 이번 런의 "코드 버그"로 분류하지 않고 현재 동작 기록 + 후보 보고로 처리한다).

참고 — 내 테스트 오류(자체 수정 완료): ① A-4에서 창 내 4통의 fake 호출 누적 미반영 ② A-5에서 SendServiceTest 전용 헬퍼(`sequence_sent_log`)를 DispatchServiceTest에서 호출 ③ A-5의 4통 구성에 수동 confirm_d1을 넣어 자동 스텝이 `step_sent?`로 제외됨 ④ C-9에서 `link_to`인 「수정」을 `assert_button`으로 단언(`assert_link`로 수정).

## 4. 현재 동작 기록으로 남긴 것(변경 가능한 후보)

1. **창 밖 재예약분의 동일 템플릿 흡수(기존 결함 후보 — 리팩터링 시 정합 권장)**. 창 밖 수동 발송은 다음 평일 09시로 예약되고("다음 평일 오전 9시에 발송됩니다" flash) `DeliverJob`이 실행하지만, `SendService#claim_log`의 manual 경로는 무조건 `new_log!`이고 그 INSERT가 예약 슬롯의 pending 부분 유니크 인덱스에 걸리면 복구 로직(`find_existing_log` — `.order(:id).first`)이 **가장 오래된 이력(이미 sent인 수동 발송)**을 돌려 `:duplicate`로 흡수한다. 결과: 예약 슬롯은 영구 pending으로 남고 발송은 일어나지 않는다. 같은 템플릿의 sent 이력이 없으면 슬롯이 재사용돼 정상 발송된다(테스트 #4가 그 경로). 수동 반복 발송이 허용된다는 REM-8 시맨틱(같은 파일의 "수동 재발송은 멱등 판정 밖" 테스트)과 상충하는 기존 동작이다. 이번 변경(상한 집계·VIEW-7)과 무관하고 리뷰 범위 밖이라 소스를 고치지 않았다 — 테스트 #5로 고정해 두었다.
2. **약속 트랙 상한 도달 시의 종결 마킹 없음·U1 통보 없음(Q28·NOTI-1 — 의도된 현재 동작)**. 상한 도달로 `promise_overdue`가 CAP_REACHED로 막히면 시퀀스 종결 마킹(`finish_sequence!`)도 `noti_promise_unkept`(약속 미이행 U1 통보)도 발생하지 않는다 — 둘 다 발송 성공 훅에 묶여 있기 때문. 테스트 #2가 단언으로 못 박았다. 상한 도달 청구는 화면의 「상한 도달」 안내로만 U1이 인지한다. 통보 누락이 문제라면 "U1 향은 상한 집계 밖" 같은 별도 결정이 필요하다(03 문서 §8 남은 우려 1과 동일 내용).
3. **수신 거부 거래처의 `suspend_reminders`는 보류 마킹을 남긴다(의도된 현재 동작)**. 버튼은 없고 직접 URL로만 닿으며, 마킹은 남지만 재개 경로가 막혀 영구 잔존한다. 발송에는 영향이 없다 — 마킹 후 수동 발송 요청의 스킵 사유는 SUSPENDED가 아니라 REFUSED다(거부 가드가 먼저다). 테스트 #7이 기록한다(05_review §5 관찰 3·03 문서 §8과 정합).

## 5. 다른 시스템 테스트 파일의 같은 로그인 패턴(수정 없이 보고)

동일한 `click_button "로그인"` 기반 자체 `log_in_as` 정의 4건 — 범위 확대 금지 지시에 따라 수정하지 않았다. 공용 케이스의 경화된 `log_in_as`는 자체 정의가 없는 파일에만 적용되며, 아래 파일들은 섀도잉으로 자체 정의를 계속 쓴다.

| 파일 | 위치 |
|:--|:--|
| `test/system/app_invoice_pdf_test.rb` | `:12` |
| `test/system/app_legal_document_pdf_test.rb` | `:15` |
| `test/system/app_invoice_form_scorecard_test.rb` | `:34` |
| `test/system/app_billing_channel_key_notice_test.rb` | `:32` |

**실측된 잔여 플레이크**: 경화 검증 도중 `app_invoice_pdf_test.rb`(PAY-6 PDF 케이스)의 로그인 제출이 1회 드롭됐다 — 실패 스크린샷(`tmp/screenshots/failures_test_paid_..._PAY-6-Q17-.png`)은 **두 필드가 모두 채워진 로그인 화면**으로, 05_review W-7이 기술한 현상(입력 유실이 아니라 제출 클릭 드롭)과 동일하다. 해당 파일은 자체 `click_button` 헬퍼를 쓰므로 이번 경화의 적용 밖이다. 위 4개 파일의 `log_in_as`를 공용 정의로 일괄 전환하면(각 파일의 자체 정의 삭제) 동일 효과가 적용될 것으로 판단된다 — 별도 결정 대상.

## 6. 남은 우려

1. **범위 밖 파일의 로그인 플레이크 잔존(§5)** — `bin/ci` 게이트가 시스템 테스트 전체를 돌리므로, 4개 파일을 전환하기 전까지는 간헐 재발 가능성이 남는다. 관측 빈도는 낮다(본 세션 전체 시스템 실행 7회 중 1회).
2. **테스트 #4·#5의 수동 템플릿 구성 현실성** — 창 내 4통을 수동 `issue_notice` 반복으로 설치한 것은 이 파일의 Q28 시나리오 선례(기존 "수동 issue_notice 5통…" 테스트들)를 따른 것이다. 실제 버튼(`manual_step_key`)은 만기 도과 청구에서 confirm_d1을 고르므로, 버튼 경유 시나리오는 §4-1의 흡수 동작과 결합해 "예약분이 실제로 sent 된다"는 전제 자체가 성립하기 어렵다 — §4-1 정합 시 함께 재검토 대상.
3. **`test:system`의 전체 실행 특성** — 포트원 런의 미커밋 시스템 테스트(`app_billing_channel_key_notice_test.rb` 등)가 함께 돌지만 대역 헬퍼만 쓰며 3회 모두 통과했다(실호출 없음 확인).
4. W-2(PRD 문언)·W-6(LAUNCH_TEST 재생성)은 문서 담당(오케스트레이터) 범위로 이번에 다루지 않았다.

## 8. W-7 후속(2차) — 시스템 테스트 로그인 헬퍼 공용화 (2026-11-26, Tester)

§5에서 남겨둔 4개 파일의 자체 `log_in_as`(동일 이름 섀도잉 — `click_button "로그인"` 제출)를 공용 헬퍼(`ApplicationSystemTestCase#log_in_as` — `dom_click_button` 제출, W-7 경화)로 전환해 §6-1의 잔여 플레이크 가능성을 닫았다. `app/` 소스 수정 0건, 수정 파일은 아래 4개의 시스템 테스트뿐이다.

### 8-1. 파일별 변경 내역

4개 모두 자체 정의가 공용 헬퍼와 **의미상 동일**(같은 `new_session_path`·라벨 "이메일"/"비밀번호"·성공 문구 단언 "로그인되었습니다."·시그니처 `(user, password: "password")`)이었고, 유일한 차이는 제출 방식(`click_button` vs `dom_click_button`)이었다 — 지시 기준 "정의 삭제 → 공용 헬퍼 사용" 케이스. 호출부(`log_in_as users(:delta)` / `log_in_as(user)` / `log_in_as user` / `log_in_as gamma`)는 전부 기본 password를 쓰므로 인자 변경 없이 그대로 동작한다.

| 파일 | 변경 | 이유·비고 |
|:--|:--|:--|
| `test/system/app_invoice_pdf_test.rb` | private `log_in_as` 정의(구 12-18행) 삭제, 공용 헬퍼 사용 주석 1행 추가 | W-7 실측 드롭이 관측됐던 바로 그 파일(§5 — PAY-6 케이스 1회 실패) |
| `test/system/app_billing_channel_key_notice_test.rb` | `private` + `log_in_as` 정의(구 30-38행) 삭제, 공용 헬퍼 사용 주석 1행 추가 | 포트원 런 산출 미추적 파일 — 로그인 헬퍼 부분만 변경, 나머지(채널 키 대역·단언) 무변경 |
| `test/system/app_legal_document_pdf_test.rb` | `log_in_as` 정의(구 15-21행) 삭제, 공용 헬퍼 사용 주석 1행 추가 | `fetch_pdf` 등 private 이하는 무변경(`private` 섹션 유지) |
| `test/system/app_invoice_form_scorecard_test.rb` | private 섹션의 `log_in_as`만 삭제(구 34-40행), 공용 헬퍼 사용 주석 1행 추가 | `seed_paid_invoice`는 사용 중이므로 유지 |

전환 후 `grep -rn "def log_in_as" test/` 결과는 공용 정의 1건뿐이다(섀도잉 0건 — 모든 시스템 테스트가 경화된 제출 경로를 탄다).

### 8-2. 실행 결과

| 명령 | 결과 |
|:--|:--|
| `bin/rails test:system` 3회 연속(파일 필터 없이 전체) | 1회차 **19 runs, 157 assertions, 0 failures, 0 errors, 0 skips**(33.1s) / 2회차 **19 runs, 157 assertions, 0 failures, 0 errors, 0 skips**(25.1s) / 3회차 **19 runs, 157 assertions, 0 failures, 0 errors, 0 skips**(26.4s) — 3회 모두 로그인 관련 실패 0건, 실패 스크린샷 미발생 |
| `bin/rubocop` | 431 files inspected, **no offenses** |

전체 테스트(`bin/rails test`)는 지시대로 실행하지 않았다. git 상태 변경 명령(stash·checkout·restore·commit·reset)은 사용하지 않았고, 외부 API(솔라피·포트원·메일·바로빌) 실호출 0건 — 기존 파일 머리의 `with_solapi_client`·`PortOneStubbing`·`FakePortOneClient` 대역을 그대로 두었다.

### 8-3. 남은 우려

1. **chromedriver 클릭 드롭은 우회일 뿐 근본 해결이 아니다** — `dom_click_button`은 DOM 레벨 클릭으로 우회하는 전략이며(§7·`application_system_test_case.rb` 주석), selenium/Chrome 버전 조합이 바뀌면 재검증이 필요하다. 3회 연속 통과는 로컬 환경 기준이다.
2. **`assert_text "로그인되었습니다."` 단일 단언 의존** — 로그인 성공 문구가 UI에서 바뀌면 공용 헬퍼를 쓰는 전체 시스템 테스트가 함께 실패한다(단일 출처화의 트레이드오프 — 실패 시 고칠 곳이 1곳으로 모이는 방향이므로 유지).
3. **이번 3회차에서 §5의 플레이크가 재현되지 않아 "수정으로 사라졌다"를 통계적으로 증명하지는 못했다** — 관측 빈도가 낮아(이전 세션 7회 중 1회) 3회로는 부족하지만, 구조적으로는 드롭 경로(`click_button`)를 제거했으므로 동일 현상의 재발 여지는 없다.

## 9. 3차 — 발송 슬롯 최종 논리·화면 분기 조합 (2026-11-26, Tester)

마지막 수정(7차 — C-1·W-1~W-5·W-7 반영)까지 포함한 발송 슬롯 논리와 청구 상세 화면에 대해, 구현자가 스스로 쓴 테스트 바깥의 반례를 추구했다. 기준: `_workspace/05_review.md` 마지막 절 "마감 리뷰 — 3~6차 변경분"(C-1·W-1~W-7·§2 경로별 추적 a~h·§6 Tester 중점 제안)·`03_implementation.md` §10·§11·§12(7차)·PRD §6.6 REM-3 "재예약분 실행 정합(2026-11-26 수정)"·§6.10 PLAN-3 끝부분. `app/` 소스 수정 0건, 수정 파일은 `test/` 아래 3개뿐이다. 외부 API 실호출 0건 — 기존 `FakeSolapiClient` 주입·`with_solapi_client` 방어선만 사용했고, 잡 실행(`DeliverJob.new.perform`)은 전부 stub 블록 안에서 수행했다. 임시 재현 테스트는 만들지 않았고 git 상태 변경 명령(stash·checkout·restore·commit·reset)도 사용하지 않았다.

### 9-1. 추가한 테스트 목록 (신규 8건)

| # | 파일 | 테스트명 | Rule ID | 구분 | 지시 |
|:--|:--|:--|:--|:--|:--|
| 1 | `test/services/reminders/send_service_test.rb` | 예약 슬롯 발송 뒤의 재실행은 자동은 duplicate로 흡수하고 수동은 재발송을 누적한다 | SEC-5·REM-8·C-1 | 경계(touch 효과 시간 경계) | A-3 |
| 2 | 동일 | 같은 단계 수동 발송 2회 재예약의 잡 2회 연속 실행은 슬롯 발송 + 새 이력 재발송으로 수렴한다 | REM-3·REM-8 | 예외(현재 동작 기록) | A-1 |
| 3 | 동일 | 창 밖 재예약된 partial_paid의 잡 2회 연속 실행은 슬롯 발송 + 새 이력 발송으로 2통이 된다 | Q23·REM-3 | 예외(현재 동작 기록) | A-5 |
| 4 | 동일 | 모호 실패 뒤 창 밖 재예약된 재시도는 다음 날 슬롯으로 발송하고 failed 이력은 보존된다 | REM-3·P4 | 정상(실패+재예약 결합) | A-2 |
| 5 | `test/controllers/app/invoices_reminders_test.rb` | 상한 도달 + 청구 건 보류가 겹친 청구 화면은 상한 상자만 보이고 발송·재개·보류 버튼이 없다 | PLAN-3·Q28·REM-7 | 분기 조합 | B-6 |
| 6 | 동일 | 상한 도달 + 수신 거부가 겹친 청구 화면은 거부 안내가 먼저이고 상한 상자·버튼이 없다 | VIEW-7·PLAN-3 | 분기 조합 | B-7 |
| 7 | 동일 | 상한 도달 + 종결(수신 거부 아님)이 겹친 청구 화면은 상한 상자를 보이고 다시 보내기 버튼이 없다 | PLAN-3·REM-12 | 분기 조합 | B-8 |
| 8 | `test/system/app_invoice_reminders_test.rb` | 수동 상한만 도달한 청구 상세는 보류하기와 한 줄 안내를 보이고 직접 발송 버튼·다음 안내 라벨을 숨긴다 | PLAN-3·W-3 | 정상(브라우저 렌더) | C |

기존 커버 확인(무수정) 2건 — 지시 A-4(U1 향 예정 알림 회귀)는 기존 테스트가 둘 다 이미 커버한다: 같은 `scheduled_at`의 sent 이력 흡수는 "U1 사전통보는 같은 예정시각 재실행을 흡수하고 다른 날은 새 이력이다 (S9)", 다른 날짜 stale pending이 있어도 오늘 예정 알림이 자기 이력으로 발송하는 것은 6차의 "U1 예정 알림은 다른 예정시각의 stale pending이 있어도 자기 예정시각의 새 이력으로 발송한다 (SEC-5·S9)". 지시 B-9(수동 상한만 도달 화면)는 7차의 "수동 상한만 도달한 청구 화면은 직접 발송 버튼·다음 안내를 숨기고 한 줄 안내를 보인다 (PLAN-3·W-3)"가 존재함을 확인 — 신규 중복 없음(단, 시스템 계층 동일 판정은 #8로 보강).

### 9-2. 현재 동작 기록 실측 (지시 1·5)

1. **이중 접수 + 이중 잡 실행(#2)** — 평일 20시에 같은 단계(confirm_d1) 수동 발송 2회 접수: 두 번 모두 `:rescheduled`를 반환하고, 회원에게는 "다음 평일 오전 9시에 발송됩니다" 안내가 2회 보인다. 예약 슬롯은 부분 유니크 인덱스 흡수로 1개만 남지만(첫 예약 유효 — 기존 W-4 테스트와 정합) `DeliverJob`은 접수 수만큼 2개가 큐에 쌓인다(`assert_enqueued_jobs 2`로 고정). 다음 날 09:00에 잡 2회 연속 실행: ① 1회차가 슬롯을 claim해 sent로 갱신·발송 ② 2회차는 남은 pending 슬롯이 없어 `new_log!`가 새 이력을 만들어 한 번 더 발송한다(수동 재발송 허용 — REM-8·멱등 판정 밖). 실측 결과: **sent 2건·pending 0건·stub 호출 2회** — 회원이 본 안내("09시에 발송")와 실제 발송 수(2통)가 수렴해 안내 거짓은 아니다. 같은 구조가 자동 1회성(partial_paid)에서도 동일하다(#3 — 과거 sent 1건 + 재예약분 → 잡 2회 실행 시 **sent 총 3건(과거 1+슬롯 1+신규 1)·pending 0·호출 2**. 이벤트성은 멱등 판정 밖이라 같은 이벤트의 잡이 2회 실행되면 같은 안내가 2통 간다 — Q23 "건마다 새 이력" 설계의 귀결).
2. **이중 발송의 성격 판정** — 두 건 모두 "코드 버그"가 아니라 REM-8(수동 재발송 허용)·Q23(이벤트성 멱등 밖)의 설계 귀결로 판정한다. 다만 잡 중복 인큐(동일 인자 2개)가 실제로 발생하는 경로는 reschedule!의 호출 수와 잡 큐의 신뢰성에 달려 있어, 큐 중복이 관측되면 "같은 단계 수동 발송은 잡 1개로 수렴" 정책(인큐 전 pending 슬롯 조회)을 별도 결정으로 검토할 여지는 있다. 발송 무결성·P4·상한 집계(Q11·sent만 집계)에는 영향이 없다.

### 9-3. 코드 버그 분류

**이번 반례 추구 범위(발송 슬롯 최종 논리·청구 상세 분기 조합)의 코드 버그: 없음.** 신규 8건 전부 소스를 수정하지 않고 첫 실행에서 통과했다. C-1의 touch 판정(`in_flight?`의 예약 슬롯 조건 + `mark_execution_started!`)·W-1의 자동 sent 재예약 금지·수동 상한 화면 분기 모두 반례를 흡수했다. 특히 #4(모호 실패 → 창 밖 재예약 → 다음 날 발송)는 5차 슬롯 우선 논리의 "failed + 슬롯" 경로가 실패 기록 1건과 성공 기록 1건을 모두 P4 보존하는 것을 직접 확인했다.

### 9-4. 실행한 명령과 회차별 수치

| 명령 | 결과 |
|:--|:--|
| `bin/rails test test/services/reminders/send_service_test.rb test/controllers/app/invoices_reminders_test.rb` | **81 runs, 564 assertions, 0 failures, 0 errors, 0 skips** (4.2s) — 신규 7건 포함, 첫 실행 통과 |
| `bin/rails test:system` — 파일 필터 없이 시스템 전체(태스크 특성) | **20 runs, 164 assertions, 0 failures, 0 errors, 0 skips** (20.7s) — 기존 19건 + 신규 1건, 1회 실행 통과(로그인 플레이크 재현 없음 — 실패 스크린샷 미발생) |
| `bin/rubocop` | 431 files inspected, **no offenses** |

전체 테스트(`bin/rails test`)는 지시대로 실행하지 않았다(오케스트레이터 실행).

### 9-5. 남은 우려

1. **잡 중복 인큐 수렴 정책(9-2의 성격 판정 후속)** — #2·#3이 고정한 "잡 2회 실행 = 발송 2통"은 수동·이벤트성 설계상 허용이지만, reschedule!가 접수 수만큼 잡을 쌓는 구조는 큐 중복·재시도와 결합하면 발송 수를 키운다. 운영에서 같은 안내 이중 접수가 관측되면 "예약 슬롯 존재 시 잡 인큐 생략" 또는 "잡 실행 시 pending 슬롯 없으면 재발송 생략" 중 하나를 별도 결정으로 검토한다(현재는 후자가 수동 재발송 허용과 충돌해 전자가 자연스럽다).
2. **U1 향·이벤트성의 잡 이중 실행 흡수는 `in_flight?` 1분 창에 의존** — 채무자 향 수동·1회성은 멱등 판정 밖이라 1분 창이 없고(claim_log가 `new_log!` 직행), 같은 잡이 1분 이내에 병렬 실행돼도 흡수되지 않는다(§10 남은 우려 3·§12 남은 우려 1의 승계). 부분 유니크 인덱스가 INSERT 경합만 막으므로 순차 2회 실행은 막을 수단이 없다 — 현재 기록(#2·#3)은 이 동작의 회귀 감지용이다.
3. **분기 조합 3건(#5~#7)은 배너 우선순위·버튼 행 숨김의 "현재 화면 계약"을 고정한 것** — 거부+상한 조합에서 상한 배지는 누적 표시된다(헬퍼의 badges는 합산 — 거부 배지와 상한 배지가 나란히 붙는다). 이 배지 조합의 가시성은 제품 판단 여지가 있어 단언에서 뺐다(배너·상자·버튼만 검증). 배지 정책을 바꾸면 이 테스트들은 영향받지 않는다.
4. **A-4·B-9의 기존 커버 재확인은 실행으로가 아니라 테스트 본문 대조로 판정했다** — 두 기존 테스트 모두 이번 전체 실행에서 함께 통과해 유효함은 확인됐다.


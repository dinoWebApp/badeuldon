# 01_plan — 수신 거부 청구의 재개 차단 + 발송 상한에 수동 발송 합산 (2026-11-25, 일반 모드·Full)

## 배경·발견 경로

- 런칭 테스트 체크리스트(`LAUNCH_TEST_CHECKLIST.md` §8)를 만들며 코드를 읽고 찾은 2건이다. 브라우저로 확인한 것은 아니다(2026-11-25 코드 기준).
- 사용자 지시(2026-11-25): "1번 2번은 자체적으로 판단해서 진행해주세요" — 승인 선택 질의는 사전 승인으로 갈음하고 제품 판단은 오케스트레이터가 내린다.

## 결정

| # | 문제 | 결정 | 근거 |
|:--|:--|:--|:--|
| 1 | 수신 거부한 거래처의 종결 청구에 「안내 다시 보내기」 버튼이 보이고, 요청도 "정기 안내를 다시 진행합니다"로 성공 안내하지만 발송은 영원히 되지 않는다(`restart_sequence!`는 `sequence_finished_at`만 지우고 `Client#refused_at`은 유지 — `reminders_dispatchable`에서 영구 제외). | 거부된 거래처의 청구는 버튼을 **노출하지 않고**, `restart_reminders` 요청은 **상태 변경 없이 사유 안내로 거부**한다. | VIEW-7(수신 거부 의사 표현 — U1이 되돌리지 않는다), 뷰 주석의 설계 의도("수신거부 → 안내만"), `ClientsController#resume_reminders` 주석("수신거부는 재개 대상이 아니다 — 채무자 의사"). 회원에게 틀린 안내를 주는 결함. |
| 2 | 자동 시퀀스 상한이 시퀀스성 템플릿 sent만 세어, 발행 안내(issue_notice) 문구로 수동 5통을 보낸 청구에도 다음 자동 단계가 발송된다(채무자 향 총 6통). | 자동 상한 집계에 **수동 발송(origin=manual, 템플릿 무관)을 합산**해 수동+시퀀스 합계 5통에서 자동 단계를 차단한다. 자동 1회성 3종(issue_notice·partial_paid·paid_thanks)은 계속 집계 밖. | PRD PLAN-3·Q11: "수동 발송도 템플릿 무관 총량 5통 하드리밋에 포함 … 상한의 산정 대상은 시퀀스성 자동 발송 **및 수동 발송**" — 종전 구현은 이 취지에 미달했다. Q10(자동 1회성 제외)은 유지. |

## 범위

### 수정 1 — VIEW-7·REM-12/13 (수신 거부 청구 재개 차단)

| 파일 | 변경 |
|:--|:--|
| `app/views/app/invoices/show.html.erb` | 버튼 분기 `elsif @invoice.sequence_finished?`에 `&& !@invoice.client.refused?`를 추가해 버튼·보조 문구를 숨긴다. 상태 배너는 이미 거부 안내가 우선이라 바꾸지 않는다. 주석(199~201행)의 설계 의도를 실제와 맞게 정정한다. |
| `app/controllers/app/invoices_controller.rb` | `restart_reminders` 첫 줄에 거래처 수신 거부 가드 — 상태 변경 없이 같은 화면으로 303 + `flash[:alert]`("이 거래처가 추가 안내 수신을 거부하여 자동 안내를 다시 진행할 수 없습니다."). |

유지되는 것: 청구 건 단위 보류 재개(`resume_reminders`), 거래처 보류 재개, 수신 거부하지 않은 종결 청구의 재개(기존 2개 테스트), 수동 발송(`remind`는 `reminders_active?`일 때만 노출 + `SendService` REFUSED 가드).

### 수정 2 — PLAN-3·Q10/Q11·REM-8 (상한 집계 합산)

| 파일 | 변경 |
|:--|:--|
| `app/models/message_log.rb` | 상한 집계 범위를 "채무자 향 sent 중 (시퀀스성 템플릿 **또는** origin=manual)"로 바꾼다. 호출처는 `SendService#cap_reached?`와 테스트뿐이라 범위·메서드 이름을 의미에 맞게 바꾼다(`counted_for_cap` 스코프 + `MessageLog.cap_sent_count`). |
| `app/services/reminders/send_service.rb` | `cap_reached?`가 새 집계를 쓴다. `manual_cap_reached?`(수동 가드 — 채무자 향 sent 전체 5통)는 바꾸지 않는다. 주석 보강. |

집계 정의: `recipient_role = debtor AND status = sent AND (template_key IN SEQUENCE_TEMPLATE_KEYS OR origin = manual)`.

### 마이그레이션·라우트

없음.

## 에러 조건·경계 (테스트 시나리오)

1. 수신 거부 거래처의 종결 청구: 상세 화면에 「안내 다시 보내기」가 없고 거부 안내 배너는 있다.
2. 같은 청구에 `POST restart_reminders`: 303 + alert, `sequence_finished_at` 유지.
3. 수신 거부하지 않은 종결 청구: 버튼 노출·재개 성공은 기존대로(회귀).
4. 수동 발행 안내(issue_notice) 5통을 보낸 청구: 다음 자동 시퀀스 단계는 `CAP_REACHED` skip, API 호출 0.
5. 수동 4통 + 자동 시퀀스 1통 = 5통: 그다음 자동 단계 `CAP_REACHED`.
6. 자동 1회성(partial_paid·paid_thanks·자동 issue_notice)은 상한 도달에도 발송되고 집계되지 않는다(Q10 유지).
7. 수동 가드는 기존대로: 채무자 향 sent 전체 5통에서 6번째 수동 발송 차단.
8. 수동으로 보낸 시퀀스성 템플릿(confirm_d1 등)은 종전과 같이 집계된다(회귀).

## 문서

- Phase 2(오케스트레이터): PRD v0.49 — PLAN-3 문단 보완, VIEW-7 구현 확정, 결정 기록 Q28.
- 완료 뒤: `LAUNCH_TEST_SCENARIOS.md`(G-07-3·G-05-4 기대값을 수정 후 동작으로), `LAUNCH_TEST_CHECKLIST.md` 재생성(§8 1·2 해소), AGENTS.md 구현 진행 상황.

## 리스크

- 같은 작업 트리에 포트원 런의 미커밋 변경(60파일)이 있다. 서브에이전트 지시서에 "범위 밖 파일 불가령·git 상태 변경 금지"를 명시한다.
- 상한 합산으로 수동 발송을 많이 쓴 청구는 다음 자동 단계가 막힐 수 있다 — 의도된 동작이며 운영 데이터는 사실상 테스트 계정뿐이다.
- 서브에이전트 테스트는 솔라피·포트원·메일 실호출 금지(기존 stub 헬퍼만 사용, 임시 재현 테스트 금지).

## 위임 계획

| Phase | 프로필 | 산출물 |
|:--|:--|:--|
| 3 | `badeuldon-developer` | 소스 + 기존 테스트 갱신 + `_workspace/03_implementation.md` |
| 4 | 오케스트레이터 | rubocop·zeitwerk |
| 5 | `badeuldon-reviewer` | `_workspace/05_review.md` |
| 6 | `badeuldon-developer`(필요 시) | 리뷰 이슈 최소 수정 |
| 7 | `badeuldon-tester` | 테스트 + `_workspace/07_test_report.md` |
| 8~9 | 오케스트레이터 | `_workspace/08_run_report.md`·보고 |

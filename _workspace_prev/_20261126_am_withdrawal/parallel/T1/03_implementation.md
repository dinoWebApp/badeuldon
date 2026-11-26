# T1 03_implementation — 회원 탈퇴(AUTH-1.5) 구현 보고 (2026-11-26, 병렬 배치 G1)

> 아래 "2차 리뷰 마무리(7차)" 절이 이 문서의 최신 상태다. "리뷰 반영(6차)" 절과 1차 본문은 이력으로 유지한다.

## 1. 변경 파일 목록

| 파일 | 구분 | 요약 |
|:---|:---|:---|
| `app/services/users/withdrawal_service.rb` | 신설 | `Users::WithdrawalService` — 이메일 확인 → 트랜잭션(감사 로그 → `user.destroy!`) → `Result(success, message)` |
| `app/controllers/app/profiles_controller.rb` | 수정 | `destroy` 액션 추가(10줄 이내) · `edit`에 `@withdrawal_summary` 적재 · update 422 재렌더 경로에도 동일 적재 · private `build_withdrawal_summary`·`paid_plus_period_end_on` · `WithdrawalSummary` Struct 상수 |
| `app/views/app/profiles/edit.html.erb` | 수정 | 프로필 폼·다이제스트 파셜 아래 최하단에 「회원 탈퇴」 section(독립 DELETE 폼) 추가 · REM-3 안내 오타 수정("야간·주일(주말)"→"야간·주말") |
| `app/views/pages/terms.html.erb` | 수정 | 제11조 ①항 끝에 미수 청구 탈퇴·링크 폐기 문장 추가 · ②항을 즉시 종료·환불 없음 문구로 교체(Q29) |
| `test/services/users/withdrawal_service_test.rb` | 신설 | 6 tests — 불일치 거부·정규화 일치·정상 탈퇴(연쇄 전수+감사)·미수 있어도 성공·유료 Plus 중 성공·RecordNotDestroyed 롤백 |
| `test/controllers/app/profiles_controller_test.rb` | 수정(추가만) | 6 tests 추가 — edit 렌더(요약 수치·오타 정정)·유료 Plus 고지·체험 고지·불일치 303·일치 시 삭제+감사+세션 종료·비로그인 차단. 기존 12 tests 무수정 유지 |
| `test/system/app_profile_withdrawal_test.rb` | 신설 | 2 tests — 탈퇴 E2E(성공→랜딩+로그인 풀림)·불일치→설정 화면 복귀. **실행하지 않음(규칙 — 통합 단계 실행)** |

소유권 외 파일은 수정하지 않았다. `config/routes.rb`는 T0가 결선한 `resource :profile`의 `destroy`를 그대로 사용.

## 2. Rule ID별 구현 매핑

| Rule ID | 구현 |
|:---|:---|
| **AUTH-1.5** | 설정 화면(`/app/profile`) 최하단 위험 구역 — ① 탈퇴 안내(되돌릴 수 없음·삭제 대상 5종) ② 현재 상태 요약(미수 청구 건수·잔액, 유료 Plus 종료일, 잔여 수금 패스) ③ 확인용 이메일 직접 입력 일치(AUTH-1.4 정규화와 같은 `strip.downcase` 기준) ④ `DELETE /app/profile`. 처리는 `Users::WithdrawalService`가 트랜잭션 안에서 감사 로그 후 `user.destroy!` — 연쇄 삭제는 `user.rb`의 `dependent: :destroy` 선언(세션→recurring_invoices→invoices→clients→items→subscription·orders·payment_passes·notice_reads·tickets·tax_invoices)에 위임. 미수 청구가 있어도 막지 않는다(Q29 — 화면에서 건수·잔액 선고지). 성공 시 `terminate_session`(기존 로그아웃 경로 재사용) → `/` 303 + notice. 같은 이메일 재가입 안내 문구 포함 |
| **ADMIN-2** | `AuditLogs::RecordService.call(admin: nil, action: "member_withdrawal", target: user, detail: "회원 탈퇴 — 이메일 스냅샷: …", ip: …)` — 삭제 트랜잭션 **내부에서 먼저** 기록(Q13 감사 보존 선례·admin 삭제 서비스와 동일 순서). 실패(RecordNotDestroyed) 시 트랜잭션 롤백으로 감사 로그도 원복 — 감사 없는 삭제 원천 차단(테스트로 검증) |
| **Q29** | 미수 청구 있어도 탈퇴 허용(서비스에 차단 가드 없음 — 관리자 삭제 Q13 차단과 의도적으로 다름) · 유료 구독·수금 패스 즉시 소멸(연쇄 삭제)·이후 결제 없음 · 남은 기간·잔여 이용권 환불 없음을 탈퇴 화면에 선고지 · 이용약관 제11조 ②항을 "즉시 종료·환불 없음"으로 정합화(현행 "기간 말 결제 중단"은 ①항의 즉시 삭제와 모순이라 교체) |
| **P4(보조)** | 감사 로그에 이메일 스냅샷·IP 기록 — 삭제 후에도 대상 식별 가능 |
| **LP-12(문구)** | 새 창작 문구는 사실 고지형 — 과장·단정 없음(Reviewer 집중 검증 대상) |

## 3. 사용자 가시 문구 전문

**뷰(app/views/app/profiles/edit.html.erb — 신규 section):**

> **회원 탈퇴**
> 탈퇴하면 계정과 데이터가 즉시 삭제되어 되돌릴 수 없습니다.
>
> 삭제되는 항목
> - 청구서와 청구 링크(발행 중인 링크는 모두 폐기)
> - 거래처·품목
> - 발송 이력·문의 내역
> - 반복 청구 일정
> - 계정 정보(이메일·휴대폰·프로필)
>
> (미수 있을 때) 미수 청구 N건(잔액 ○원)의 청구 링크가 모두 폐기됩니다. 탈퇴 뒤에는 받을돈으로 이 청구들을 받을 수 없습니다.
> (유료 Plus 이용 중) 이용 중인 Plus(M월 D일 종료 예정)는 즉시 종료됩니다. 남은 기간은 환불되지 않고 이후 결제는 청구되지 않습니다.
> (체험 중) 체험 중인 Plus는 즉시 종료됩니다.
> (패스 있을 때) 남은 수금 패스 N건은 소멸되며 환불되지 않습니다.
>
> 확인용 이메일 [입력 — placeholder: "가입한 이메일을 입력해 주세요"]
> [탈퇴합니다]
> 탈퇴 후에는 같은 이메일로 다시 가입할 수 있지만, 이전 데이터는 복구되지 않습니다.

**플래시:**
- 성공(랜딩 notice): "탈퇴가 완료되었습니다. 그동안 이용해 주셔서 감사합니다."
- 이메일 불일치(설정 화면 alert): "이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요."
- FK 제약 실패(설정 화면 alert): "탈퇴 처리 중 오류가 발생했습니다. 잠시 후 다시 시도하거나 문의해 주세요."

**오타 정정(같은 화면 REM-3 안내):** "야간·주일(주말) 발송은 정책상 불가합니다…" → "야간·주말 발송은 정책상 불가합니다 — 허용 범위 내에서만 조정할 수 있습니다."

**이용약관 제11조(app/views/pages/terms.html.erb):**
- ①항 끝 추가: "미수 청구가 있는 경우에도 탈퇴할 수 있으며, 이 경우 해당 청구의 링크도 폐기됩니다."
- ②항 교체: "탈퇴 시 이용 중인 유료 구독은 즉시 종료되며 이후 결제는 청구되지 않습니다. 탈퇴 시점에 남은 이용 기간과 남은 이용권(수금 패스)은 환불되지 않습니다."

## 4. 실행한 테스트·검증 결과

```
DATABASE_URL=sqlite3:tmp/parallel/T1/test.sqlite3 bin/rails test \
  test/services/users/withdrawal_service_test.rb test/controllers/app/profiles_controller_test.rb
→ 24 runs, 202 assertions, 0 failures, 0 errors, 0 skips
  (기존 12 + 신규 6 서비스 + 신규 6 컨트롤러. 최초 실행에서 422 재렌더 경로의
   @withdrawal_summary 미적재 오류 2건 발견 → update 실패 분기에 적재 추가 후 재실행 통과)

bin/rubocop app/controllers/app/profiles_controller.rb app/services/users/withdrawal_service.rb \
  test/services/users/withdrawal_service_test.rb test/controllers/app/profiles_controller_test.rb \
  test/system/app_profile_withdrawal_test.rb
→ 5 files inspected, no offenses detected
  (※ ERB는 이 프로젝트의 rubocop 대상이 아님 — omakase는 .rb만. ERB는 테스트 렌더로 검증.
   ERB를 rubocop에 직접 넘기면 Ruby 파서 오탐 626건 — 프로젝트 기준 아님)

bin/rails zeitwerk:check → "Otherwise, all is good!"

시스템 테스트(test/system/app_profile_withdrawal_test.rb)는 작성만 하고 실행하지 않음(규칙).
```

## 5. 판단이 필요했던 부분

1. **Plus 이용 상태 판정** — `Subscription`의 plan+status 조합으로 세 갈래: ① 체험 중 = `status: trialing`(`start_trial!`이 plan plus+status trialing을 함께 씀) → 체험 문구 ② 유료 기간 중 = `plan: plus ∧ !trialing ∧ current_period_end 존재` — status가 `active`와 `cancelled`(PLAN-5 해지 잔여 기간도 Plus 유지) 모두 커버하며 `current_period_end.to_date`를 "M월 D일 종료 예정"으로 표시 ③ 구독 행 없음(폴백 Free)·Free → 문구 없음. 판정 헬퍼는 컨트롤러 private `paid_plus_period_end_on` 한 곳.
2. **잔여 수금 패스 건수** — `user.payment_passes.usable.sum(:remaining_uses)`. `usable` 스코프(잔여 1 이상 ∧ 만료 전 — PLAN-4 단일 출처)의 잔여 횟수 합계 = "지금 쓸 수 있는 발행 건수"이며 10건짜리 패스 여러 장도 합산해 "N건"으로 고지한다. 소멸 고지 문구의 대상과 정확히 일치하는 계산.
3. **미수 잔액 계산식** — `App::DashboardsController#remaining_total`과 동일: `scope.sum(:total_amount) − Payment.where(invoice_id: scope.select(:id)).sum(:amount)` — 부분입금을 반영한 잔액 기준(DASH-1·F-PAY 재계산 선례).
4. **세션 종료 순서** — `user.destroy!`의 연쇄 삭제가 `Current.session` 행을 이미 파괴한 뒤 `terminate_session`이 재호출된다. Rails `destroy`는 이미 파괴된 레코드에 대해 SQL 없이 멱등(activerecord persistence.rb 실측 — `persisted?` false로 destroy_row 미호출)이라 안전하며, 쿠키 삭제는 독립 동작한다. 기존 `terminate_session`을 그대로 재사용(사양 지시).
5. **update 422 재렌더** — 뷰가 `@withdrawal_summary`를 요구하게 되어 프로필 저장 실패(422) 재렌더 경로에서도 적재해야 했다(최초 테스트 실행에서 발견). 액션 본문 10줄 이내 유지(8줄).
6. **탈퇴 폼의 자동완성** — `autocomplete: "email"`만 부여하고 값은 프리필하지 않는다(본인 타이핑 확인이 확인 절차의 핵심).

## 6. 범위 밖 수정 요청 (실행하지 않음 — 통합/후속 단계 반영 희망)

| 파일 | 요청 | 이유 |
|:---|:---|:---|
| `test/controllers/pages_policy_test.rb` | terms_path 본문 검증 테스트에 제11조 신규 문구 2문장(`미수 청구가 있는 경우에도 탈퇴할 수 있으며`·`남은 이용권(수금 패스)은 환불되지 않습니다`)의 assert_includes 추가 | 약관 정정(Q29)의 회귀 고정. 해당 파일은 T1 소유가 아니어서 건드리지 않았음 — 현재 terms 렌더 테스트는 요금 문구만 검사 |
| `LAUNCH_TEST_SCENARIOS.md` · `LAUNCH_TEST_CHECKLIST.md` | 02_prd_update.md 계획대로 C-04·C-02 갱신 | Phase 9(오케스트레이터) 문서 대상 |

## 7. 남은 우려

1. **시스템 테스트 미실행** — 규칙상 작성만 했다. Turbo 경유 DELETE 폼이지만 Turbo 미부트 시 네이티브 폼(`_method=delete` hidden)으로도 성공하는 구조라 이중 안전. 통합 단계(7-S)에서 실행 필요.
2. **개인정보 결제 기록 5년 보존 vs 주문 삭제** — 탈퇴 시 `orders`가 연쇄 삭제된다(현행 연쇄). PRD에 법무 검토 후속으로 명시된 사항이며 이번 범위 밖. 개인정보처리방침 문구 수정은 여전히 미반영.
3. **탈퇴 후 `/b/…` 링크 잔존 응답** — 링크 자체는 존재하지 않는 토큰으로 404/만료 안내가 된다(뷰어 기존 동작 — 별도 처리 불요로 판단). 청구 링크 폐기 고지 문구로 사용자 기대 정합.
4. **미수 청구의 채권 자체** — 서비스 명의 독촉이 중단되어도 금전 채권은 소멸하지 않는다. 화면 문구는 "받을돈으로 이 청구들을 받을 수 없습니다"로 한정해 법적 단정을 피했다(LP-12).
5. **파생 잡 회수** — 리마인더 예약 잡은 `Reminders::DeliverJob`의 `discard_on ActiveRecord::RecordNotFound`(기존), dunning 재차감은 `DunningRetryJob`의 `discard_on ActiveJob::DeserializationError` + `find_by` nil 가드(기존)로 모두 흡수됨을 확인했다. 신규 방어 코드 불요.

---

## 리뷰 반영(6차) — C-1·C-2·W-1~W-5·W-7·W-8 (2026-11-26)

`_workspace/05_review.md` T1 절의 지시 범위(오케스트레이터 처리 결정)에 따라 C-1·C-2·W-1·W-2·W-3·W-4·W-5·W-7·W-8(감사 detail 수치)을 수정했다. 소유 파일만 건드렸다.

### 1. 변경 파일 목록

| 파일 | 이슈 | 요약 |
|:---|:---|:---|
| `app/services/users/withdrawal_service.rb` | W-8 | `withdrawal_detail`·`plus_state` private 메서드 추가 — 삭제 전에 계산한 탈퇴 시점 요약을 detail에 굳짐: `"회원 탈퇴 — 이메일 스냅샷: … · 미수 N건(잔액 ○원) · Plus: 없음\|체험\|유료(종료 M-D)\|유료(해지 예약) · 수금 패스 N건"`. 잔액은 DASH-1과 같은 식(Σ총액 − Σ입금액 — 부분입금 반영), 패스는 `PaymentPass.usable` 잔여 합계. 기간 종료일 없는 Plus는 "유료"로 경계 처리 |
| `app/controllers/app/profiles_controller.rb` | W-3·W-5 | ① destroy 실패 리다이렉트를 `edit_app_profile_path(anchor: "withdrawal")`로 ② 요약 Struct에 `paid_plus_cancelled`(해지 예약 — PLAN-5 cancelled) 추가, private `paid_plus_cancelled?`·`confirm_email_param` 신설 |
| `app/views/app/profiles/edit.html.erb` | C-2·W-3·W-4·W-5 | 탈퇴 `<section>`에 `id="withdrawal"` · 삭제되는 항목 5종→8종 확장 + "필요한 내역은 탈퇴 전에 미리 저장해 주세요." · 첫 문장·상태 요약 문단을 `text-sm text-stone-700` + 핵심 구절 `<strong class="font-bold">` · 미수 문구를 "열리지 않아…받을 권리는 그대로 남습니다"로 교체 · Plus 고지를 자동 결제 중/해지 예약 2분기 · 확인용 이메일 입력란에 `pattern=".*\S.*"`·`title` 추가 |
| `app/views/pages/terms.html.erb` | W-2 | 머리 "마지막 수정일·공고·시행일" → 2026년 11월 26일 · 제11조 ②항 교체(제7조·제8조 관계 명시) · 제15조 ①항 시행일 갱신 + "2026년 11월 26일 개정 이력" 항목 추가(기존 11-20 이력 항목 유지) · 파일 머리 주석에 11-26 개정 기록 |
| `app/views/admin/audit_logs/index.html.erb` | W-1 | 행위 필터 선택지에 `[ "회원 탈퇴", "member_withdrawal" ]` 추가(기존 `to_h` 변환 방식 안에서) |
| `app/models/invoice.rb` | W-7 | promises·payments 주석만 갱신 — "삭제 경로 자체가 없다" → 회원 탈퇴(AUTH-1.5)·관리자 계정 삭제(ADMIN-3·Q13) 시 연쇄 삭제, 감사 로그만 보존 |
| `app/models/user.rb` | W-7 | status enum 주석만 갱신 — "Run C 재검토 대상" → 두 파기 경로(WithdrawalService·AccountPurgeService)와 감사 로그 보존 기술 |
| `test/controllers/app/profiles_controller_test.rb` | C-1·C-2·W-3·W-5 | 렌더 테스트: C-1(픽스처 패스→`travel_to` 안 90일 생성 패스 교체)·삭제 항목 8종+안내 문장 단언·`section#withdrawal`·pattern/title 속성·미수·패스 문구를 문단 텍스트 기준 단언으로 전환 · 해지 예약 고지 분기 신규 · 공백만·빈 문자열 303+alert 신규 · 불일치 단언을 앵커 목적지로 · 정상 탈퇴 감사 detail에 요약 단언 추가 |
| `test/services/users/withdrawal_service_test.rb` | W-8 | "정상 탈퇴"에 미수·Plus·패스 요약 단언 추가 · "감사 detail에 탈퇴 시점 요약…"(부분입금 잔액 차감·Plus 유료(종료 12-31))·"해지 예약(cancelled)…해지 예약으로 기록" 2건 신규. 헤더 주석 갱신 |
| `test/system/app_profile_withdrawal_test.rb` | C-1 | 픽스처 패스→테스트 생성 90일 패스 교체. 시스템 테스트는 travel_to 대신 상대 만료일(`90.days.from_now`)을 쓴다(Capybara 시간 동결 회피). **실행하지 않음(규칙)** |
| `test/controllers/pages_policy_test.rb` | W-2 | 약관 날짜 단언을 2026-11-26으로(방침·환불은 2026-11-20 유지) · 테스트 이름을 "정책 문서의 개정일 표기가 각 문서와 일치한다"로 변경 · 제11조 회귀 단언 신규(①항 미수 폐기·②항 3문장·부칙 개정 이력) |
| `test/controllers/app/billings_controller_test.rb` | C-1 | :91 같은 날짜 폭탄 — 같은 방식(픽스처 패스 파기 후 `travel_to("2026-10-15")` 안 90일 생성 패스)으로 교체, 단언을 "2027-01-13까지"로 |
| `test/controllers/admin/audit_logs_controller_test.rb` | W-1 | 행위 필터 select에 `option[value=member_withdrawal]`(표시 "회원 탈퇴") 존재 단언 신규 |

### 2. 구현 판단 노트

1. **W-3 — `params.expect`는 blank에서도 400을 던진다**: actionpack 8.1.4.1 `expect` 내부의 `require`가 `value.present?` 판정이라 공백만·빈 문자열도 `ParameterMissing`(400 정적 페이지)이 됐다. 지시("공백만·빈 문자열 → 303 설정 화면 + 불일치 alert · 파라미터 자체가 없는 요청만 400 유지")를 만족시키기 위해 `confirm_email_param` private 헬퍼로 분기한다 — `params.key?(:confirm_email)`가 참이면 `params[:confirm_email]`(빈 값 포함 — 서비스 불일치 가드로 흘러 303+alert), 거짓(키 없는 요청 — 정상 경로 아님)이면 `params.expect(:confirm_email)`로 기존 400 유지. 브라우저 pattern(`.*\S.*`)은 공백만 제출을 클라이언트에서 먼저 막는 이중 방어다.
2. **W-5 해지 예약 분기** — `Subscription`의 `cancelled`(PLAN-5: 자동 결제는 끝났고 기간 말까지 Plus)에서는 "이후 결제는 청구되지 않습니다"가 사실과 맞지 않아 두 문단으로 갈랐다. 판정은 컨트롤러 요약(`paid_plus_cancelled`) 한 곳.
3. **W-8 detail 형식** — 숫자·상태만(추가 개인정보 없음). 미수 0건·패스 0건도 "0건"으로 항상 기록해 grep 가능한 균일 형식을 유지한다. 날짜는 `%-m-%-d`(예: 종료 12-31).
4. **C-1 시스템 테스트의 travel_to 회피** — Capybara와 시간 동결의 상호작용 위험을 피하기 위해 시스템 테스트는 `expires_at: 90.days.from_now`(실행일 기준 상대 — 그 자체로 날짜 폭탄 없음)로 해결하고, 통합 테스트는 프로젝트 기준일 `2026-10-15 09:00` travel_to 안에서 생성한다.
5. **약관 조 번호 대조(W-2 지시)** — 교체 전 원문 확인: 제7조 ⑦ = "유료 구독은 신용카드 정기결제로 자동 갱신되며, 해지 시 남은 이용 기간까지 서비스를 이용할 수 있고…"(해지 잔여 기간 이용 규정), 제8조 ② = 이용 개시 전 7일 청약철회, ③ = 회사 귀책 전액 환불. 교체 문구의 "제7조의 남은 기간 이용"·"제8조에 따른 청약철회와 회사의 귀책 사유에 의한 환불" 조·항 번호가 실제 본문과 일치해서 지시 문구를 그대로 사용했다.
6. **테스트 단언 방식 전환** — W-4의 `<strong>` 마크업이 문장 중간에 삽입되므로 해당 문구 단언을 `assert_match response.body`에서 `assert_select "#withdrawal p", text: /…/`(태그 제거 텍스트 기준)로 전환했다(미수·Plus·수금 패스 문구).

### 3. 사용자 가시 문구 전문 (최종)

**뷰(app/views/app/profiles/edit.html.erb — 탈퇴 영역, `<section id="withdrawal">`):**

> **회원 탈퇴**
> 탈퇴하면 계정과 데이터가 즉시 삭제되어 **되돌릴 수 없습니다.**
>
> 삭제되는 항목
> - 청구서와 청구 링크(발행 중인 링크는 모두 폐기)
> - 청구서 부속 기록(입금 내역·약속·문의 응답·열람 기록)
> - 거래처·품목
> - 발송 이력·문의 내역
> - 반복 청구 일정
> - 결제·환불 내역(구독료·수금 패스·내용증명·세금계산서 결제)
> - 세금계산서 발행 내역
> - 계정 정보(이메일·휴대폰·프로필)
>
> 필요한 내역은 탈퇴 전에 미리 저장해 주세요.
>
> (미수 있을 때) 미수 청구 **N건(잔액 ○원)**의 청구 링크가 열리지 않아, 받을돈 명의의 안내나 입금 예정일을 받을 수 없습니다. **받을 권리는 그대로 남습니다.**
> (유료 Plus·자동 결제 중) 이용 중인 Plus(**M월 D일 종료 예정**)는 즉시 종료됩니다. 남은 기간은 **환불되지 않고**, 이후 결제는 청구되지 않습니다.
> (유료 Plus·해지 예약 — 자동 결제가 이미 끝난 상태) 이용 중인 Plus(**M월 D일 종료 예정**)는 즉시 종료됩니다. 남은 기간은 **환불되지 않습니다**.
> (체험 중) 체험 중인 Plus는 즉시 종료됩니다.
> (패스 있을 때) 남은 수금 패스 **N건**은 소멸되며 **환불되지 않습니다**.
>
> 확인용 이메일 [입력 — placeholder: "가입한 이메일을 입력해 주세요" · 브라우저 검증: 공백만 입력 차단]
> [탈퇴합니다]
> 탈퇴 후에는 같은 이메일로 다시 가입할 수 있지만, 이전 데이터는 복구되지 않습니다.

(굵게 표시 부분이 `<strong class="font-bold">`다. 플래시 문구는 1차와 동일 — 성공 "탈퇴가 완료되었습니다. …" / 불일치 "이메일이 일치하지 않습니다. …"(이제 탈퇴 영역 앵커로 복귀하며 바로 보인다) / FK 실패 "탈퇴 처리 중 오류가 발생했습니다. …".)

**이용약관(app/views/pages/terms.html.erb) 최종 본문:**

- 머리: "마지막 수정일: 2026년 11월 26일 · 공고·시행일: 2026년 11월 26일 · 상호: 벨로루프"
- 제11조(계정 해지 및 서비스 중단):
  - ① "회원은 언제든 서비스 내 설정 화면에서 탈퇴할 수 있으며, 탈퇴 즉시 계정 데이터가 삭제되고 발행 중인 청구 링크가 전부 폐기되며 진행 중인 자동 시퀀스가 중단됩니다. 미수 청구가 있는 경우에도 탈퇴할 수 있으며, 이 경우 해당 청구의 링크도 폐기됩니다."(1차 문구 유지)
  - ② "회원 탈퇴 시 이용 중인 유료 구독은 즉시 종료되며 이후 결제는 청구되지 않습니다(구독만 해지하는 경우와 달리 제7조의 남은 기간 이용은 적용되지 않습니다). 탈퇴 시점에 남은 이용 기간과 남은 이용권(수금 패스)은 환불되지 않습니다. 다만 제8조에 따른 청약철회와 회사의 귀책 사유에 의한 환불은 그러하지 아니합니다."
  - ③ (기존 유지) "회원이 이 약관을 위반한 경우 회사는 사전 통지 후 …"
- 제15조(부칙):
  - ① "이 약관은 2026년 10월 15일에 제정되어 시행되었으며, 2026년 11월 26일에 개정되어 공고·시행됩니다."
  - ② "2026년 11월 20일 개정 이력: 휴대폰 인증 가입 절차 반영(제4조), 전자세금계산서 발행 관련 조항 신설(제5조), 부가서비스 요금·추천 할인 관련 조항 신설(제7조)."(기존 유지)
  - ③ "2026년 11월 26일 개정 이력: 회원 탈퇴 절차 명시(제11조 — 설정 화면 탈퇴, 미수 청구 링크 폐기, 유료 구독 즉시 종료)."(신설)
  - ④ "개정된 약관은 별도의 명시가 없는 한 그 시행일부터 체결되는 이용계약에 즉시 적용됩니다."

**감사 로그 detail(W-8 — 관리자 가시):**
`회원 탈퇴 — 이메일 스냅샷: alpha@example.com · 미수 6건(잔액 946000원) · Plus: 유료(종료 10-31) · 수금 패스 10건`
(Plus 상태: 없음·체험·유료(종료 M-D)·유료(해지 예약). 잔액·패스는 정수 원·건.)

### 4. 실행한 테스트·검증 결과 (6차)

```
DATABASE_URL=sqlite3:tmp/parallel/T1/test.sqlite3 bin/rails test \
  test/services/users test/controllers/app/profiles_controller_test.rb \
  test/controllers/app/profiles_remind_settings_test.rb test/controllers/pages_policy_test.rb \
  test/controllers/app/billings_controller_test.rb test/controllers/admin
→ 189 runs, 1562 assertions, 0 failures, 0 errors, 0 skips
  (최초 실행 3 failures + 1 errors — ① <strong> 마크업으로 assert_match 2건 깨짐 →
   assert_select 문단 텍스트 단언으로 전환 ② 공백만 입력이 params.expect로 400 →
   confirm_email_param 분기로 해소 ③ W-8 테스트가 서비스 호출 뒤 삭제된 invoice를
   reload하려 함 → 호출 전 금액 캡처. 이후 재실행 전부 통과)

bin/rubocop app/controllers/app/profiles_controller.rb app/services/users/withdrawal_service.rb \
  app/models/invoice.rb app/models/user.rb test/services/users/withdrawal_service_test.rb \
  test/controllers/app/profiles_controller_test.rb test/system/app_profile_withdrawal_test.rb \
  test/controllers/pages_policy_test.rb test/controllers/app/billings_controller_test.rb \
  test/controllers/admin/audit_logs_controller_test.rb
→ 10 files inspected, no offenses detected

bin/rails zeitwerk:check → "Otherwise, all is good!"

시스템 테스트(test/system/app_profile_withdrawal_test.rb)는 수정만 하고 실행하지 않음(규칙 — 통합 단계 실행).
```

### 5. 안 고친 것 (오케스트레이터 처리 결정 기준)

| 항목 | 이유 |
|:---|:---|
| W-6(잔액 계산식 중복 — `Invoice` 단일 출처화) | 선택 사항이며 `app/controllers/app/dashboards_controller.rb`는 T3(대시보드) Developer 소유 — 이번 배치의 동시 작업 소유 규칙상 손댈 수 없다. 서비스·컨트롤러 양쪽 모두 주석으로 DASH-1 계산식과의 동일성을 명시해 두어 출처 참조는 유지된다 |
| W-8의 개인정보처리방침 문구(이메일·IP 보존 명시) | `app/views/pages/privacy.html.erb`는 금지 파일(법무 후속 배치 대상) |
| 정책 공백 5건(SALES 정산 기준 소실·재가입 혜택 리셋·외부 서비스 잔존·법무 보존 기록·미결제 주문) | 구현 결함이 아니라 Q29가 다루지 않는 정책 공백 — PRD AUTH-1.5 "알려진 한계(2026-11-26 리뷰 — 후속 과제)" ①~⑤로 이미 기록됨. 문서(PRD)는 이 배치 금지 파일 |

### 6. 남은 우려

1. **시스템 테스트 미실행** — 규칙상 작성만 했다(7-S 통합 단계 실행 필요). C-1 교체 로직 자체는 통합 테스트에서 동일하게 검증됐다.
2. **약관 개정 공고 절차** — 제14조 ②항("적용일 30일 전부터 공지")과 2026-11-26 당일 공고·시행 표기가 병존한다. 회원 탈퇴 조항은 회원에게 불리한 변경이 아니라(기존 ②항 "기간 말 결제 중단" 모순의 해소 + PRD v0.50 확정) 즉시 시행 가능한 성격이지만, 법무 확인 시 공고 방식(서비스 내 공지 여부)과 함께 짚어볼 것. W-2의 "공지 방식을 정해" 지시는 날짜·부칙 갱신으로만 수행했다.
3. **W-7 주석의 Payment 모델 확산** — `app/models/payment.rb` 머리 주석도 "입금 이력은 영구 보존한다(P4)"로 같은 낡은 서술이 남아 있다. T1 소유 파일이 아니어서 고치지 않았다(후속 1줄 수정 요청).
4. **감사 detail의 미수 잔액은 콤마 없는 정수** — 화면 고지는 `number_with_delimiter`(946,000원), 감사 detail은 정수(946000원)다. grep·파싱 편의를 우선했으며 ADMIN-2 화면은 truncate로 보여준다.
5. **해지 예약 상태에서 기간 종료일이 과거인 경우**(스윕 전·dunning 중 — 리뷰 ③에서 "표기 문제 수준"으로 확인된 사항) — "M월 D일 종료 예정"에 지난 날짜가 찍힐 수 있다. 이번 범위 밖(리뷰에서 이미 수용된 표기 한계).

---

## 2차 리뷰 마무리(7차) — X-1·X-2·N-1·N-3·N-4·N-5 (2026-11-26)

`_workspace/05_review.md` 끝의 "T1 — 2차(재)리뷰"(APPROVED — W 6 + 범위 밖 X 2)와 "오케스트레이터 처리 결정(T1 2차)" 지시 범위를 수정했다. N-2·N-6은 결정상 이번 배치 제외다. 소유 파일만 건드렸다.

### 1. 변경 파일 목록

| 파일 | 이슈 | 요약 |
|:---|:---|:---|
| `test/controllers/admin/orders_controller_test.rb` | X-1 | "owner의 환불 실행 성공…" — 공용 픽스처 패스(delta_active_pass, 만료 2026-12-30)를 `destroy_all`한 뒤 `expires_at: 90.days.from_now` 패스를 테스트 안에서 직접 생성(6차 C-1과 같은 방식 — 이 테스트는 travel_to가 없어 상대 만료일만). 단언("수금 패스 10건 차감")은 그대로 |
| `test/system/admin_order_refund_test.rb` | X-1 | 같은 방식 — `users(:delta).payment_passes.destroy_all` + 90일 상대 만료일 패스 생성(시스템 테스트라 travel_to 없음). 단언 "잔여 합계 0"은 그대로. **실행하지 않음(규칙)** |
| `app/controllers/app/profiles_controller.rb` | N-1 | destroy 실패 분기에 `flash[:withdrawal_error] = result.message` 추가(기존 `alert:` 유지 — 상단 경고·기존 단언 그대로). 액션 본문 10줄 이내 유지 |
| `app/views/app/profiles/edit.html.erb` | N-1·N-3 | ① 탈퇴 section 안(상태 요약 문단들과 DELETE 폼 사이)에 `flash[:withdrawal_error]`를 `role="alert"` 한 줄로 표시 — 스타일은 이 화면의 기존 인라인 경고 문법(`mt-3 text-xs font-medium text-red-600`) ② 미수 문장을 N-3 문구로 교체 |
| `app/views/admin/audit_logs/index.html.erb` | N-4 | 요약 셀의 `<td>`에 `title="<%= log.detail %>"` 추가 — 잘린 전문을 마우스 올림으로 본다. truncate 60은 그대로 |
| `app/views/pages/terms.html.erb` | N-5 | 제15조 "2026년 11월 26일 개정 이력" 항 끝에 시행 정합 문장 1개 추가(머리 표기·시행일 무변경). 파일 머리 주석의 11-26 개정 항에 한 줄 덧붙임 |
| `app/models/payment.rb` | X-2 | 머리 주석만 — "입금 이력은 영구 보존한다(P4)" → "앱 내 삭제 경로는 없지만, 회원 탈퇴(AUTH-1.5)·관리자 계정 삭제(ADMIN-3·Q13) 시에는 입금 내역도 연쇄 삭제된다 — 감사 로그(ADMIN-2)만 보존된다"(invoice.rb 6차 주석과 같은 서술). 동작 변경 없음 |
| `app/models/promise.rb` | X-2 | 머리 주석만 — "이력은 영구 보존한다(P4 …)" → 재응답 유지·최신 응답 기준 서술은 남기고 연쇄 삭제·감사 로그 보존 문장으로 교체. 동작 변경 없음 |
| `test/controllers/app/profiles_controller_test.rb` | N-1·N-3 | 불일치 테스트에 `#withdrawal [role=alert]` 문구 단언 추가 · 미수 문장 regex를 N-3 문구 전체로 확장 |
| `test/controllers/admin/audit_logs_controller_test.rb` | N-4 | 60자를 넘는 detail(이메일 스냅샷·미수·Plus·수금 패스 요약)의 전문이 `td[title]`에 싣기는지 단언 신규 |
| `test/controllers/pages_policy_test.rb` | N-5 | 부칙 정합 문장(부분 문자열) 회귀 단언 신규 |

### 2. 사용자 가시 문구 전문 (최종)

**미수 문장(N-3 — `edit.html.erb` 탈퇴 영역):**

> 미수 청구 **N건(잔액 ○원)**의 청구 링크가 열리지 않아, 채무자에게 받을돈 명의의 안내를 보내거나 입금 예정일 약속을 받을 수 없습니다. **받을 권리는 그대로 남습니다.**

(굵게는 기존 `<strong class="font-bold">` 그대로. "받을돈 명의의 안내나 입금 예정일을 받을 수 없습니다" → 위 문구로 교체.)

**탈퇴 영역 실패 안내(N-1 — `<section id="withdrawal">` 안, 상태 요약 문단들과 폼 사이에 한 줄):**

> 이메일이 일치하지 않습니다. 가입한 이메일을 다시 입력해 주세요.

(`flash[:withdrawal_error]`가 있을 때만 렌더 — 내용은 서비스 실패 메시지와 같다. 불일치 안내와 FK 실패 안내 두 가지가 이 경로로 온다. 레이아웃 상단의 기존 `#alert`도 그대로 표시된다. 스타일: 작은 글자·붉은 계열 텍스트.)

**약관 부칙 최종 본문(N-5 — 제15조 ③항):**

> 2026년 11월 26일 개정 이력: 회원 탈퇴 절차 명시(제11조 — 설정 화면 탈퇴, 미수 청구 링크 폐기, 유료 구독 즉시 종료). 이 개정은 서비스 정식 오픈 전에 공고되어 같은 날 시행되며, 정식 오픈 이후의 약관 개정은 제14조 ②에 따라 공지합니다.

(머리 표기 "마지막 수정일: 2026년 11월 26일 · 공고·시행일: 2026년 11월 26일"과 제15조 ①·②·④항은 무변경.)

### 3. 실행한 테스트·검증 결과 (7차)

```
DATABASE_URL=sqlite3:tmp/parallel/T1/test.sqlite3 bin/rails test \
  test/services/users test/controllers/app/profiles_controller_test.rb \
  test/controllers/pages_policy_test.rb test/controllers/app/billings_controller_test.rb \
  test/controllers/admin/orders_controller_test.rb test/controllers/admin/audit_logs_controller_test.rb
→ 73 runs, 649 assertions, 0 failures, 0 errors, 0 skips

bin/rubocop app/controllers/app/profiles_controller.rb app/models/payment.rb app/models/promise.rb \
  test/controllers/app/profiles_controller_test.rb test/controllers/pages_policy_test.rb \
  test/controllers/admin/orders_controller_test.rb test/controllers/admin/audit_logs_controller_test.rb \
  test/system/admin_order_refund_test.rb
→ 8 files inspected, no offenses detected

bin/rails zeitwerk:check → "Otherwise, all is good!"

git diff --stat — 이번 세션 변경은 소유 파일 11개뿐(위 표). fixtures·config·db·타 태스크 파일 무변경.
시스템 테스트(test/system/admin_order_refund_test.rb)는 수정만 하고 실행하지 않음(규칙 — 7-S 통합 실행).
```

### 4. 안 고친 것 (오케스트레이터 처리 결정 기준)

| 항목 | 이유 |
|:---|:---|
| N-2(감사 IP가 실방문자 IP인지 미확인) | 결정상 "이번 배치는 그대로 — 첫 실제 탈퇴 1건의 감사 IP를 확인하고 틀리면 전역 수정(후속 과제)". `request.remote_ip`는 다른 ADMIN-2 호출처와 같은 기준이라 이 파일만 바꾸면 기준이 갈라진다. 운영에서 `CF-Connecting-IP` 수신 여부는 정적으로 확정되지 않는다(프록시 신뢰 설정 없음) |
| N-6(환불 예외 문언 vs 주문 연쇄 삭제) | 결정상 "코드 수정 없음 — 법무 보존 결정(결제 기록 5년 보존)과 묶어 후속 과제로". 제11조 ②항의 제8조 예외 문언은 그대로며, 탈퇴 뒤 환불은 포트원 콘솔 수동 처리로 운영한다는 운영 노트 보강은 문서(오케스트레이터) 몫 |
| X-1의 근본 대책(픽스처를 ERB 상대 만료일로 전환) | 픽스처는 이번 배치 공유 금지 파일 — 테스트 측 해소(6차 C-1과 같은 방식)로만 처리. 후속 배치 제안 |
| 키워드 기반 훑기(X-1 리뷰 한계 — "다른 인스턴스가 더 있을 수 있다") | 소유 파일 범위 내에서는 `delta_active_pass` 의존 단언이 남아 있는 파일을 전수 확인했고 이 2건이 전부다. 파일 밖(다른 태스크 소유)은 손대지 않았다 |

### 5. 남은 우려

1. **시스템 테스트 2파일 미실행** — `admin_order_refund_test.rb`(이번 X-1 수정)·`app_profile_withdrawal_test.rb`(기존) 모두 규칙상 7-S 통합 단계 실행 필요. X-1 교체 로직 자체는 동일 패턴이 통합 테스트(73 runs)에서 검증됐다.
2. **운영 회원 9개에 실제 사용자 존재 여부**(오케스트레이터가 완료 보고 결정 필요로 올린 N-5 관련) — 외부 회원이 있으면 약관 당일 시행은 법무 확인 뒤 시행일 30일 뒤 또는 개별 통지로 조정해야 한다(리뷰 5-C의 CRITICAL 전환 조건). 코드·문구는 권고안(문장 1개)으로 반영했다.
3. **`flash[:withdrawal_error]`는 `add_flash_types`에 없는 커스텀 키라** `redirect_to ... , withdrawal_error:` 옵션 형태로는 설정되지 않는다(actionpack 8.1.4.1 `ActionController::Flash#redirect_to`는 `_flash_types`·`flash:` 해시만 흡수 — 실측). 그래서 명시적 `flash[:withdrawal_error] =` 대입으로 구현했다. 뷰에서 이 키를 읽는 곳은 탈퇴 영역 한 곳뿐이다.
4. **X-1 유형의 잔존 가능성** — 리뷰가 키워드 기반 훑기라 했다. 소유 파일 밖에서 `delta_active_pass` 등 고정 만료일 픽스처에 의존하는 테스트가 발견되면 같은 방식(픽스처 파기 후 상대 만료일 생성)으로 정리하는 것이 후속 배치 후보다.


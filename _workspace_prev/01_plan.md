# 01_plan — 병렬 배치(절약): 후속 과제 뭉치 (2026-11-26, lite 모드·parallel)

## 배경

직전 배치(회원 탈퇴·수신 거부 번호 단위·대시보드 오늘의 액션 — `_workspace_prev/`)의 완료 보고가 남긴 후속 과제 중
**코드로 바로 진행 가능한 것**을 묶는다. 법무·운영 판단이 필요한 것(약관 시행일 확인·탈퇴 시 법정 보존 기록·SALES 정산 소실 등
탈퇴 알려진 한계 5건)과 가치가 낮은 것(대시보드 성능·문구 후속)은 이번 배치에서 제외 — 완료 보고에 명시.
시점: main `d658c78` + 미커밋 71경로(직전 배치·런칭 테스트 문서·하네스 문서 — 기존 관례대로 위에 쌓고 "커밋 배포" 시 범위별 분리 커밋).

## 태스크 후보 (게이트에서 사용자 선택)

| ID | 태스크 | Rule ID | 규모 | 비고 |
|:--|:--|:--|:--|:--|
| T1 | 휴대폰 인증 기록 파기 잡 — 만료(24시간) 지난 `phone_verifications` 행을 매일 삭제 | AUTH-9 | Small | PRD AUTH-9 알려진 한계 해소. rate limit(1분·1시간)·가입 이중 검증(30분) 창과 무관한 24시간 기준 |
| T2 | 클라이언트 IP 전역 통일 — `CF-Connecting-IP` 우선 헬퍼 1개로 감사 로그·세션·새 IP 감지·rate limit 적용 | ADMIN-2, AUTH-7, AUTH-9 | Standard | **운영 결함 해소 포함**: 운영은 전부 CF 터널 경유라 `remote_ip`가 전부 같은 값 — 감사 IP·관리자 새 IP 알림·등록 rate limit이 사실상 무의미. 뷰어의 `viewer_client_ip`(선례)를 전역 헬퍼로 추출 |
| T3 | 픽스처 날짜 폭탄 근본 해소 — `invoices.yml`·`payment_passes.yml`의 고정 미래 만료일을 ERB 상대값으로 | (테스트 자산 — 기술 부채) | Small | `notices.yml`·`coupons.yml`·`sales_referral_codes.yml`은 이미 ERB 상대값(선례). 만료(과거) 픽스처는 의도 유지 |
| T4 | 수신 거부를 번호에 고정 — `clients.refused_phone` 신설(마이그레이션), 거부 시점의 번호를 저장하고 상속·전파의 기준으로 | VIEW-7(Q30) | Standard | 알려진 한계 해소: 거부된 거래처 행의 번호를 바꾸면 그 행이 새 번호의 상속 원천이 되는 문제. 행 단위 거부 판정(`client.refused?`)·되돌림 없음 원칙은 불변. **이번 배치의 유일 마이그레이션** |
| T5 | 사전통보 발송 시각 정합 — 09:00 사전통보가 실제 발송일이 아닌 날을 안내하지 않게(DASH-2와 같은 실제 발송 시각 판정) | REM-11, REM-3 | Standard | 알림톡 문구는 변경하지 않는다(템플릿 재검수 불요) — **통보 대상 선별 로직만** 수정. `PrenoticeService` |

제외(보고): 대시보드 후보별 쿼리 수·같은 청구 두 카드 문구(가치 낮음·직전 코드 안정화 우선) / 약관 시행일·법정 보존 기록(사용자 결정 대기) / 탈퇴 알려진 한계 5건(법무·운영 판단).

## 병렬 안전 판정 (§6.14 3조건)

| 조건 | 판정 | 근거 |
|:--|:--|:--|
| 1. 파일 소유권 분리 | **충족** | 아래 소유권 표 — T1~T5의 생성·수정 파일이 겹치지 않는다 |
| 2. 의존 없음 | **충족** | 서로의 산출물을 참조하지 않는다. T5가 참조하는 `DispatchService` 상수·`scheduled_today_keys`는 직전 배치에서 완료된 기존 코드(선행 산출 참조 허용) |
| 3. 공유 파일 비수정 | **충족** | `config/recurring.yml`은 T1 단독 소유. 마이그레이션은 T4 단독(배치 내 1건). routes·PRD·AGENTS·progress.json은 아무도 직접 수정하지 않음(Phase 2·3-S) |

## 파일 소유권 표

| 태스크 | 앱 코드 | 테스트 |
|:--|:--|:--|
| T1 | `app/jobs/phone_verifications/purge_job.rb`(신설) · `app/models/phone_verification.rb`(스코프·주석) · `config/recurring.yml`(production·development 1잡씩) | `test/jobs/phone_verifications/purge_job_test.rb`(신설) |
| T2 | `app/controllers/concerns/client_ip.rb`(신설) · `app/controllers/viewer_controller.rb`(헬퍼 위임) · `app/controllers/concerns/authentication.rb` · `app/controllers/registrations_controller.rb` · `app/controllers/app/profiles_controller.rb` · `app/controllers/admin/sessions_controller.rb` · `app/controllers/admin/passwords_controller.rb` · `app/controllers/admin/sales_reps_controller.rb` · `app/controllers/admin/sales_commissions_controller.rb` · `app/controllers/sales/sessions_controller.rb` | 위 컨트롤러·concern의 기존 테스트 + IP 단언 보강(`test/controllers/` 해당 파일들) |
| T3 | — (테스트 자산만) | `test/fixtures/invoices.yml` · `test/fixtures/payment_passes.yml` (+ 각 파일 헤더 주석) |
| T4 | `db/migrate/`(신설 1건) · `app/models/client.rb` · `app/services/promises/register_service.rb` · `app/controllers/app/clients_controller.rb` | `test/models/client_test.rb` · `test/services/promises/register_service_test.rb` · `test/controllers/app/clients_controller_test.rb` |
| T5 | `app/services/reminders/prenotice_service.rb` | `test/services/reminders/prenotice_service_test.rb`(필요시 신설·보강) |

금지(전 태스크 공통): `config/routes.rb` · `db/`(T4 외) · `PRD.md`·`AGENTS.md` · `config/locales/*` · `test/fixtures/*`(T3 외) · `config/recurring.yml`(T1 외) · 다른 태스크의 소유 파일. 불가피하면 수정하지 않고 보고서에 적는다(3-S에서 반영).

## 확정 규칙 (PRD v0.50 기준 — Phase 2에서 선택 태스크분 갱신)

### T1 파기 잡
- `PhoneVerifications::PurgeJob` — `PhoneVerification` 중 `created_at < 24.hours.ago` 전량 삭제(감사 대상 아님 — 인증 용도 단기 데이터). 멱등·배치 삭제. 재시도 `retry_on` 명시.
- `config/recurring.yml` production·development에 매일 새벽(예: `30 4 * * * Asia/Seoul`) 등록 — 기존 잡 문법(fugit cron·KST 접미사) 준용.
- 모델에 `scope :purgeable` + AUTH-9 주석 갱신(알려진 한계 해소). 테스트: 23:59:59 유지 / 24시간+ 삭제 / consumed 창(30분) 내 행 유지.

### T2 클라이언트 IP
- 헬퍼 1개(예: `ClientIp.of(request)`) — `CF-Connecting-IP` 존재 시 그 값(단일 IP 형태 검증 — 스푸핑된 쉼표 목록은 fallback), 없으면 `request.remote_ip`. 뷰어의 기존 `viewer_client_ip` 로직을 헬퍼로 위임(동작 불변).
- 적용처: 감사 로그 `ip:` 전체(관리자 세션 5종·비밀번호 재설정·영업 세션 4종·sales_reps·sales_commissions·가입 인증·회원 탈퇴), 세션 생성 `ip_address`(authentication concern), 관리자 `last_login_ip`·새 IP 알림·`new_ip_login`, **등록 rate limit `by:`**(운영에서 전 방문자가 한 버킷으로 묶이는 결함 해소).
- 테스트: 헤더 있음/없음·형식 이상 값 fallback — 컨트롤러 테스트로 감사 IP·rate limit 단언 보강.

### T3 픽스처 상대 만료일
- `invoices.yml`의 `token_expires_at` 행과 `payment_passes.yml`의 `delta_active_pass`를 ERB 상대값으로(`<%= … %>` — 각 행의 용도 확인 후: "활성 링크"는 미래 상대값, "만료 안내" 픽스처는 과거 상대값 유지). 각 행이 어떤 테스트에서 쓰이는지 먼저 확인하고 변환 뒤 관련 테스트 실행.
- 2026-11-26 현재 이미 과거가 된 행(예: 2026-11-13·11-18)은 용도에 따라 정리. **날짜 의존 경계 판정에 상대 픽스처를 쓰지 않는다**는 기존 교훈(test-date-time-bombs 패턴 2)을 지시서에 명시 — travel하는 테스트가 해당 픽스처를 경계 판정에 쓰면 그 테스트를 같이 고친다.

### T4 수신 거부 번호 고정
- 마이그레이션: `clients.refused_phone`(string, nullable — 인덱스 불요). 거부 접수·전파 시점의 전화번호를 함께 저장.
- 상속(`inherit_refusal_from_same_phone`)·전파(`propagate_refusal_to_same_phone`)의 매칭을 행의 현재 `phone`이 아니라 **거부 시점 번호(`refused_phone`)** 기준으로 변경 — 거부된 행이 번호를 바꿔도 새 번호로 상속을 퍼뜨리지 않는다.
- 발송 가드 등 `client.refused?` 판정(행 단위)·되돌림 없음 원칙·화면 문구는 불변. 기존 거부 데이터(운영 0건 — 실측) 소급 불요.
- 테스트: 기존 전파·상속 테스트 전부 통과 + "거부된 행의 번호 변경 뒤 새 번호로 등록한 거래처는 상속받지 않음"·"바뀐 행 자체는 여전히 거부 상태" 경계.

### T5 사전통보 발송 시각 정합
- `PrenoticeService`의 통보 대상 선별에 실제 발송 시각 판정을 적용 — 대상 스텝의 `send_at`(재예약 슬롯 또는 `user.next_remind_slot(다음 스캔 시각)` — 직전 배치의 `Dashboards::ReminderActionsService` 산정 규칙과 동일)이 **오늘**인 청구만 사전통보. 알림톡 템플릿·문구 무변경.
- `steps_due_today`(PRENOTICE_KEYS)·발송 스캔 로직은 불변. 테스트: 주말 이월분(월요일 오전 통보), REM-3 창에 14시가 없는 회원(오늘 통보 안 함), 재예약 슬롯이 오늘 오전인 회원(통보함).

## 동시성·검증 설계

- 동시성 상한 3: 선택 태스크를 위험·소요 순으로 2웨이브 분배(예: 웨이브 1 = T1·T2·T3, 웨이브 2 = T4·T5). 단일 태스크 선택이면 단독.
- **태스크별 테스트 DB**: `DATABASE_URL=sqlite3:tmp/parallel/<task-id>/test.sqlite3` 격리 실행(기존 실측 관례). 전체 테스트·시스템 테스트·`db:migrate`·서버 기동은 태스크에서 금지 — 3-S·7-S에서 통합 실행.
- 자체 검증은 자기 소유 파일의 테스트만. 범위 밖 회귀는 7-S 전체 테스트로.
- **위임 실측 주의**: `badeuldon-reviewer-lite`의 `thoughtLevel: max` 상향(2026-11-26)은 **새 세션부터 적용**이라 — 이 세션의 reviewer-lite 스폰은 정의 이전값(high)으로 나올 수 있다. 실측해 기록하고 불일치 사유를 완료 보고에 명시한다(max 실측은 다음 세션).

## 리스크

| 리스크 | 대응 |
|:--|:--|
| T2 적용처 20곳+ — 누락·오표시 | 호출처 목록을 지시서에 전수 나열(실측 grep 기준), 테스트로 감사 IP 단언 보강, 7-S 전체 회귀 |
| T2 rate limit에 스푸핑 가능 헤더 사용 | 헤더는 CF 터널 경유 요청에만 존재(운영 원본 포트 비공개 — AGENTS.md 배포 인프라), 단일 IP 형식 검증 + fallback. PRD에 근거 기록 |
| T3 픽스처 변경이 travel 테스트와 재결합(패턴 2 폭탄) | 행별 용도 확인 후 변환, 변환 뒤 관련 테스트 즉시 실행, 날짜 의존 경계 판정 금지 규칙 지시서 명시 |
| T4 마이그레이션·행위 변경 — 절약 모드(Flash/low)에서 섬세한 로직 | 지시서에 현재 구현·경계를 전부 명시, 리뷰에서 집중 검증, 실패 시 일반 모드 재위임 검토 |
| T5 발송 심장부 인접 수정 | `steps_due_today`·스캔 불변 지시, 기존 dispatch·send 테스트 회귀 실행 |
| 알림톡 템플릿 재검수 리스크 | T5는 문구·템플릿 무변경(선별 로직만)으로 설계 |

## 파이프라인

0 → 1-P → ✅승인(multiSelect·배치 1회) → 2(선택 태스크분 PRD 직렬) → 3-P(병렬 fan-out, 상한 3·2웨이브) → 3-S(소유권 대조·마이그레이션 1회·rubocop·zeitwerk) → 4 → 5(리뷰) → 6? → 7(테스트 보강·7-P) → 7-S(`bin/ci` 1회·시스템) → 8(실행 검증) → 9(보고·문서).

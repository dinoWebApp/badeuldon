# T3 기술 부채-DB — 구현 결과 (03_implementation)

날짜: 2026-11-20 · 프로필: badeuldon-developer (절약 병렬 배치 §6.14)

## 생성/수정 파일

| 파일 | 구분 | 내용 |
|:---|:---|:---|
| `db/migrate/20261120000000_tech_debt_payments_note_and_digest_index.rb` | 신규 | 통합 마이그레이션 1건(① payments.note + ② digest 부분 유니크 인덱스) |
| `app/models/payment.rb` | 수정 | 헤더 주석 갱신 — note 컬럼 문서화(서비스 계층 전용 기록·검증 불요 근거) |
| `app/services/payments/record_service.rb` | 수정 | 과다입금 초과분 note 저장(트랜잭션 내) + 감사 로그 병행 유지 |
| `app/views/app/invoices/show.html.erb` | 수정 | 입금 이력 목록에 과다입금 비고 1줄 표시 |
| `config/routes.rb` | 수정 | `resources :sales_reps, except: :destroy` (+ 근거 주석 2행) |

`db/schema.rb`는 미수정 — 3-S 결선에서 `bin/rails db:migrate` 후 dump로 갱신(지시 제약: 마이그레이션 파일 생성만).

## ① payments.note (Q22 구조화)

- **컬럼**: `add_column :payments, :note, :string` — null 허용, default 없음. 비고는 과다입금 마감 건에만 존재하는 선택 표기이므로 모든 행에 강제할 수 없다. 사용자 입력 경로가 전혀 없어(RecordService만 기록) 모델 검증 불요 — Payment 헤더 주석에 근거 명시.
- **RecordService 변경**:
  - `record_payment!` 내, 초과분 산정 직후 **같은 with_lock 트랜잭션 안에서** `@payment.update!(note: over_note)` — 기록(payment 행)과 비고가 항상 함께 확정·함께 롤백된다(데이터 무결성). 초과분은 저장 성공 후 캐스팅된 정수로 산정하는 기존 순서 유지.
  - 문구(`over_note`): `"입금액이 남은 잔액을 N원 초과하여 마감 처리 — 초과분 환불은 거래처와 직접 협의"` (지시문 예시 문언 준수 — 천단위 콤마는 기존 `delimited` 헬퍼 재사용).
  - 감사 로그는 유지(P4): `note_over_record` → `audit_over_record`로 명칭 변경(역할 분리 반영), `payment_over_recorded` action·detail 문구·호출 타이밍(커밋 후) 모두 불변.
  - rescue 범위 주석 갱신 — `update!`도 RecordInvalid 흡수 대상(InvalidPayment 조립 경로 동일, BUG-2 방어 유지).
- **뷰 표시**: 입금 이력 목록(`show.html.erb` 531행대) — 각 payment 행 아래 `payment.note.present?`일 때 1줄 표기(`text-xs text-stone-500`). `<%= %>` 기본 이스케이프(raw/html_safe 없음). 마감 녹색 박스·부분입금 폼 등 기존 영역 불변, "마감 후 재입금"(note 없음) 건에는 변화 없음.

## ② message_logs digest 부분 유니크 인덱스 (W-1 DB 방어선)

- **인덱스**: `idx_message_logs_digest_period_uniq` — 컬럼 `[user_id, template_key, scheduled_at]`, `unique: true`, `where: "digest = 1"`.
- **멱등 판정 쿼리와 정합**: `Noti::WeeklyDigestService#already_sent_this_week?`가 `MessageLog.exists?(user_id:, template_key: TEMPLATE_KEY, scheduled_at: period_start)`로 멱등 판정한다(서비스 71-74행). 인덱스 3컬럼은 이 키와 1:1 대응 — exists? 조회가 곧 인덱스 프리픽스 히트가 되고, 경합 시 create! 단계에서 DB가 중복을 차단한다(SEC-5 — debtor pending 슬롯 인덱스와 같은 "애플리케이션 판정 유지 + DB 최후 방어선" 2중 구조).
- **where 절 표현**: `digest = 1` — 기존 선례 `idx_message_logs_debtor_pending_uniq`의 `where: "recipient_role = 0 AND status = 0"`과 같은 SQLite 정수 표현으로 통일.
- **NULL 경계**: `scheduled_at`은 WeeklyDigestService가 항상 `period_start`(결정적 주 키)로 채운다. 유니크 인덱스에서 NULL은 상호 구별되어 중복 판정에서 제외되지만, digest 행이 scheduled_at nil로 생성되는 경로는 없다(단일 진입점).
- **기존 데이터 방어**: 인덱스 생성 전 `dedup_digest_logs!` — 같은 (user_id·template_key·scheduled_at) digest 묶음에서 **최신 1행(MAX id)만 남기고 오래된 행 삭제**(지시 문언 "older 삭제"). digest 행은 주 단위 1회 기록이 의도라 동일 주기 중복은 내용상 동치이며, 최신 행이 최종 발송 상태(sent/failed)를 가장 잘 대표한다. 삭제는 비가역이므로 **up/down을 명시 분리**해 down에서 execute가 재실행되지 않게 했다(change 방식 시 rollback 재실행 위험 제거). down은 remove_index → remove_column 대칭만 수행.

## ③ routes 정리 (관찰⑤)

- `resources :sales_reps, except: :destroy` — `Admin::SalesRepsController`에 destroy 액션이 없음을 실측 확인(index/new/create/edit/update/toggle_suspension/unlock/rotate_code만 존재). 존재하지 않는 DELETE 경로가 라우팅 오류가 아닌 정상 404로 흡수된다. member PATCH 3종(toggle_suspension·rotate_code·unlock)·sales_commissions 블록 불변.

## 제약 준수

- 화이트리스트 5파일만 수정(다른 태스크 소유 파일 미접촉 — git diff로 확인).
- `bin/rails db:migrate`·부트·전체 테스트 미실행 — 3-S 이후 오케스트레이터가 통합 실행.
- PRD/AGENTS 미수정 · 커밋 없음.

## 자가 검증 결과

- `ruby -c`: 마이그레이션·record_service·payment·routes 전부 Syntax OK.
- `bin/rubocop`(변경 Ruby 4파일): **0 offenses**(초기 Layout/SpaceInsideArrayLiteralBrackets 2건은 `-a` 교정 — omakase `[ ... ]` 스타일). ERB는 RuboCop 대상 외(HTML 파싱 오오탐 — 대상에서 제외하고 눈검증).
- 마이그레이션 up/down 대칭 눈검증: up(컬럼 추가 → 중복 정리 → 인덱스) / down(인덱스 제거 → 컬럼 제거) — dedup은 up 전용(비가역, 문서화).
- ERB: `<%= %>` 이스케이프 확인, 뷰 내 쿼리 호출 없음(@payments 반복만), 들여쓰기 2칸.

## Rule ID / 결정 기록 매핑

| 항목 | 근거 | 구현 |
|:---|:---|:---|
| ① note 컬럼 | Q22 (PRD 결정 기록 — 초과분 "마감 기록 비고에 남기고" 구조화) | payments.note + RecordService 트랜잭션 내 기록 + 뷰 표시 |
| ① 감사 기록 병행 | P4 | audit_over_record(action payment_over_recorded) 불변 유지 |
| ② digest 멱등 | W-1(이전 배치 리뷰 — DB 방어선 과제)·SEC-5·NOTI-2 | 부분 유니크 인덱스 + 사전 dedup |
| ③ except: :destroy | 관찰⑤ (T-F 원 관찰) | routes 1행 |

## 후속 참고 (오케스트레이터용)

- 3-S에서 `bin/rails db:migrate` 후 `db/schema.rb` dump 필요 — payments에 `t.string "note"`·message_logs에 `idx_message_logs_digest_period_uniq` 인덱스 추가 반영 확인.
- 테스트(Phase 7) 관련: Payments::RecordService의 과다입금 시나리오 기존 테스트가 note 컬럼 존재를 전제하지 않으므로, 스키마 반영 후 재실행 권장. digest 인덱스는 경합 재실행 시나리오(WeeklyDigestJob 중복 실행)에서 `create!`가 RecordInvalid 대신 차단되는 동작 — 서비스는 exists? 판정이 먼저라 :duplicate 반환 경로 불변.

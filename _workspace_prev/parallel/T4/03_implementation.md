# T4 구현 보고 — 수신 거부를 거부 시점 번호에 고정 (VIEW-7·Q30, 2026-11-26)

## 변경 파일

| 파일 | 변경 |
|:--|:--|
| `db/migrate/20261126050721_add_refused_phone_to_clients.rb` | 신설 — `clients.refused_phone`(string, nullable·인덱스 불요) + 방어적 소급 UPDATE |
| `db/schema.rb` | 위 마이그레이션 반영(컬럼 1행 + version) — 전용 dev DB에서 `db:migrate`로 생성. diff는 이 컬럼 추가분만 |
| `app/models/client.rb` | 상속 원천 판정을 `refused_phone` 기준으로 전환 + 레거시 nil 폴백, 상속 시 `refused_phone` 기록, 주석 갱신 |
| `app/services/promises/register_service.rb` | 접수 마킹 `update_columns(refused_at:, refused_phone:)`, 전파 `update_all`에 `refused_phone` 추가(같은 `Time.current` 공유) |
| `test/models/client_test.rb` | 거부 시뮬레이션 헬퍼 `mark_refused!`(refused_at+refused_phone 동시 마킹) 도입, 한계 고정 테스트를 올바른 동작으로 교체, 폴백 경계 1건 신설 |
| `test/services/promises/register_service_test.rb` | 접수·전파 행의 `refused_phone` 단언 추가 |
| `test/controllers/app/clients_controller_test.rb` | 무수정 (고지 문구 분기 `refusal_inherited`가 그대로 동작 — 폴백 경로로 기존 시나리오 유지) |

## 마이그레이션 전문

```ruby
class AddRefusedPhoneToClients < ActiveRecord::Migration[8.1]
  def change
    add_column :clients, :refused_phone, :string

    # 기존 거부 행 소급 — 거부 시점 번호가 없는 행에 현재 번호를 채운다.
    # 운영 실측 0건(2026-11-26 읽기 전용 조회) — 방어적 소급(로컬·테스트 DB 대비).
    execute <<~SQL
      UPDATE clients
      SET refused_phone = replace(phone, '-', '')
      WHERE refused_at IS NOT NULL AND refused_phone IS NULL
    SQL
  end
end
```

## 판정 로직 전후 (Client#inherit_refusal_from_same_phone)

- **전(舊 한계)**: 원천 = 형제 중 `refused_at` 있음 + **형제의 현재 phone** 일치(`same_phone_digits`). → 거부된 행의 번호를 B로 바꾸면 그 행이 B의 상속 원천이 됨(거부한 적 없는 번호 멈춤).
- **후(본 구현)**: 원천 = 형제 중 `refused_at` 있음 + **`refused_phone == phone_digits`**(거부 시점 번호) 1순위. `refused_phone`이 nil인 행만 현재 번호 비교 폴백(마이그레이션 소급·서비스 쓰기가 전부 채우므로 운영 미발생 방어 경로 — update_column 우회 마킹 호환). 상속 시 `refused_phone`도 함께 기록.
- 전파(`propagate_refusal_to_same_phone`): 대상 판정은 기존대로 현재 번호(`same_phone_digits` — 전파 대상은 "지금 그 번호를 가진 미거부 행")이며, `update_all`에 `refused_phone: client.phone_digits`를 행마다 명시.
- `client.refused?` 행 단위 판정·되돌림 없음·화면 문구 불변.

## 동작 표 (지시서 4번)

| 시나리오 | 결과 |
|:--|:--|
| 거부된 행 R(refused_phone=A)의 phone을 B로 변경·저장 | 거부 유지(`refused?` true·refused_at/refused_phone=A 불변) — 기존 테스트에 `refused_phone` 불변 단언 추가 |
| 같은 회원이 번호 B로 신규 등록 | 상속 없음(정상 등록·refusal_inherited false) |
| 번호 A로 신규 등록 | 상속됨(R이 원천·refusal_inherited true) |
| 번호 A를 가진 정상 행이 C로 번호 변경 후 저장 | 상속 없음(신설 테스트) |
| 거부 접수·전파 | 접수 행·전파 행 전수에 refused_phone 채움(서비스 테스트에 단언) |

## 테스트 결과

- 대상 8파일: `224 runs, 1459 assertions, 0 failures, 0 errors, 0 skips`
- `bin/rubocop` 소유 6파일: no offenses / `bin/rails zeitwerk:check`: 통과
- 전용 DB: `tmp/parallel/T4/{dev,test}.sqlite3` (기본 개발 DB 미터치)

## 고친 기존 테스트와 사유

- `client_test.rb` "거부된 행이 번호를 바꿔 이동하면 새 번호 등록분도 상속한다 — 알려진 한계의 현재 동작 고정": 옛 한계 동작을 고정하던 테스트라 본 수정으로 실패 확정 → 올바른 동작(새 번호 무상속·옛 번호 상속)으로 교체, 사유 주석 명시.
- 그 외 `client_test.rb`·`register_service_test.rb`: 거부 시뮬레이션에 `refused_phone` 동시 마킹 헬퍼(`mark_refused!`)·단언 보강만.
- **무수정으로 통과한 타 파일 테스트**(`invoices_controller_test`·`clients_reminders_test`·`invoices_reminders_test`·`send_service_test`·`issue_service_test`의 상속 시나리오): 이들은 `update_column(:refused_at)`만으로 원천을 마킹한다 — 모델의 nil 폴백 경로가 호환을 제공. 폴백이 없으면 이 5파일(소유 밖) 수정이 필요했을 것.

## 남은 우려

1. **nil 폴백의 존재**: `refused_phone`이 nil인 거부 행은 여전히 현재 번호 기준 상속(舊 동작). 운영·테스트 픽스처에서 발생하지 않지만, 미래 코드가 `update_column(:refused_at)` 단독 마킹을 다시 추가하면 한계가 부활한다 — 리뷰에서 폴백 유지 여부 판정 권장(대안: 폴백 제거 + 타 파일 5곳 마킹 보강).
2. `same_phone_digits` 스코프는 전파 전용으로 용도 주석 갱신 완료 — 다른 호출처 존재 여부는 확인하지 않았다(전파 외 호출이 있으면 현재 번호 기준이므로 의미상 안전).

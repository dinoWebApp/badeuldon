# T3 — ViewEvent 하드닝 구현 문서

## 수정 파일
- `app/models/view_event.rb`
- `app/services/view_events/track_service.rb`

(컨트롤러 `app/controllers/viewer_controller.rb` 수정 없음 — CF-Connecting-IP fallback은 기존 구현 유지, 봇 UA 필터·SHARE-4 알림 발화 경로 무변경)

## 1. 중복 열람 스팸 억제

- **판정 키**: 청구서(share token과 1:1 대응인 `invoice_id`)+**정제된 IP** (`normalized_ip`와 저장값 동일 — 키 일관성 보장)
- **윈도우**: `ViewEvent::DUPLICATE_WINDOW = 30.minutes` (상수, 모델에 정의)
- **규칙**: TrackService#call 트랜잭션 내에서
  - 기록 0건(첫 열람) → 억제 판정 없이 **반드시 기록** (`first = true`, 상태 전이 + SHARE-4 알림)
  - 기록 존재 + `viewed_at >= DUPLICATE_WINDOW.ago` 동일 청구서+IP → **생성 생략**, `@suppressed = true` 후 즉시 반환 (상태 전이·알림·이벤트 모두 없음)
  - 그 외 → 기록
- **구분 반환**: `TrackService#suppressed?` (boolean 접근자)
- **위치 근거**: 모델은 "데이터·검증만" 컨벤션 유지 — 억제 오케스트레이션은 TrackService에 둠

## 2. 검증 강화 (단일 출처 — 모델 클래스 메서드)

- `ViewEvent.sanitize_ip(raw)`: 공백 제거 → 45자 절단(컬럼 limit 유지) → `IPAddr.new` IPv4/IPv6 형식 검증 → 실패 시 `"unknown"` 대체(`ip NOT NULL` 검증 유지)
- `ViewEvent.sanitize_user_agent(ua)`: nil 안전(`to_s`) → strip → `ViewEvent::UA_MAX_LENGTH = 512`자 절단. UA는 저장 컬럼이 없어 device·봇 판별 입력으로만 사용(봇 판별은 원본 UA 우선 — 기존 bot? 호출은 변경 없음, device 판별만 정제 UA 사용)
- 기존 `normalized_ip` 프라이빗 메서드는 `sanitize_ip`로 위임 + memoization

## 3. 스키마 선언 (3-S 통합 생성용 — 마이그레이션 이번 런에서 생성 금지)

```ruby
# view_events에 복합 인덱스 추가 (중복 억제 조회: invoice_id + ip + viewed_at 범위)
add_index :view_events, [:invoice_id, :ip, :viewed_at],
          name: "index_view_events_on_invoice_ip_viewed_at"
```

- 현재 `invoice_id` 단일 인덱스만 존재 → 윈도우 범위 조회가 레코드 전수 스캔. 건수 자체가 적어 즉시 필요는 아니나, 열람 누적 시 유익. 3-S에서 일괄 반영 권장.

## 4. SHARE-4 / PERF-1 불변 확인 방법

- **SHARE-4(최초 열람 알림)**: 억제 분기는 `first == false`(기록 1건 이상)일 때만 도달 — 첫 열람은 항상 기록 + `mark_viewed!` + `DeliverJob.perform_later(noti_opened, "user")`. 봇 UA 조기 반환은 기존 그대로. 코드상 알림 발화 라인 미변경.
- **PERF-1(60초)**: 억제는 "이벤트 생성 생략"만 하고 알림 경로에 손대지 않음 — 첫 열람 알림 인큐 타이밍(커밋 후 인큐) 무변경.
- **VIEW-8**: 뷰어 뷰 미수정.
- **봇 UA 필터**: `ViewEvent.bot?` 패턴·호출 순서 유지, `BOT_UA_PATTERN`의 HeadlessChrome 제외 의도 유지.
- 억제 로직은 기존 테스트(첫 열람 시나리오 = 기록 0건)와 충돌하지 않는다 — 억제는 두 번째 이후 재열람에만 적용. 테스트 실행은 3-S 이후 일괄(fan-out 제약).

## 자가 검증 결과
- `ruby -c` 두 파일 모두 Syntax OK
- `bin/rubocop app/models/view_event.rb app/services/view_events/track_service.rb` — 2 files inspected, no offenses

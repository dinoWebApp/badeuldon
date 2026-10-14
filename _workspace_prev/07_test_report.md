# 07_test_report.md — CF-Connecting-IP 기록 테스트 (Phase 7)

- **일자**: 2026-10-14
- **테스터**: CfIpTester
- **대상**: `viewer_controller.rb` `viewer_client_ip`(CF-Connecting-IP 우선·presence·remote_ip fallback) + 호출부 `ViewEvents::TrackService` ip 전달
- **시나리오 기준**: `_workspace/05_review.md` Tester 중점 제안 4분기 + INV-4 회귀
- **테스트 파일**: `test/controllers/viewer_controller_test.rb`(기존 파일에 섹션 확장 — 신규 5케이스, 기존 어설션 무손상)

## 결과 요약

| 항목 | 결과 |
|:---|:---|
| 대상 파일 실행 (`bin/rails test test/controllers/viewer_controller_test.rb`) | **21 runs, 152 assertions, 0 failures, 0 errors, 0 skips** (기존 16 + 신규 5) |
| 전체 회귀 (`bin/rails test`) | **363 runs, 2216 assertions, 0 failures, 0 errors, 0 skips** (기존 358 + 신규 5) |
| `bin/rubocop` | **100 files inspected, no offenses** (0에러) |
| 코드 버그 | **0건** — 실패·에러 전무, 원인 분류 대상 없음 |
| 외부 API 실호출 | 0건 (뷰어 통합 테스트, stub 불요 경로) |

## 신규 케이스 상세

| # | 테스트 | 검증 내용 | 결과 |
|:--|:---|:---|:---|
| 1 | CF-Connecting-IP 헤더가 있으면 실방문자 IP를 기록한다 (SHARE-3) | `CF-Connecting-IP: 203.0.113.7` → `ViewEvent.ip == "203.0.113.7"`, `first?` true, `issued→viewed` 전이(헤더 유무와 무관) | ✅ |
| 2 | CF-Connecting-IP가 없으면 remote_ip fallback을 유지한다 (SHARE-3) | 헤더 없음 + `REMOTE_ADDR=198.51.100.77` → `ip == "198.51.100.77"` — fallback 원천이 remote_ip임을 명시 | ✅ |
| 3 | 빈 CF-Connecting-IP 헤더는 fallback으로 수렴한다 (SHARE-3 — .presence 분기) | `CF-Connecting-IP: ""` → `.presence` nil → remote_ip 기록 | ✅ |
| 4 | IPv6 IP는 45자 컬럼 한계 내 그대로 기록된다 (SHARE-3) | 39자 전체 표기 `2001:0db8:85a3:0000:0000:8a2e:0370:7334`·45자 IPv4 매핑 최장 표기 `0000:0000:0000:0000:0000:ffff:255.255.255.255`(string limit 45 경계) 모두 변형 없이 기록 | ✅ |
| 5 | CF-Connecting-IP가 바뀐 재열람은 상태·first 플래그에 무영향이다 (INV-4·SHARE-3) | 서로 다른 IP로 이중 접속 → 상태 `viewed` 유지, 이벤트 2건, `first` 최초 1건만 true — IP 교체가 트랜잭션·전이에 무영향 | ✅ |

### fallback(제안 2분기) 중복 명시

기존 테스트 **「최초 열람은 viewed 전이와 first 이벤트를 기록한다 (INV-4·SHARE-3)」**가 헤더 없는 요청에서 `event.ip == "127.0.0.1"`을 이미 단정 — 리뷰어 권고(수정 없이 유지)대로 **무변경 유지하고 회귀로 확인**했다(본 실행에서 통과). 신규 #2는 기본값 `127.0.0.1` 단정과 중복을 피하기 위해 `REMOTE_ADDR`를 별도 값으로 주입해 fallback이 우연한 상수가 아니라 `request.remote_ip`에서 온다는 점까지 검증한 것이다. 전이 무관성(제안 5분기)도 기존 재열람 테스트 + 신규 #1·#5로 이중 확인.

## 구현 정합성 근거

- `viewer_client_ip`는 `request.headers["CF-Connecting-IP"].presence || request.remote_ip` — 테스트는 이 3분기(우선·빈값·부재)를 정확히 매핑.
- `view_events.ip`는 `string limit: 45`(`db/schema.rb:125`)·presence 필수(`ViewEvent`) — #4가 상한 경계, 전 케이스가 presence 충족.
- TrackService 무변경: 이벤트 기록과 `mark_viewed!`가 동일 트랜잭션 — #1·#5에서 기록+전이 동시 성립으로 회귀 확인.

## 품질 자체 점검

- [x] 제안 4분기 + INV-4 회귀 모두 커버 (정상 #1·2 / 경계 #3·4 / 회귀 #1·5)
- [x] 외부 API 실호출 0건
- [x] 미사용 정의 0건 · `bin/rubocop` no offenses · 들여쓰기 2칸
- [x] 기존 어설션 무손상(기존 16케이스 전부 통과) · 전체 회귀 363 runs 통과
- [x] 실패 0건 → 원인 분류(코드 버그 vs 테스트 오류) 해당 없음

## 비고

- `bin/rails test`는 358 → **363** runs(신규 5건 증분만, 소거 0).
- 테스트 소스 외 프로덕션 코드 변경 없음 — 본 Phase는 테스트 전용.

# 03_implementation.md — 운영 배포 설정 확정 + CF 실방문자 IP 기록

- **일자**: 2026-10-14
- **범위**: 플랜 B(구현) 1~3 전부 · 서버 접촉·빌드 없음(Phase 8 전 configuration 검증만)

## 1. 변경 파일

| 파일 | 변경 |
|:---|:---|
| `config/deploy.yml` | 전면 확정 — 서버·SSH·프록시·레지스트리·accessory 확정, 스켈레톤 예시 제거 |
| `config/environments/production.rb` | `assume_ssl = true` 활성화 + `force_ssl = true` 명시 |
| `app/controllers/viewer_controller.rb` | ViewEvent IP 출처를 `viewer_client_ip` 헬퍼로 교체 |
| `.kamal/secrets` | `KAMAL_REGISTRY_PASSWORD` 더미값 추가(아래 3.2 사유) |

## 2. 확정 값

| 항목 | 값 |
|:---|:---|
| 서버(Tailscale) | `100.98.162.61` (web + job 동일 호스트, role 분리) |
| SSH 사용자 | `kgj` |
| 도메인 / SSL 종단 | `badeuldon.kr` / Cloudflare 터널 종단 → 앱은 http 수신 |
| kamal-proxy 바인딩 | `127.0.0.1:3000`(cloudflared만 도달, 공개 포트 0) |
| 레지스트리 | `100.98.162.61:5000`(accessory `registry:3`, Tailscale 인터페이스 바인딩, `registry_data` 볼륨) |
| 이미지 | `badeuldon`(builder `arch: amd64` 크로스 빌드) |

### deploy.yml 구조 비고
- **job role 분리**: `servers.job.cmd: bin/jobs` — `env.clear.SOLID_QUEUE_IN_PUMA` 제거(규약 §11.3).
- **`proxy.run` 네스팅**: Kamal 2.12에서 `http_port`·`bind_ips`는 `proxy.run` 하위 키다. 플랜 원문의
  `proxy: { http_port, bind_ips }` 평면 배치는 `unknown keys` 검증 오류로 기각 —
  `kamal-2.12.0/lib/kamal/configuration/proxy/run.rb` 스키마 확인 후 `run:` 하위로 배치.
- **`ssl: false`, `host` 없음**: CF 터널이 SSL 종단하므로 kamal-proxy 자동 인증서 미사용.

### environments/production.rb 비고
- `config.assume_ssl = true` — 주석 해제. CF 종단 대응.
- `config.force_ssl = true` — **주석 해제(명시)**. 플랜은 "기본값 유지"로 가정했으나
  `RAILS_ENV=production` 실측에서 Rails 8.1 기본값이 `false`였다(실측 출력: `true / true` —
  force_ssl / assume_ssl). AGENTS.md 「배포 인프라」의 "assume_ssl+force_ssl 필수" 요건을
  충족하려면 명시가 필요해 해제했다.

## 3. Kamal 검증 필수 사항 2건 (플랜 외 발견 — 해결)

1. **`registry.username` 필수**: Kamal 2.12는 무인증 레지스트리도 `registry/username`을 요구한다
   (`ConfigurationError: registry/username: is required`).
2. **해결**: `username: badeuldon` + `password: [KAMAL_REGISTRY_PASSWORD]`(시크릿 참조)로 선언하고
   `.kamal/secrets`에 더미값 `badeuldon` 추가. registry:3 무인증 레지스트리의 `docker login`은
   항상 성공하므로 동작상 영향 없음 — Kamal 검증 요건 충족용 더미이며 git-safe 값.

## 4. CF-Connecting-IP 기록 (ViewerController — ViewEvent 한정)

- private 헬퍼 신설: `viewer_client_ip` = `request.headers["CF-Connecting-IP"].presence || request.remote_ip`
- `ViewEvents::TrackService`는 `ip:` 키워드 인자를 이미 받으므로 **호출부 값 교체만** 수행(서비스 무변경).
- `show` 액션의 ViewEvent 기록에만 적용 — 전역 `remote_ip` 재계산(미들웨어)은 플랜대로 후속.
- **기존 테스트 영향(Phase 7 갱신 대상)**: `test/controllers/viewer_controller_test.rb:67`
  `assert_equal "127.0.0.1", event.ip` — 통합 테스트는 CF 헤더가 없어 **fallback 경로로 그대로 통과**
  (전체 스위트 리그레션 0). 단, Phase 7에서 **헤더 있음/없음 2분기 테스트 추가 권장**:
  (a) `headers: { "CF-Connecting-IP" => "203.0.113.7" }`로 열람 시 `event.ip == "203.0.113.7"`
  (b) 헤더 없으면 `event.ip == "127.0.0.1"` — 기존 테스트 수정 없이 신규 추가만.

## 5. 검증 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | 100 files inspected, **no offenses** |
| `bin/rails zeitwerk:check` | **all is good** |
| `bin/kamal config` | **통과** — roles `job, web` / host `100.98.162.61` / `ssh: {user: kgj}` / `repository: 100.98.162.61:5000/badeuldon` / builder `arch: amd64` / accessory `registry`(`registry:3`, `100.98.162.61:5000:5000`, `registry_data:/var/lib/registry`) — 서버 미접촉 확인 |
| `bin/rails test` | **358 runs, 2195 assertions, 0 failures, 0 errors, 0 skips** |
| production 부팅 실측 | `force_ssl=true`, `assume_ssl=true` |

## 6. Rule 매핑

| 근거 | 구현 |
|:---|:---|
| SHARE-3(열람 메타 기록 정합) | ViewEvent IP가 CF 터널 경유 시 실방문자 IP로 기록 — 터널/NAT 뒤 `remote_ip`(127.0.0.1) 오기록 방지 |
| P4(모든 발신은 기록) | 열람 기록 무손실 — TrackService 트랜잭션 구조 유지, 호출부 값만 교체 |
| 규약 §11.3(job 분리) | `servers.job` role + `bin/jobs`, `SOLID_QUEUE_IN_PUMA` 제거 |
| AGENTS.md 「배포 인프라」 | 확정 값 표·프록시 바인딩·레지스트리 accessory 전부 문서와 일치 |

## 7. Phase 8(오케스트레이터) 인계 메모

- 서버·PC 양단 `insecure-registries: ["100.98.162.61:5000"]` 사전 설정이 레지스트리 push/pull 전제(플랜 D-2·D-3).
- cloudflared → `localhost:3000` 포워딩이 kamal-proxy `127.0.0.1:3000` 바인딩과 정확히 맞물림.
- `.kamal/secrets`의 `RAILS_MASTER_KEY`는 기존 라인 유지, `KAMAL_REGISTRY_PASSWORD`는 더미(무인증 레지스트리) — 레지스트리에 인증을 도입하는 시점에 실 시크릿으로 교체.

## 수정 이력 (Phase 8 — 공유 레지스트리 분리)

- **일자**: 2026-10-14 · **대상**: `config/deploy.yml` 1건 (AGENTS.md는 오케스트레이터가 갱신 — 미접촉)

### 근거

서버(100.98.162.61)에 여러 서비스가 올라가므로 Docker 레지스트리는 badeuldon 전용 accessory가
아닌 **서버 공유 인프라로 독립 운영**한다. 레지스트리의 실행·볼륨(registry_data)·백업은
badeuldon Kamal 관리 대상에서 제외되며, Kamal에서는 push/pull 대상(`registry:` 참조)으로만
사용한다. 이에 따라 deploy.yml에서 `accessories:` 섹션을 제거한다.

### 변경 diff 요약 (`config/deploy.yml`)

1. **삭제** — `accessories:` 섹션 전체(주석 포함 8행):
   `accessories.registry` = image `registry:3` · host `100.98.162.61` · port `100.98.162.61:5000:5000` ·
   directory `registry_data:/var/lib/registry`
2. **주석 갱신** — `registry:` 섹션 헤더 주석을 공유 인프라 사유로 교체:
   「레지스트리 — 서버 공유 인프라로 독립 운영(여러 서비스 공용, badeuldon Kamal accessory 미관리) /
   Kamal에서는 push/pull 대상으로만 참조(실행·백업은 Kamal 관리 밖) / Tailscale 망 내 HTTP —
   양단 Docker insecure-registries 등록 전제」
3. **무변경** — `registry:` 섹션 값 3종은 그대로(push/pull 대상 동일):
   `server: 100.98.162.61:5000` · `username: badeuldon`(더미) · `password: [KAMAL_REGISTRY_PASSWORD]`
4. **파수 효과** — 이 저장소에서 `kamal accessory` 커맨드(registry 부팅 등)는 더 이상 유효하지 않음.
   레지스트리 기동은 서버 측 공유 인프라 구성(docker run/compose 등)으로 담당.

### 검증 결과 (서버 미접촉)

| 점검 | 결과 |
|:---|:---|
| `bin/kamal config` | **통과(exit 0)** — `roles: job, web` / `primary_host: 100.98.162.61` / `ssh.user: kgj` / `repository: 100.98.162.61:5000/badeuldon` / builder `arch: amd64` — **`accessories` 키 소멸** 확인, YAML 파스·Kamal 검증 정상 |
| `bin/rubocop` | **100 files inspected, no offenses** (deploy.yml은 YAML이라 rubocop 검사 대상 아님 — 파일 직접 지정 시 Ruby 파서가 YAML을 파싱하는 오탐 발생은 도구 범주 오류) |
| 서버 접촉 | **없음** — kamal config는 로컬 설정 검증만 수행 |

## 수정 이력 (Phase 8b — 공개 표면 브라우저 허용)

- **일자**: 2026-10-14 · **대상**: `app/controllers/` 6건(concern 1 신설 + 컨트롤러 5)

### 실측 근거

운영 https://badeuldon.kr (Phase 8 실측)에서 iPhone 인앱 WebView(UA에 `Safari/604.1` —
카카오톡 인앱 등)가 랜딩 `/`에서 **406 Not Acceptable**로 차단됐다. 원인은
`ApplicationController`의 `allow_browser versions: :modern` 상속 — 공개 표면(랜딩·인증
화면)까지 모던 브라우저 게이트가 적용된 것. 뷰어(`ViewerController`)는 Phase 7의 VIEW-1
수정에서 no-op `def allow_browser(**); end` 오버라이드로 이미 통과 중이며, 동일 메커니즘을
공개 표면 전체로 확장한다. (actionpack 8.1은 `versions: :all` 미지원 — NoMethodError
실증, 상속 before_action은 익명 람다라 `skip_before_action`으로도 해제 불가.)

### 변경 (6파일)

1. **신설** `app/controllers/concerns/allow_all_browsers.rb` — 공용 concern `AllowAllBrowsers`:
   private no-op `allow_browser(**)` 인스턴스 메서드 1개로 상속 게이트를 무효화.
   뷰어의 기존 오버라이드 주석(VIEW-1 실측·actionpack 8.1 제약·`/app·/admin` :modern 불변)을
   이동 보존.
2. **include 추가 5종** — 공개 표면 컨트롤러에 1행 include(각 1~2행 VIEW-1 주석 동반):
   `LandingController`(표면 ①), `SessionsController`·`RegistrationsController`·
   `PasswordsController`(인증 진입), `ViewerController`(③ — 기존 no-op 메서드+주석 블록은
   제거하고 include로 대체, 메커니즘 상세는 concern 주석 참조 주석 유지).
3. **미변경** — `App::` 계열(/app)은 `:modern` 유지(Turbo·모던 JS 전제 관리화면, 변경 금지),
   `ApplicationController`·라우트·뷰 무접촉.

### 기존 테스트 영향 조사 (갱신 대상)

- `test/controllers/viewer_controller_test.rb:196` — 구형·인앱 UA 406 회귀 테스트(VIEW-1):
  concern 전환 후 동일 동작이라 **수정 불요, 그대로 통과**.
- 랜딩·인증 3종 컨트롤러 테스트에 406/브라우저 관련 어설션 **부재** — 갱신 대상 없음
  (grep `406|allow_browser|Not Acceptable` 전체 test/ 확인).

### 검증 결과

| 점검 | 결과 |
|:---|:---|
| `bin/rubocop` | **101 files inspected, no offenses** |
| `bin/rails zeitwerk:check` | **all is good** |
| `bin/rails test` | **363 runs, 2216 assertions, 0 failures, 0 errors, 0 skips** — VIEW-1 406 회귀 포함 전부 통과 |


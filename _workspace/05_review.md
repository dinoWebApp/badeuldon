# 05_review.md — 운영 배포 설정 + CF-Connecting-IP 기록 리뷰 (Phase 5)

- **일자**: 2026-10-14
- **리뷰 대상**: `config/deploy.yml` · `config/environments/production.rb` · `app/controllers/viewer_controller.rb` · `.kamal/secrets` (git 변경분 4건)
- **검증 방법**: Kamal 2.12.0 젬 소스 대조(스키마·명령 생성부) · Rails 8.1.4 actionpack/railties 소스 대조(AssumeSSL·SSL 미들웨어) · solid_queue 1.7.0 CLI 확인 · 프로젝트 파일 실측. 코드 수정 없음.

## Status: CHANGES_REQUESTED

**코드 4건은 수정 불요(APPROVED 수준)** — 단, Phase 8 실행 계획(`01_plan.md` §D-4)에 **BLOCKER**가 확인되어 상태를 CHANGES_REQUESTED로 기록한다. 수정 대상은 런북(계획 문서)이며, 재리뷰 대상도 수정된 Phase 8 순서 문서뿐이다(코드 재리뷰 불요).

## 배포 준비 판정: NO-GO (조건부 GO)

- **NO-GO 사유**: 예정된 `bin/kamal setup`(D-4)이 신규 서버에서 **확정 실패**한다(이슈 #1 — 레지스트리 기동 순서 chicken-and-egg).
- **GO 조건(전부 충족 시)**:
  1. §D-4에 「레지스트리 1회 사전 기동」 단계 삽입 (이슈 #1의 명령 순서 그대로)
  2. D-1~D-3(클라우드플레어드 restart 정책·서버/PC `insecure-registries`)은 계획대로 유지 — 본 리뷰에서 정합 확인됨
  3. 첫 배포 후 서버에서 `badeuldon-registry` 컨테이너가 kamal 관리 체계(라벨 `service=badeuldon-registry`)로 인식되는지 `bin/kamal accessory details registry`로 확인

## 이슈 목록

| # | Severity | Rule ID | File:Line | 설명 | 수정 제안 |
|---|----------|---------|-----------|------|-----------|
| 1 | **BLOCKER** | AGENTS.md 「배포 인프라」 (실행 계획) | `_workspace/01_plan.md` §D-4 | **첫 `bin/kamal setup` 순서 결함 — 레지스트리 chicken-and-egg.** Kamal 2.12 `deploy`는 `build:deliver`(Mac 로컬 `docker login 100.98.162.61:5000` → 빌드 → push)를 accessory 기동 **이전**에 실행한다(`kamal/cli/main.rb:31→40`, 로그인 기본 활성 `commands/builder/base.rb:64-66`). 신규 서버엔 레지스트리가 없으므로 로그인이 connection refused로 실패 → setup 중단. 더해서 `bin/kamal accessory boot registry`도 prepare 단계에서 서버측 `docker login`을 컨테이너 기동 **전**에 수행한다(`kamal/cli/accessory.rb:11,332-341` + `kamal/commands/registry.rb:2-11` — accessory에 `registry:` 없으면 주 레지스트리로 fallback) → 이 경로도 실패. 존재 판정은 컨테이너명이 아닌 **라벨** 기반이다(`commands/accessory.rb:40-42,115-117`). | §D-4 직전에 1회 수동 기동 삽입: `ssh kgj@100.98.162.61` → `docker network create kamal`(없을 때) → `mkdir -p ~/badeuldon-registry/registry_data` → `docker run -d --restart unless-stopped --name badeuldon-registry --label service=badeuldon-registry --network kamal -p 100.98.162.61:5000:5000 -v "$HOME/badeuldon-registry/registry_data:/var/lib/registry" registry:3` → 이후 `bin/kamal setup`(accessory boot는 기존 컨테이너를 라벨로 인식해 skip, kamal 관리로 이관됨). **대안(검토용)**: Kamal 2.12 네이티브 로컬 레지스트리 모드(`registry.server: localhost:5555`)는 로그인·insecure 설정·accessory가 전부 불필요하고 pull을 SSH 포워드로 처리한다(`configuration/registry.rb:22-28`, `cli/build.rb:21,74`) — 단 AGENTS.md로 확정한 서버 상시 레지스트리 아키텍처와 배치되므로 Main 판단 사항. |
| 2 | WARNING | AGENTS.md 「배포 인프라」 (문서 정합) | `config/deploy.yml:47-48` | accessory `directories: ["registry_data:/var/lib/registry"]`는 도커 **네임드 볼륨이 아니라** 호스트 바인드 디렉터리로 마운트된다. Kamal 2.12는 상대 경로 `local`을 `$PWD/<service>-<accessory>/<name>` 호스트 경로로 확장해 `--volume` 처리한다(`configuration/accessory.rb:88-102,219-233`, `configuration/volume.rb:15-27`). 실제 데이터 위치는 SSH 접속 기본 cwd(= `/home/kgj`) 하위 `badeuldon-registry/registry_data`. 영속성은 확보되나(정합성 문제 없음) 03 보고서·주석의 "볼륨" 표현과 실제가 어긋나 백업 경로 안내 시 혼동 여지. | 동작 유지하되 AGENTS.md 백업 노트에 실제 경로(`/home/kgj/badeuldon-registry/registry_data`) 명시. 네임드 볼륨을 원하면 accessory에 `volumes: ["registry_data:/var/lib/registry"]` 키 사용(`specific_volumes`는 원문 그대로 `-v` 전달). |
| 3 | INFO | — (운영 인지 사항) | `config/deploy.yml:24-26` | `proxy.run.http_port: 3000` 지정 시에도 kamal-proxy는 `https_port` 기본 443을 함께 publish한다 — 결과 `--publish 127.0.0.1:3000:80 --publish 127.0.0.1:443:443`(`configuration/proxy/run.rb:36-46`). 루프백 전용이라 공개 노출 면은 0이며 현재 충돌 서비스 없음. | 조치 불요. 향후 서버 로컬에서 443을 쓰는 서비스 추가 시 `proxy.run.https_port` 조정. |
| 4 | INFO | — (운영 인지 사항) | `config/deploy.yml:46` | `-p 100.98.162.61:5000:5000` 바인딩은 해당 IP가 호스트에 존재할 때만 성공한다. 서버 재부팅 시 Docker가 tailscaled보다 먼저 뜨면 registry 컨테이너 시작이 일시 실패하나 `restart: unless-stopped`(accessory 기본, `configuration/accessory.rb:108-110`)가 재시도해 Tailscale 기동 후 복귀한다. | 조치 불요. Phase 8 사후 점검 항목에 "재부팅 후 `docker ps`로 badeuldon-registry·kamal-proxy 복귀 확인" 추가 권장. |

**BLOCKER 없던 것으로 확인된 항목(위양성 방지 근거)**: 아래 "검증 상세" 참조.

## 검증 상세 — 이슈 표 외 전수 확인 결과

### 1. 배포 설정 (Kamal 2.12 젬 소스 대조)

| 점검 | 결과 | 근거 |
|:---|:---|:---|
| `proxy.run` 네스팅(`http_port`·`bind_ips`) | ✅ 정확 | `kamal-2.12.0/lib/kamal/configuration/proxy/run.rb:24-34` — 두 키 모두 `run:` 하위 스키마. 플랜의 평면 배치 기각 판단(03 보고서 §2)은 젬 소스와 일치 |
| 공개 노출 면 0 | ✅ | `publish_args`가 `--publish 127.0.0.1:3000:80` 생성(run.rb:36-46). 루프백 바인딩은 테일넷에서도 도달 불가. 서버 공개 포트 0(AGENTS.md)과 정합 |
| `ssl: false` + `host` 없음 | ✅ | CF 종단 구조에서 ACME 시도 없음. `proxy.hosts` 미지정 → kamal-proxy 라우트가 모든 Host 헤더 수용(`configuration/proxy.rb:28-30,70-94`) — 단일 앱·터널 전용 토폴로지에서 정상 |
| job role 단일 실행 | ✅ | role당 컨테이너 분리(`badeuldon-job`) + `bin/jobs` → `SolidQueue::Cli.start(ARGV)`의 기본 커맨드가 supervisor 기동(solid_queue 1.7.0 `cli.rb:31` "Default command"). `SOLID_QUEUE_IN_PUMA` 제거로 웹 롤의 puma 플러그인 비활성(`config/puma.rb:38` 조건부) — **§11.3 준수, 이중 실행 경로 없음**. Solid Queue claim(DB)이 2차 방어 |
| 볼륨 web/job 공유 | ✅ | 서비스 레벨 `volumes`는 전 롤의 `docker run`에 적용(`commands/app.rb:29`). SQLite 4개 DB(primary/cache/queue/cable, `config/database.yml`) 모두 `/rails/storage` 하위 → `badeuldon_storage` 볼륨 하나로 web·job 공유 |
| 스켈레톤 정리 누락 없음 | ✅ | 구본 active 설정은 placeholder(서버·`localhost:5555`)와 `SOLID_QUEUE_IN_PUMA: true`뿐. 후자 제거는 §11.3 준수 목적의 의도적 변경. `aliases`·`volumes`·`asset_path`·`builder.arch: amd64` 유지 확인 |
| registry username 더미 | ✅ | `validator/registry.rb` — 서버가 `localhost`가 아닌 이상 username 필수. `username: badeuldon` + `[KAMAL_REGISTRY_PASSWORD]` 참조는 젬이 승인하는 형태(`STRING_OR_ONE_ITEM_ARRAY_KEYS`). 무인증 registry:3의 login은 항상 성공 |
| master key 전달 경로 | ✅ | 이미지에 미포함(`.dockerignore`의 `/config/master.key`) + `env.secret: [RAILS_MASTER_KEY]` → 호스트 0600 env 파일 → 컨테이너. `.kamal/secrets`는 `$(cat config/master.key)` 치환식과 더미값뿐 — **git 노출 무해 확인** |

### 2. SSL/헤더 — assume_ssl+force_ssl·CF-Connecting-IP

**리다이렉트 루프 없음(구조 검증)**: Rails 8.1.4 `default_middleware_stack.rb:20-27` — `assume_ssl`은 `ActionDispatch::AssumeSSL` 미들웨어로 구현되며 요청 env에 `HTTPS=on`, `rack.url_scheme=https`, `X-Forwarded-Proto=https`를 강제한다(`middleware/assume_ssl.rb:20-27`). 이 미들웨어가 `ActionDispatch::SSL`(force_ssl)보다 먼저 스택에 삽입되므로, kamal-proxy가 http로 전달한 터널 트래픽은 항상 SSL 요청으로 간주되어 **301 리다이렉트가 발생하지 않는다**. 반대로 assume_ssl이 없으면 `X-Forwarded-Proto: http` → force_ssl 301 → CF → http → 301의 무한 루프가 발생하므로, 이 조합은 본 토폴로지에서 **필수이며 정확히 구성됨**. HSTS·Secure 쿠키는 브라우저 기준 https(CF 종단)에서만 전달되어 정상 작동. Rails 8.1 production 기본값 force_ssl=false 실측(03 보고서)에 근거한 명시도 타당.

**CF-Connecting-IP 위조 가능성 분석 (핵심 검증)**:

| 위조 시도 경로 | 차단 근거 |
|:---|:---|
| 공인망 → 서버:3000 직접 | kamal-proxy publish가 `127.0.0.1:3000` 루프백 한정. 서버 공개 포트 0(AGENTS.md 「배포 인프라」) — **불가** |
| 테일넷 장비 → 서버:3000 | 루프백 바인딩은 테일넷 인터페이스 리스닝이 아님 — **불가** (SSH 포워드는 관리자 신뢰 경계 내) |
| cloudflared 인바운드 직접 | cloudflared는 아웃바운드 터널 연결만 사용(리스닝 포트 없음) — **불가** |
| CF 경유 요청에 위조 헤더 실어 보내기 | Cloudflare edge는 클라이언트가 보낸 `CF-Connecting-IP`를 **항상 실접속 IP로 덮어쓴다** — **불가** |
| 잔여: 서버 로컬 프로세스·`kamal` 도커 네트워크 내부에서 Puma 80 직접 호출 | 물리적으론 가능하나 서버·이미지 침해를 전제로 한 신뢰 경계 내 — 위협 모델 외 |
- **fallback 경로 질 보강(참고)**: kamal-proxy는 `ssl: false`일 때 `X-Forwarded-For`·`X-Forwarded-Proto`를 기본 전달한다(공식 문서 "will forward them if it is set to `false`"). CF edge가 XFF 체인에 실접속 IP를 남기므로, 터널 경유 요청의 `remote_ip` fallback도 RemoteIp 미들웨어의 우측-소비 규칙상 실방문자 IP로 수렴할 가능성이 높다(03 보고서의 "remote_ip 127.0.0.1 오기록" 전제보다 양호). CF-Connecting-IP 우선 정책은 단일 신뢰 값이라는 점에서 여전히 우위이며 구성 유지 타당.

**결론: 현 토폴로지에서 실질적인 위조 경로 없음.** 단 이 신뢰는 `bind_ips: [127.0.0.1]`에 조건부다 — 향후 디버깅 등으로 `0.0.0.0` 바인딩으로 바꾸는 순간 비인증 뷰어 경로(`/b/:token`)에서 헤더 위조로 IP 위장이 가능해진다. deploy.yml 주석(deploy.yml:18-21)에 이미 이 전제가 명시되어 있어 유지 강조만으로 충분하다.

**ViewEvent 무결성 유지**: `viewer_client_ip`(`viewer_controller.rb:63-65`)는 `show`의 ViewEvent 기록에만 사용되며 인가·rate_limit(`rate_limit by: -> { params[:token] }`, viewer_controller.rb:14 — **token 기반이라 IP 위조와 무관**)에 관여하지 않는다. `view_events.ip`는 `string limit: 45`(`db/schema.rb:125`)로 IPv6 최장 표현(45자)까지 수용. `.presence`가 빈 헤더를 fallback으로 처리한다. `TrackService`는 무변경(키워드 인자 `ip:` 그대로) — 트랜잭션·first 플래그 로직 무손실. fallback `remote_ip`도 안전: RemoteIp 미들웨어는 XFF를 우측부터 신뢰 프록시만 소비하므로 외부 주입 XFF는 반영되지 않는다.

### 3. 운영 보안

- **레지스트리 무인증 HTTP 노출 면**: publish `100.98.162.61:5000` — 테일넷 인터페이스 한정. 테일넷 내 장비는 push/pull/delete 가능하나 개인 망 구성에서 수용 범위(AGENTS.md에 "Tailscale 망 내" 문서화됨). 레지스트리에 실 인증 도입 시점에 `.kamal/secrets` 더미 교체 필요 — 03 보고서 §7 인계 메모에 이미 기록됨.
- **`.kamal/secrets` git 추적**: 내용은 전부 안전(치환식·더미·주석). 파일 헤더 자체가 "git-safe 필수"를 명시. 실 시크릿 반입 시 사고 여지는 있으나 운영 규칙으로 통제 중 — INFO.

### 4. 무회귀

- 기존 358 테스트 통과는 03 보고서 §5 확인(리뷰에서 재실행하지 않음). CF 헤더가 없는 통합 테스트는 `viewer_client_ip`의 fallback(`remote_ip`) 경로를 그대로 통과한다 — `test/controllers/viewer_controller_test.rb:67`의 `assert_equal "127.0.0.1", event.ip`는 변경 불요(호출부 교체가 조건부 우선순위만 추가).
- `production.rb` 나머지 설정·라우트(`/up` — `config/routes.rb:34` D-5 검증용) 무변경.

## Rule ID 준수 매핑

| 근거 | 구현·준수 |
|:---|:---|
| SHARE-3 (열람 메타 기록 정합) | CF 터널 경유 요청의 ViewEvent IP가 실방문자 IP로 기록 — 터널/NAT 뒤 `remote_ip`(127.0.0.1) 오기록 방지. 최소 범위(ViewEvent 한정) 설계 유지 |
| P4 (모든 발신은 기록) | `TrackService` 무변경·호출부 값만 교체 → 열람 기록 무손실, 트랜잭션 구조 보존 |
| 규약 §11.3 (웹·잡 분리) | `servers.job`(cmd: bin/jobs) + `SOLID_QUEUE_IN_PUMA` 제거 — 문서 요구사항과 정확히 일치(ARCHITECTURE_CONVENTURE 1172-1183행) |
| AGENTS.md 「배포 인프라」 | 서버·SSH·CF 터널→3000·프록시 바인딩·레지스트리 accessory·크로스 빌드·볼륨 전부 문서와 일치 (이슈 #2의 데이터 실제 경로만 보충 필요) |

## Tester에게 제안하는 중점 테스트 영역 (Phase 7)

1. **CF 헤더 있음**: `get viewer_path(token), headers: { "CF-Connecting-IP" => "203.0.113.7", "User-Agent" => DESKTOP_UA }` → `event.ip == "203.0.113.7"` (03 보고서 §4 권고 (a)와 동일)
2. **CF 헤더 없음(fallback)**: 기존 `viewer_controller_test.rb:67` 테스트가 이미 커버 — 수정 없이 유지 (권고 (b))
3. **빈 헤더**: `headers: { "CF-Connecting-IP" => "" }` → fallback으로 수렴하는지(`.presence` 분기) — 신규 추가 권장
4. **IPv6 값**: `"2001:db8::1"` 기록 성공(컬럼 limit 45 경계) — 신규 추가 권장
5. **전이 무관성**: IP 교체와 무관하게 INV-4 `issued→viewed` 1회 전이·`first` 플래그 유지 — 기존 테스트 커버, 회귀로 확인

## Phase 8 실행 체크리스트 검증

| 단계 | 판정 | 비고 |
|:---|:---|:---|
| D-1 cloudflared `docker update --restart unless-stopped` | ✅ 유지 | 터널 자동 복귀. 호스트 병렬 프로세스가 이중화 완충(플랜 리스크 기술과 정합) |
| D-2 서버 `/etc/docker/daemon.json` `insecure-registries: ["100.98.162.61:5000"]` + docker 재시작 | ✅ 유지 | 레지스트리 pull·login 전제. Docker 재시작 후 컨테이너 복귀 확인 포함 양호 |
| D-3 PC Docker Desktop insecure-registries(GUI) | ✅ 유지 | Mac측 `docker login`·push 전제(D-4 첫 단계에서 필수) |
| D-4 `bin/kamal setup` | ❌ **수정 필요(이슈 #1)** | 레지스트리 1회 사전 기동 단계를 setup 앞에 삽입해야 함. setup 흐름 내 `db:prepare`(Dockerfile entrypoint)·배포 헬스체크는 무관계로 정상 — kamal-proxy 기본 헬스체크 경로 `/up`(공식 문서 "hit `/up` once every second")·라우트 존재(`config/routes.rb:34`)·`silence_healthcheck_path = "/up"`와 정합 |
| D-5 도메인 확인(`https://badeuldon.kr`·`/up` 200) | ✅ 유지 | `/up` 라우트 확인. force_ssl 리다이렉트 없음(위 검증)으로 200 응답 가능 |
| (신규 권장) 사후 점검 | ➕ 추가 권장 | `bin/kamal app details`·`bin/kamal accessory details registry`(라벨 인식 확인), 재부팅 습성(이슈 #4), `/home/kgj/badeuldon-registry/registry_data` 데이터 적재 확인 |

## 재리뷰 범위

- 이슈 #1의 D-4 수정(런북) 반영 후 해당 섹션만 재확인 — 코드 4건은 재리뷰 불요.
- 이슈 #2는 문서(AGENTS.md 백업 노트) 반영 권고로, Phase 2 산출물에 반영 시 별도 재리뷰 불요.

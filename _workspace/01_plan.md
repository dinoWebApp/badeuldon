# 01_plan.md — 운영 배포 설정 + 첫 배포 (Cloudflare Tunnel · Tailscale · 로컬 레지스트리)

- **일자**: 2026-10-14
- **pipelineType**: Full — 배포 설정·코드 보강(CF IP)·**실서버 배포 실행**(Phase 8) 포함
- **도메인**: F-EXT(운영 인프라) — PRD 명세 변경 없음

## 인프라 현황 (Phase 0 실측)

| 항목 | 값 |
|:---|:---|
| 서버 | 물리 서버 · Tailscale `100.98.162.61` · SSH `kgj`(키 인증 BatchMode 통과) · Docker 29.7.2 · daemon.json 없음 |
| 터널 | cloudflared **도커 컨테이너**(`dreamy_lederberg`, Up) + 호스트 프로세스 병렬 → CF에서 HTTPS 종단, `localhost:3000`로 포워드 |
| PC | Docker 27.3.1 · insecure-registries 미설정(추가 필요) |
| 레지스트리 | 서버 로컬 accessory(Tailscale 인터페이스 바인딩) 방침 확정 |

## A. 문서 현행화 (Phase 2 — 오케스트레이터)

**AGENTS.md에 「배포 인프라」 섹션 신설**: Tailscale 주소·SSH 사용자, CF Tunnel→3000 구조(SSL은 CF 종단·`assume_ssl`), 로컬 레지스트리 accessory, insecure-registries 양단 설정 위치, kamal 운영 명령(setup/deploy/rollback/logs/console), cloudflared 컨테이너 restart 정책, SQLite 볼륨 백업 노트. (PRD 갱신 불요 — 제품 명세 무관, 사유 기록)

## B. 구현 (Phase 3 — Developer)

1. **`config/deploy.yml` 전면 확정**:
   - `servers.web/job.hosts: [100.98.162.61]`, `ssh.user: kgj`
   - `proxy: { ssl: false, http_port: 3000, bind_ips: [127.0.0.1] }` — cloudflared만 도달, 무중단 전환 유지
   - `registry: { server: 100.98.162.61:5000 }` + `accessories.registry`(image registry:3, port `"100.98.162.61:5000:5000"` Tailscale 바인딩, 데이터 볼륨)
   - `image: badeuldon`, `env.secret: [RAILS_MASTER_KEY]`, `SOLID_QUEUE_IN_PUMA` 제거(job 분리 §11.3)
2. **`config/environments/production.rb`**: `assume_ssl = true` 주석 해제(force_ssl true 확인)
3. **CF-Connecting-IP 보강(최소 범위)**: `ViewerController`의 ViewEvent IP 기록을 `request.headers["CF-Connecting-IP"].presence || request.remote_ip`로 — 터널 경유 시 실방문자 IP 기록(SHARE-3 정합). 전역 remote_ip 재계산 미들웨어는 후속

## C. 검증 (Phase 4·5·7)

- Phase 4: rubocop·zeitwerk + **`bin/kamal config`**(YAML 파스·role/accessory 검증)
- Phase 5: 설정 정합 리뷰(프록시 바인딩·볼륨·시크릿 경로)
- Phase 7: CF IP 헤더 테스트(헤더 있음/없음 fallback 2분기 + 기존 회귀)

## D. 배포 실행 (Phase 8 — 오케스트레이터 직접, 실서버 조작)

1. **사전**: cloudflared 컨테이너 `docker update --restart unless-stopped` (Docker 재시작 후 터널 자동 복귀)
2. **서버**: `/etc/docker/daemon.json`에 `insecure-registries: ["100.98.162.61:5000"]` 생성 → `systemctl restart docker` → 컨테이너 복귀·터널 확인
3. **PC**: Docker Desktop insecure-registries 추가 — **사용자 GUI 조작 1회 필요**(Settings → Docker Engine에 `"100.98.162.61:5000"` 추가·Apply) — 설정 파일 직접 편집은 버전 호환 리스크로 피함
4. **`bin/kamal setup`**: 레지스트리 기동 → 이미지 빌드(arm64→amd64 크로스) → push → 배포 → `db:prepare` → `/up` 헬스체크
5. **도메인 확인**: `https://도메인` 랜딩·/up 200 실측 (터널→3000→kamal-proxy→app)

## 결정 사항 (제안)

1. cloudflared 컨테이너 재시작 정책 `unless-stopped` 설정 — Docker 재시작 생존 보장
2. PC insecure 등록은 사용자 GUI(가이드 제공, 나는 검증만) — Docker Desktop 설정 파일 편집 회피
3. CF-IP 보강은 ViewEvent 최소 범위 — 전역 프록시 대응은 후속
4. **Phase 8 검증을 위한 도메인 명칭 공유 필요**

## 리스크

- 크로스 빌드(arm64 Mac→amd64) 첫 빌드 10~20분 소요 가능 — 이후 레이어 캐시로 단축
- Docker 재시작 순간 터널 수 초 단절(호스트 cloudflared 프로세스가 병렬 실행 중이라 이중화 완충)
- Kamal 초기 setup 실패 시 원인별 대응(레지스트리 연결→insecure 플래그, 빌드→아키텍처)

## Phase 6 (런북 정정 — 리뷰 BLOCKER 반영)

§D-4 수정 — 첫 배포 시퀀스 (레지스트리 chicken-and-egg 해소):
1. cloudflared 컨테이너 `docker update --restart unless-stopped`
2. 서버 `/etc/docker/daemon.json` 생성(insecure-registries) → `systemctl restart docker` → cloudflared 자동 복귀 확인
3. **레지스트리 1회 수동 기동** (kamal 라벨 부여 — 이후 kamal setup이 인식·이관):
   `docker run -d --restart unless-stopped --label service=badeuldon-registry --network kamal -p 100.98.162.61:5000:5000 -v /home/kgj/badeuldon-registry/registry_data:/var/lib/registry registry:3`
4. PC Docker Desktop insecure-registries에 `"100.98.162.61:5000"` 추가 (사용자 GUI)
5. `bin/kamal setup` → 도메인 확인

## Phase 8 정정 2 (공유 레지스트리 — 사용자 요청)

서버에 여러 서비스를 올리므로 레지스트리를 badeuldon accessory가 아닌 **서버 공유 인프라**로 분리:
- deploy.yml `accessories:` 제거(kamal config 통과), `registry:` 섹션(push/pull 대상) 유지
- 서버 기동 명령 변경 — kamal 라벨 제거·`--name registry`·데이터 경로 `/home/kgj/registry/registry_data`:
  `docker run -d --name registry --restart unless-stopped -p 100.98.162.61:5000:5000 -v /home/kgj/registry/registry_data:/var/lib/registry registry:3`
- 이후 다른 서비스도 `registry.server: 100.98.162.61:5000` + 고유 `image:` 이름으로 같은 레지스트리 사용

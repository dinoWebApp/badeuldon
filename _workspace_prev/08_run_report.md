# 08_run_report.md — Phase 8 실행 검증 (운영 첫 배포)

- **일자**: 2026-10-14
- **대상**: badeuldon.kr 운영 배포 (Tailscale·CF Tunnel·공유 레지스트리·Kamal)

## 배포 결과

| 항목 | 결과 |
|:---|:---|
| `bin/kamal setup` (첫 배포) | ✅ web·job 컨테이너 healthy (211s) — 빌드·push·배포·db:prepare |
| 운영 버전 | `7f9be0eb…` (커밋 SHA 태그) |

## 운영 실측 (https://badeuldon.kr)

| 표면 | 결과 |
|:---|:---|
| 랜딩(①) 데스크톱 | ✅ 200 (35.6KB) — 헤드라인·CTA·요금제·FAQ 렌더 |
| **랜딩(①) 인앱 UA(iPhone Safari/604.1)** | ✅ **200** — 결함 수정 후 (아래) |
| 랜딩 안드로이드 구형(Chrome/111)·크롤러 | ✅ 200 |
| 가입·로그인 화면(인앱 UA) | ✅ 200 |
| `/up` 헬스체크 | ✅ 200 |
| `/app`(②) 비인증 | ✅ 302 → session/new |
| `/b/무효토큰`(③) | ✅ 404 |

## 배포 과정에서 발견·해소한 결함 4건 (다계층 검증의 가치)

| # | 결함 | 해소 |
|:---|:---|:---|
| 1 | **buildx push 실패** — buildx 컨테이너 빌더는 Docker Desktop insecure-registries 미상속 → HTTPS push 시도 | `config/buildkitd.toml` 작성 후 `kamal-local-docker-container` 빌더를 재생성(HTTP 레지스트리 허용) — Kamal이 재사용 |
| 2 | **터널 502 (복제 경합)** — cloudflared가 bridge망 컨테이너로도 실행: 컨테이너의 localhost:3000 ≠ 호스트 | 호스트 네트워크 단일 복제로 재생성(`--restart unless-stopped`) + 감시자 없던 날 프로세스 제거. ※ 원본 토큰은 중지 컨테이너 Cmd에서 추출(재전사 오류 1회 → 이 경로로 확정) |
| 3 | **터널 502 (TLS)** — CF 대시보더 서비스 URL이 `https://localhost:3000`로 TLS 시도 | 사용자가 `http://localhost:3000`로 수정 (프록시 plain-HTTP) |
| 4 | **공개 표면 406** — `allow_browser :modern`이 랜딩·인증까지 차단(인앱 UA) | `AllowAllBrowsers` concern으로 공개 5종 컨트롤러 허용, /app·/admin은 :modern 유지 |

## 운영 교훈 (기록)

- **Kamal 버전 태그 = git HEAD SHA** — 미커밋 변경은 새 버전으로 취급되지 않아 이전 이미지 재배포됨(19.8s 재배포의 정체). **배포 전 커밋 필수**
- 레지스트리·cloudflared·kamal-proxy 전부 `restart: unless-stopped` — 서버 재부팅 시 전체 자동 복귀
- 터널 토큰이 로그·프로세스 목록에 노출될 수 있음 — 추후 Cloudflare 터널 토큰 로테이션 권장(후속)

## 결론

**운영 배포 완료** — Phase 9 진행.

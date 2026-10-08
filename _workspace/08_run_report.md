# 08_run_report.md — Phase 8 실행 검증

- **일자**: 2026-10-08
- **대상**: 랜딩 루트 화면(표면 ① 골격) — `_workspace/03_implementation.md` 구현분

## 부트 검증

| 항목 | 결과 |
|:---|:---|
| 서버 기동 | ✅ `bin/dev` — Puma 8.0.2, Rails 8.1.4 development, Ruby 4.0.7 (mise), 127.0.0.1:3000 |
| 부트 로그 에러 | ✅ 없음 (Puma start 정상 출력) |

## 라이브 응답 검증 (curl 실측)

| 검증 | 결과 |
|:---|:---|
| `GET /` | ✅ HTTP 200, 3714B, **0.14s** |
| `<title>` | ✅ 「받을돈 — 말하기 어려운 '돈 다오', 받을돈이 대신합니다」 (content_for 반영) |
| h1 헤드라인 (LP-1/Q6) | ✅ 「말하기 어려운 '돈 다오', 받을돈이 대신합니다」 |
| 주 CTA | ✅ 「카카오로 시작하기」 + 「무료 · 카드등록 없음 · 3분」 + aria-disabled |
| 보조 CTA | ✅ 「작동 방식 보기」 |
| SURF-3 색인 허용 | ✅ 응답에 noindex 없음 |
| `GET /up` 헬스체크 | ✅ HTTP 200 |

## WARN 분류

| 분류 | 항목 | 조치 |
|:---|:---|:---|
| **[수정 필요 → 해결]** | 서비스 셸 환경에서 `bin/dev` 자식 프로세스가 mise PATH를 못 물려 macOS 시스템 Ruby 2.6으로 실행 → Gemfile 파싱 실패(1차 부팅 실패) | `PATH=~/.local/share/mise/...:$PATH` 명시 후 재기동으로 해결. **환경 문제이며 코드 결함 아님** — 개선 후보: `bin/dev` 무관, 추후 `.mise.toml`/셸 프로파일 PATH 정리 (별도 환경 작업) |
| [허용] | foreman 설치 안내(시스템 gem 권한 에러) — mise 루비에 foreman 이미 존재하여 무해 | 기록만 |
| [주의] | Tailwind CSS watch(css.1)는 부팅됨 — `app/assets/builds` 산출물은 본 검증 범위 외(HTML 응답 검증) | 시각 검증은 LP-2~13 후속 작업 시 수행 |

## 결론

실행 검증 **통과** — Phase 9 진행.

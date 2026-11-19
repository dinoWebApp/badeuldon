# Outbound Mail API — 사용 및 운영 가이드 (addendum v1.0.0)

- 기준 명세: `03-company-mail-outbound-api-addendum-v1.0.0.md`
- Base URL: `https://mail-api.veloloop.kr` (Cloudflare Tunnel → `http://127.0.0.1:3001`)
- 로컬 검증: `http://127.0.0.1:3001`

## 전송 경로 (변경 금지)

```
회사 서비스 → POST /api/v1/emails → Rails Action Mailer (:sendmail)
  → Ubuntu 로컬 Postfix → SMTP2GO Relay ([mail.smtp2go.com]:587) → 수신자
```

Rails은 SMTP2GO REST API를 호출하지 않고 SMTP 자격증명을 알지 못한다.
Postfix relay 구성은 v2.2.0 설정을 그대로 재사용한다.

## Endpoints

| Method | Path | 인증 |
|---|---|---|
| POST | `/api/v1/emails` | `Authorization: Bearer <MAIL_API_TOKEN>` |
| GET | `/api/v1/emails/:id` | 동일 토큰 (작성 클라이언트만) |
| POST | `/webhooks/smtp2go` | `Authorization: Bearer <SMTP2GO_WEBHOOK_TOKEN>` |

기존 `POST /internal/v1/inbound`, `GET /internal/healthz`는 변경 없음.

## 1. API Client 토큰 발급 (운영자)

```bash
# 신규 서비스 등록 — 토큰은 이때 한 번만 출력됨
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:create[keymesh-api]'

# 발신 주소 허용 (활성 메일 사용자 또는 alias만 등록 가능)
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:allow_sender[keymesh-api,contact@veloloop.kr]'

# 목록 / 비활성화 / 토큰 회전 / 발신 주소 해제
sudo /opt/company-mail/scripts/run-rake.sh mail:api_client:list
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:disable[keymesh-api]'
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:rotate[keymesh-api]'
sudo /opt/company-mail/scripts/run-rake.sh 'mail:api_client:revoke_sender[keymesh-api,contact@veloloop.kr]'
```

- 토큰 원문은 DB에 없다(SHA-256 digest + 표시용 prefix만 저장).
- 토큰은 호출 서비스의 Secret Manager에 보관하고 URL/로그/채팅에 넣지 않는다.
- 서비스마다 별도 클라이언트를 발급한다(공용 토큰 금지).

## 2. 발신 요청

```bash
curl --request POST \
  --url https://mail-api.veloloop.kr/api/v1/emails \
  --header "Authorization: Bearer ${MAIL_API_TOKEN}" \
  --header "Content-Type: application/json" \
  --header "Idempotency-Key: <논리적 발송 단위별 고유 키>" \
  --data '{
    "from":   { "email": "contact@veloloop.kr", "name": "Veloloop 고객지원" },
    "to":     [ { "email": "customer@example.com", "name": "홍길동" } ],
    "cc":     [],
    "bcc":    [],
    "reply_to": { "email": "contact@veloloop.kr" },
    "subject": "서비스 이용 안내",
    "text_body": "안녕하세요. Veloloop입니다.",
    "html_body": "<h2>안녕하세요.</h2><p>Veloloop입니다.</p>",
    "attachments": [
      { "filename": "guide.pdf", "content_type": "application/pdf",
        "content_base64": "<base64>" }
    ]
  }'
```

규칙:

- `Idempotency-Key` 필수(8~128자, `[A-Za-z0-9._-]`). 재시도에는 **같은 키 재사용**.
- `from.email`은 그 클라이언트의 허용 발신 주소이자 활성 회사 주소여야 한다.
- `text_body`/`html_body` 중 하나 이상. `reply_to`는 승인된 회사 주소만.
- 임의 헤더(Message-ID/Sender/Received 등) 주입 불가. Message-ID는 서버 생성.
- Bcc는 SMTP envelope에만 포함되고 헤더/로그/조회 응답에 노출되지 않는다.

### 응답

성공 `202 Accepted`:

```json
{ "success": true, "data": { "id": "mail_...", "message_id": "<...@veloloop.kr>",
  "status": "accepted_by_postfix", "accepted_at": "...",
  "recipients": { "to": 1, "cc": 0, "bcc": 0 } } }
```

**202는 "로컬 Postfix 접수 완료"만 뜻한다.** SMTP2GO 접수·최종 배달 여부는
`GET /api/v1/emails/:id` 또는 SMTP2GO Webhook으로 확인한다.

오류:

| HTTP | code | 상황 |
|---|---|---|
| 400 | INVALID_REQUEST | JSON/필드/Base64/파일명 오류, Idempotency-Key 문제 |
| 401 | UNAUTHORIZED | 토큰 누락/오류/비활성 |
| 403 | SENDER_NOT_ALLOWED | 허용 안 된 발신 주소 |
| 404 | MESSAGE_NOT_FOUND | 타 클라이언트 소유 포함 |
| 409 | IDEMPOTENCY_CONFLICT | 같은 키 + 다른 payload |
| 413 | REQUEST_TOO_LARGE | 요청 15MiB / 첨부 디코딩 합계 10MiB 초과 |
| 422 | INVALID_RECIPIENT | 주소/수신자 수(≤50) 검증 실패 |
| 429 | RATE_LIMITED | 분당(클라이언트별, 기본 30) / 일일(전체, 기본 100) 초과 |
| 502 | LOCAL_MTA_ERROR | 로컬 Postfix 제출 실패 |
| 503 | MAIL_SERVICE_UNAVAILABLE / MANUAL_REVIEW | DB 장애 / 제출 결과 불명확 |

### Idempotency 동작

- UNIQUE `(api_client, idempotency_key)`.
- 같은 키 + 같은 payload → 기존 메시지 ID/상태 반환(재발송 없음, `idempotent_replay: true`).
- 같은 키 + 다른 payload → 409.
- `submitting`이 5분 이상 지속(비정상 종료) → `manual_review` 전이, **자동 재발송 없음**.

## 3. 상태 조회

```bash
curl https://mail-api.veloloop.kr/api/v1/emails/mail_XXXX \
  -H "Authorization: Bearer ${MAIL_API_TOKEN}"
```

수신자별 상태: `accepted_by_postfix → processed → delivered` 또는
`soft_bounced / hard_bounced / rejected`. Bcc 주소는 응답에 없고 `bcc_count`만 표시된다.

## 4. 운영 파라미터

`/etc/company-mail/ingest-api.env` (수정 후 `systemctl restart company-mail-ingest`):

| 변수 | 기본 | 설명 |
|---|---|---|
| MAIL_API_RATE_LIMIT_PER_MINUTE | 30 | 클라이언트별 분당 신규 발신 |
| MAIL_API_DAILY_LIMIT | 100 | 전체 일일 발신(합산) |
| MAIL_API_MAX_RECIPIENTS | 50 | to+cc+bcc 상한 |
| MAIL_API_MAX_ATTACHMENT_BYTES | 10485760 | 첨부 디코딩 합계 상한 |
| MAIL_API_MAX_REQUEST_BYTES | 15728640 | HTTP 요청 상한 |
| SMTP2GO_WEBHOOK_TOKEN | (생성됨) | webhook Bearer (원본은 `/etc/company-mail/smtp2go-webhook.token`) |

## 5. 장애 추적

```bash
sudo journalctl -u company-mail-ingest -n 100        # API/전송 로그 (본문 미기록)
sudo postqueue -p                                    # Postfix 큐
grep '<ulid>@veloloop.kr' /var/log/mail.log          # Message-ID 추적
sudo /opt/company-mail/scripts/run-rake.sh runner \
  'puts MailApiMessage.order(created_at: :desc).limit(10).pluck(:id, :status, :error_code)'
```

`manual_review` 처리: 위 조회로 Message-ID 확인 → mail.log에서 접수 여부 확인 →
필요 시 수동 재요청(새 Idempotency-Key).

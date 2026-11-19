# 01_plan — F-EMAIL 자체 메일 API 연동 (2026-11-20, Full · 일반 모드 · Sequential)

## 배경

AUTH-8(U1 비밀번호 재설정)·AUTH-7.4/7.6(관리자 잠금 통보·신규 IP·재설정)은 개발 로그 발송 대체 상태. 사용자가 **자체 메일 서버를 HTTP API로 공개**(Cloudflare Tunnel — SMTP 포트 미공개)하여 이를 표준 이메일 채널로 승격. 사양: 루트 `OUTBOUND_MAIL_API.md`(POST /api/v1/emails·Bearer MAIL_API_TOKEN·**Idempotency-Key 필수**·202=Postfix 접수·SMTP2GO 릴레이·분 30/일 100 한도).

## 핵심 설계 — 커스텀 ActionMailer 배달 방식

기존 메일러(`PasswordsMailer.reset`·`AdminMailer` 3종·`deliver_later` 경로 포함)를 **한 곳도 수정 없이** 전환한다:

1. `app/services/outbound_mail/client_service.rb` — HTTP 래퍼(솔라피/바로빌 래퍼 패턴): credentials `outbound_mail: {base_url, token, from_email, from_name, reply_to}` 기본값+주입·Bearer·타임아웃·오류 코드 매핑(`OutboundMail::ApiError` — status+code)·202 파싱(id·message_id 캡처)·**실호출 주입 차단**(test/dev 기본 stub)
2. `app/services/outbound_mail/delivery_method.rb` — `ActionMailer` 커스텀 배달 방식(`deliver!(mail)`): 렌더된 text/html 파트 추출→payload 조립(from/reply_to는 credentials로 강제 — API 허용 발신 주소 정책)→**Idempotency-Key = mail.message_id 정제**(bd.{id} — 잡 재시도에 동일 키 재사용·자연 멱등)→ClientService 호출
3. 등록: initializer `ActionMailer::Base.add_delivery_method :outbound_mail_api, OutboundMail::DeliveryMethod`·production에서 `delivery_method = :outbound_mail_api`(**credentials token 부재 시 로그 폴백 유지** — NOTI-3 선례: 등록 전 동작 불변)
4. `ApplicationMailer` default from → credentials(from_email)·제목/본문 문구 점검(기존 뷰 재사용·한국어)
5. `raise_delivery_errors` true(production) — API 5xx/429 시 잡 재시도(Solid Queue retry_on)

## 전환 대상(수정 0줄·배달 방식만으로)

- U1 비밀번호 재설정(AUTH-8)·관리자 잠금 통보·신규 IP 알림(AUTH-7.4)·관리자 재설정(AUTH-7.6)

## 사용자 운영 절차(산출에 안내 — 게이트 확정 대상)

1. 메일 서버: `mail:api_client:create[badeuldon]` → 토큰 확보·`allow_sender[badeuldon, <발신 주소>]`
2. credentials `outbound_mail` 블록 등록(base_url·token·from_email·from_name·reply_to)
3. 등록 전까지 기존 로그 발송 유지(무중단)

## 대상 파일

- 신규: `app/services/outbound_mail/{client_service,delivery_method}.rb`·initializer 1건
- 수정: `config/environments/production.rb`(배달 방식·raise_delivery_errors)·`app/mailers/application_mailer.rb`(from)·PRD(AUTH-8 구현 확정·EXT 표 '지정')·메일러 뷰 문구(필요 시 최소)
- 테스트: 래퍼 단위(stub)·배달 방식(payload 조립·멱등 키·폴백)·기존 passwords/admin 메일러 테스트 갱신(로그 단정→배달 stub 단정)

## Rule ID

AUTH-8(구현 확정)·AUTH-7.4/7.6(동일 경로)·EXT-1(이메일 발송 '미지정'→'지정 — 자체 Outbound Mail API)·SEC-5(멱등 — Idempotency-Key)·P4(발송 기록: 로그 수준) — 신규 Rule ID 불요

## 리스크

1. **from 주소**: API는 사전 허용된 회사 주소만 발신 가능 — 권고 `contact@veloloop.kr`(문서 예시·기 허용 가능성) 또는 전용 alias 신설(예: `badeuldon@veloloop.kr`) — 게이트에서 확정
2. **일일 100건 한도**(전체 합산) — 재설정+관리자 통보 트래픽은 충분·429 처리(재시도) 확인
3. 202≠최종 배달 — 배달 확인은 상태 조회(웹훅은 받을돈이 안 받음) — v1은 발송 접수까지만(계약된 범위)·추적은 메일 서버 journalctl
4. 메일 스팸 정책(DMARQ/SPF veloloop 도메인) — 서버 구성 v2.2.0 재사용으로 이미 준수(문서 명시)

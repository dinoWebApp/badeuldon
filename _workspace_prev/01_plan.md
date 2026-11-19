# 01_plan — F-SALES 후속: 인증번호 알림톡 전환 (2026-11-19, Standard · 절약 모드)

## 배경

AUTH-9 인증번호를 SMS로 구현한 이유는 인증번호 알림톡 템플릿 미등록(검수 필요). 사용자 요청으로 **알림톡 우선·SMS 폴백** 전환 — 템플릿 등록 전에도 가입 플로우 무중단·등록 즉시 자동 알림톡(NOTI-3 선례 패턴).

## 구현 범위 (Standard — 기존 로직 수정)

1. `PhoneVerifications::SendService` — 발송 경로 이원화:
   - `TEMPLATE_KEY = "phone_verification"` 상수 — credentials `solapi.template_ids.phone_verification`에 키 존재 시 `send_alimtalk(template_key:, to:, variables: { 인증번호: code })`(래퍼 기존 — variables는 `#{}` 키 규격)
   - 키 부재·발송 실패(ApiError 등) 시 기존 `send_sms` 폴백 (기록: MessageLog 아님 — phone_verifications 행에 발송 채널 컬럼 없이 로그만? **채널 기록 없이 단순 폴백·실패 시에도 인증번호는 반드시 전달** — 부분 실패 시 SMS가 최종 결과)
   - rate limit·만료·1회용 로직 불변
2. PRD AUTH-9 문구 갱신: "SMS 문자" → "알림톡 우선(템플릿 `phone_verification` — 등록 전 SMS 폴백)"
3. 테스트 갱신: 알림톡 경로(키 존재 stub)·폴백 경로(키 부재·알림톡 실패)·기존 rate limit 시나리오 유지
4. **사용자 운영 작업 안내(산출에 포함)**: 솔라피 콘솔 템플릿 등록 — 문구 제안 `[받을돈] 가입 인증번호는 [#{인증번호}]입니다. 5분간 유효합니다.` (변수 1개·검수 통과용 간결) + 등록 후 credentials `solapi.template_ids.phone_verification`에 템플릿 ID 추가

## 대상 파일

- `app/services/phone_verifications/send_service.rb`(주 수정)·`PRD.md`(AUTH-9 1문장)·`test/services/phone_verifications/send_service_test.rb`

## Rule ID

AUTH-9(경로 전환)·REM-10(솔라피 템플릿 체계)·NOTI-3 선례(등록 전 폴백·자동 활성화)

## 리스크

- 알림톡 variables 키 형식(`#{인증번호}`)은 F-REM 확정 스펙 준용 — 템플릿 등록 문구의 변수명과 코드 키 일치 필요(안내 문구에 변수명 "인증번호" 고정)
- 폴백 이중 발송 가능성(알림톡 성공했는데 실패 오판) 방지: 실패 판정은 ApiError 예외 기준(래퍼 fail-fast) — 성공 응답 후 폴백 없음

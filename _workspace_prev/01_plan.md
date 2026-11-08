# 01_plan — F-REM 리마인더 시퀀스 구현 (2026-11-04, Full 파이프라인)

## 배경·전제

알림톡 18종 전원 솔라피 승인·credentials 등록 완료(2026-11-04, PRD v0.25·ALIMTALK_TEMPLATES.md).
`:solapi:` 블록 전항목 실측 확인(api_key·api_secret·pf_id·sender_number·template_ids 18종).
F-REM 착수 전제 조건 전부 충족. 코드에는 발송 연동이 전무 — 솔라피 래퍼부터 시퀀스 엔진·
이벤트성 알림·U1 noti·수신거부·overdue 저장화까지 일괄 구현한다.

## 작업 범위

### 1. 솔라피 래퍼 (REM-10)
- `app/services/solapi/client_service.rb` — PortOne::ClientService 패턴 그대로(Net::HTTP 순수
  래퍼·주입 가능·ApiError). 알림톡 발송 단일 진입점. credentials `:solapi:` dig 주입.
- REM-5 대체문자는 템플릿 자체 필드로 처리 확정(2026-11-03) — 별도 SMS 설계 없음.
- 솔라피 응답 스펙의 세부 필드는 [INFERENCE] 마킹 + 테스트 stub(라이브 실측 후보 = 기술 부채).

### 2. 발송 이력 모델 (REM-6·P4·SEC-5·PLAN-3)
- `message_logs` 테이블: invoice·client·user(수신자 맥락), recipient_role(debtor|user),
  template_key, step(스텝 식별자), origin(auto|manual), status(sent|failed|skipped),
  provider_message_id·error, scheduled_at·sent_at. 사용자 임의 삭제 불가(P4) — 삭제 경로 없음.
- SEC-5 멱등: 유니크 인덱스 [invoice_id, step, origin] — 동일 청구·동일 단계 자동 발송 1회.
- PLAN-3 상한: 채무자 향 sent 5통(대체문자 포함) 초과 시 skip + 사유 기록. U1 향 noti_*는 상한 밖.

### 3. 시퀀스 엔진·잡 (REM-2·3·4·11·12, PROMISE-3, SHARE-5)
- 발송 트랙(ALIMTALK_TEMPLATES "발송 트랙" 절 그대로):
  - 기본: invoice_notice(D-1) → confirm_d1|confirm_d1_opened(D+1, 열람 분기 REM-4/SHARE-5) →
    requeue_d7(D+7) → final_d14(D+14, 자동 종결 REM-12)
  - 약속: 등록 즉시 기본 트랙 중단 → promise_d1(약속일-1) → promise_overdue(약속일+1)
  - 부분입금: partial_paid(입금 기록 시 즉시, 잔액 기준 문구)
- recurring 3종(KST 고정 fugit 접미사):
  - 07:00 매일: **overdue 저장화** — unsettled + 만기 경과 → `mark_overdue!`(조건부 UPDATE,
    promised 제외). Invoice 주석 "enum 자동 전환은 F-REM 스케줄러와 함께"의 이행.
  - 09:00 평일: **사전통보 잡** — D+1/D+7/D+14 예정건 U1에게 noti_prenotice(REM-11) +
    D-1 건 U1에게 noti_due_soon(NOTI-1)
  - 14:00 평일: **발송 잡** — 스텝 도래 채무자 발송. 직전 재확인: 마감·보류(REM-7)·수신거부
    (VIEW-7)·자격(plus?|수금패스 — REM-8)·상한. 취소 창 = 09~14시 사이 U1 액션.
- REM-3: 평일 09:00~18:00 고정. 스텝 산정 시 주말·창 밖은 **다음 평일 09시 이연**.
  사용자 세부 지정은 후순위(기술 부채로 PRD 명시).
- 즉시 발송(perform_later): issue_notice(SHARE-6 발행 시), noti_opened(SHARE-4, PERF-1 60초),
  noti_promise(PROMISE-4), noti_deposit_reply(PROMISE-7), noti_inquiry(PROMISE-6),
  noti_refusal(VIEW-7), partial_paid(PAY-2), paid_thanks(PAY-4), noti_promise_unkept(NOTI-1,
  약속 도과 = promise_overdue 발송 시점).
- 채무자 향 즉시 발송(issue_notice·partial_paid·paid_thanks)도 REM-3 창 준수 — 창 밖 접수는
  다음 평일 창으로 예약(scheduled_at). U1 향 noti_*는 즉시(PERF-1).

### 4. 상태·컬럼 (REM-7·VIEW-7·SHARE-6·PAY-4)
- invoices: `reminders_suspended_at`(REM-7 건 단위), `sequence_finished_at`(REM-12 종결)
- clients: `reminders_suspended_at`(REM-7 거래처 단위), `refused_at`(VIEW-7 수신거부 — 번호 단위 즉시 중단)
- promises: kind에 `refusal` 추가(VIEW-7 회신 이력 보존 P4)
- SHARE-6: 발행 폼에 "서비스 명의 안내 알림톡 발송" 선택(기본값 선택) → issue 시 issue_notice
- PAY-4: 마감(원클릭) 폼에 감사 알림 체크박스 **기본 켬** → 마감 확정 시 paid_thanks

### 5. UI (표면 ②·③)
- /app 청구서 상세: 발송 이력(REM-6)·수동 발송 버튼(REM-8, Free 포함 — 현재 상황에 맞는
  다음 1통, 상한·수신거부는 동일 적용)·보류/재개(REM-7)·감사 알림 체크
- /app 거래처: 보류/재개(거래처 단위 REM-7) + 수신거부 상태 표시
- 뷰어(③): 하단 고지 근처 "추가 안내 수신 거부" 작은 링크 → 확인 → 접수(VIEW-7.
  VIEW-8 화이트리스트에 수신 거부 진입이 포함됨을 PRD에 명시)
- noti_prenotice 버튼 2개(마감하기=기존 마감 화면·보류하기=보류 액션)는 웹링크 → 기존/신규 화면 재사용

### 6. 범위 밖 (후속 명시)
- REM-9 문구 직접 편집 — **정정 제안**(하단 설계 결정 ②): 알림톡 사전검수 제약으로 제공 불가
- REM-3 세부 지정 UI(고정값으로 구현), NOTI-2 주간 다이제스트(템플릿 미등록), NOTI-3(INV-7 전),
  DASH-5/6, F-ADMIN 크레딧 모니터링(ADMIN-5), 웹훅 기반 발송 상태 회수

## 설계 결정 사항 (승인 게이트 질의)

1. **promise_overdue 이후 final_d14 재개 여부** (PRD 미명시 — ALIMTALK_TEMPLATES.md 지적)
   - 권고: **재개 없이 promise_overdue로 시퀀스 종결** — 상한 5통 산정과 정합(어느 해석이든
     6통째 방지), 약속 파기 후 자동 재독촉은 P1 리스크, 수동 재요청 경로(REM-12)가 이미 존재.
     확정 시 REM-13으로 PRD 신규 등재.
2. **REM-9 폐기(정정)**: 알림톡은 솔라피 사전검수 승인 문구만 발송 가능 — 사용자 편집 문구는
   구조적으로 발송 불가. "직접 편집"을 폐기하고 변수(발행인 표시명 등)가 청구서별 반영되는
   구조로 명세 정정(결정 기록 Q9 추가).

## 대상 파일 (예상)

| 구분 | 파일 |
|---|---|
| 문서 | PRD.md(v0.26 — REM-9 정정·REM-13·VIEW-8 보강·NOTI-2 후순위), ALIMTALK_TEMPLATES.md(키 정리 주석) |
| DB | db/migrate/(message_logs 생성 + invoices·clients·promises 컬럼) |
| 모델 | message_log.rb(신규), invoice.rb(mark_overdue!·보류·종결), client.rb(수신거부·보류), promise.rb(refusal kind) |
| 서비스 | solapi/client_service.rb·api_error.rb, reminders/(발송 실행·스텝 산정·U1 알림) |
| 잡 | reminders/(사전통보·발송·overdue·즉시발송), config/recurring.yml |
| 컨트롤러·라우트 | app/invoices(보류·재개·수동발송 member + issue 옵션), app/clients(보류·재개), app/payments(감사 옵션), viewer(수신거부), config/routes.rb |
| 뷰 | app/views/app/invoices/(상세 이력·버튼·발행 폼 옵션), app/views/app/clients/, app/views/viewer/(수신거부) |
| 테스트 | test/models·services·jobs·controllers·system (Rule ID별 시나리오) |

## 관련 Rule ID

REM-1~8·10~12 (REM-9 정정 대상) / SHARE-4·5·6 / PROMISE-3·4·6·7 / PAY-2·4 / PLAN-3·4 / VIEW-7·8 /
NOTI-1 / SEC-5 / PERF-1 / TIME-1 / P1~P5. PRD §6.6·§6.5·§6.7·§6.8·§6.11·§6.12·ALIMTALK_TEMPLATES.md.

## 에이전트 지시 요약 (Developer 순차 2회 위임 — 동일 파일 병렬 금지 준수)

- **3-a 백엔드**: 마이그레이션 → 모델(+enum·전이·검증) → Solapi 래퍼 → Reminders 서비스 → 잡·recurring → 라우트 결선. 산출물 `03_implementation.md`.
- **3-b 프론트**: 컨트롤러(얇게·params.expect) → 뷰(ERB·표현 3줄+ 헬퍼·UI 품질 기준) → 발행 폼 SHARE-6 옵션 → 뷰어 수신거부. `03_implementation.md` 갱신.
- **Phase 5 Reviewer**: Rule ID 정합성(최우선)·SEC-5 멱등·상한·의존 방향·VIEW-8 마케팅 무결성·REM 톤.
- **Phase 7 Tester**: Rule ID별 정상/경계/예외 — 멱동(동시 발송 경합)·상한 경계(5통째/6통째)·평일 이연(금→월)·약속 재스케줄·수신거부 즉시 중단·KST. 솔라피 stub.

## 리스크

- **솔라피 실응답 스펙 [INFERENCE]**: 문서 기준 구현 + stub 테스트. 라이브 발송 검증은 배포 후
  1건 실측 필요(기존 포트원 웹훅 data 필드 전례와 동일 패턴).
- **규모**: 신규 모델 1·서비스 다수·잡 4종·UI 3표면 — Developer 2회 순차 위임으로 분산,
  리뷰·테스트 게이트는 전체 대상 1사이클.
- **기존 테스트 회귀**: viewer 시스템 테스트(수신거부 링크 추가)·invoice 전이 테스트(overdue 저장화)
  — Tester가 회귀 포함 실행.
- **발송 창 이연 임계**: D-1 스텝의 "다음 평일 이연"이 D+1 스텝과 충돌하지 않는지(스텝별 1회
  멱등으로 흡수) — 서비스 산정 로직에서 명시 처리.
- U1 phone 미등록: noti_* 발송 skipped 기록(에러 아님).

## 진행 (Full: Phase 0→1→✋→2→3-a→3-b→4→5→6?→7→8→9)

완료 후 AGENTS.md "구현 진행 상황" 갱신, progress 리셋. 커밋·배포는 사용자 요청 시 badeuldon-git-deploy.

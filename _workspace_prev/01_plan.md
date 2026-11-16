# 01_plan — F-LEGAL/REF/TAX (2026-11-11, §6.14 병렬 판정 · 절약 모드)

## §6.14 병렬 판정 — 외부 의존 확인 결과

| 기능 | 구현 가능성 | 판정 |
|---|---|---|
| **LEGAL-1/2/3/4** 내용증명 양식(PDF)+건당 5,000원 과금 | ✓ 자체 구현 가능 — 과금은 기존 포트원 단건 플로우(수금 패스 Order 선례) 재사용 | **병렬 태스크 1** |
| **REF-1/2/3/4** 추심 상담 소개 화면 | ✓ 소개 화면·버튼·P5 고지 — 제휴사 데이터는 미계약 상태(안내 화면 한정) | **병렬 태스크 2** |
| **TAX-1/2** 전자세금계산서 | ✗ **제휴 전자세금계산서 사업자(API) 계약이 선행** — 외부 계약 없이 구현 불가(팝빌 등 계약 후 별도 런) | **런 제외** |

→ **2태스크 병렬 유리** (legal 도메인 vs ref 도메인 — 파일 소유권 분리·의존 없음·공유 파일 3-S 결선) + **TAX 별도 런 분리(계약 후)**. ADMIN-10 콘텐츠 메뉴는 Run C+LP-11에서 이미 완성.

## T-F1 · LEGAL 내용증명 양식 + 건당 과금 (LEGAL-1/2/3/4)

- **대상**: 만기 D+30 초과 청구(paid/voided 제외 — 미수 상태만이 내용증명 대상·리스크: paid·voided도 발급 가능하게 하면 근거 훼손 — 권고: unsettled 한정)
- **양식 PDF**(LEGAL-1): 청구 내역(품목·금액)·**발송 이력(REM-6 — message_logs)**·약속 이력(promise 파생 — Q14 판정)·부분입금 내역이 자동 반영된 내용증명 양식 PDF — **Prawn+Pretendard TTF 재사용**(Q17 패턴·한글 렌더 실측 완료)
- **LEGAL-3 고지 필수**: "본 서비스는 법률 자문을 제공하지 않습니다..." — 양식·생성 화면 양쪽(법률 검토 완료 전제 — Q5)
- **LEGAL-4**: 발송 대행 없음 — 화면에 "우체국 등기 등 직접 발송" 안내
- **과금(LEGAL-2·Q5 건당 5,000원)**: 기존 포트원 단건 결제 플로우 재사용 — Order 재사용(수금 패스 선례 — item 타입 구분 컬럼 추가 마이그레이션 1건·T-F1 소유)·**결제 완료(콜백) 후에만 PDF 다운로드 활성화**·미결제 시 양식 미리보기만(워터마크)
- 소유 파일: 마이그레이션 1건(orders item_type 또는 legal_orders 별도 — 당신 설계·권고: 기존 orders 재사용)·`legal_document.rb`?(문서 기록 불요 — PDF는 즉시 생성·주문 기록만)·`app/services/legal_documents/`·`app/controllers/admin/legal_documents_controller.rb`(관리 조회)·`app/controllers/app/legal_documents_controller.rb`·`app/views/app/legal_documents/**`·invoices show에 D+30 배너(조건부)·routes는 3-S·테스트

## T-F2 · REF 추심 상담 소개 (REF-1/2/3/4)

- **대상**: 만기 D+30 초과 청구(미수)
- **소개 화면**: "전문 추심 상담 연결" 안내 — ① 서비스 역할 고지(P5 — "채권 수임·중개를 수행하지 않습니다"·의뢰·계약은 U1과 제휴사 사이 — REF-2) ② 전달 자료 범위 고지(REF-3 — U1 명시적 동의 항목 한정) ③ 레퍼럴 무료 여부 표시(REF-4 — 제휴 계약에 따름) ④ **제휴사 미계약 상태 안내**("제휴 상담사 연결은 준비 중입니다" — 계약 후 데이터 반영)
- **버튼**: 청구서 상세(D+30 도달 건)에 "전문 추심 상담 연결" 안내 버튼 — 클릭 시 소개 화면
- 소유 파일: `app/controllers/app/referrals_controller.rb`(신규)·`app/views/app/referrals/**`(신규)·invoices show 배너(조건부)·해당 테스트
- 판정: ✓ 3조건(마이그레이션 불요·T-F1과 파일 분리)

## TAX-1/2 — 런 제외 (확정 제안)

제휴 전자세금계산서 사업자(팝빌 등) API 계약이 선행 — 계약 없이 구현 불가(외부 API 스펙·인증·수수료 전부 계약 의존). PRD에 "계약 후 별도 런" 명시는 기존 갱신 문구로 유지.

## 공유 파일·결선 (3-S)

- `config/routes.rb`: legal_documents(resources — index·new·create·show·payment 관련)·referrals(resource or resources)
- `app/helpers/app/base_helper.rb` 또는 사이드바: "내용증명·추심" 메뉴(또는 청구서 상세 진입만 — 당신 설계)
- 마이그레이션: T-F1 orders 재사용 시 item_type 컬럼 추가 1건(단일 마이그레이션 원칙 — 3-S 일괄)
- 스모크: 비인증 302·LEGAL 과금 플로우 stub 경유 200/303·REF 화면 200

## 리스크·모호점 (게이트 확정 대상)

1. **LEGAL 과금 결제 플로우**: 수금 패스 구매 플로우(orders callback·포트원 위젯) 재사용 설계 — item_type 구분 없이는 기존 주문과 혼동. 권고: orders.item_type 컬럼 추가(pass:0/legal_doc:1)
2. **REF 제휴사 미확정** — 소개 화면이 "빈 껍데기"가 되는 리스크: P5 고지·자료 범위·준비 중 안내를 명확히 하여 법적 리스크 관리 화면으로 정의(REF-2/3 준수 자체가 목적)
3. **D+30 경계**: "초과" = today > due_on + 30 — 경계일 계산 travel_to 테스트
4. **PAY-6 PDF와 기술 공유**: ReceiptPdfService 패턴 재사용(Prawn+TTF) — 파일 분리(legal_documents 전용 서비스)
5. **과금 미연동 fallback**: 결제 플로우 결선 실패 시 무료 제공은 LEGAL-2 위반 — 결제 미완료 시 다운로드 차단이 정답(권고)

## 관련 Rule ID

LEGAL-1~4(결정 기록 Q5)·REF-1~4·P5(규제 경계 — 화면 고지 자체가 목적)·PLAN-5(포트원 단건 재사용)·INV-4(unsettled 판정)·REM-6(발송 이력 인용)·TIME-1

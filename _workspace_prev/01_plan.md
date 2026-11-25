# 01_plan — 세금계산서 발급 자격 차단·운영 준비 게이트 (2026-11-24, 일반 모드·Full)

## 배경·목표

**A. 간이과세·면세사업자 발행 차단(영구 — 사용자 확정 2026-11-24)**: 발행 설정의 과세 유형에서
"간이과세"·"면세사업자"를 고를 수 있고, 고르면 `TaxInvoices::IssueService::TAX_TYPE_BY_USER`가
간이과세→영세(2)·면세→면세(3)로 매핑해 세금계산서가 발급된다. 세법상 간이과세자·면세사업자는
세금계산서를 발급하지 않는다(시행령 §70 — 검색 자료 기준). 발급을 막고 안내한다.

- 법적 예외(미지원 — 안내로 고지): 부가가치세법 §64의2 — 직전 연도 공급대가가 일정 금액 이상이고
  영수증 발급 의무가 있는 간이과세자는 세금계산서 발급 의무가 있다(10% 과세). 기준 금액은 자료마다
  달라(안내 기준 4,800만원) 이 작업에서 지원하지 않는다. 해당 사용자는 홈택스 등에서 발행한다.
- 과세 유형 **선택지 자체는 유지**한다 — 바로빌 회원 등록(RegistCorp)에 쓰는 사업자 정보라 실제
  유형을 선택할 수 있어야 한다. 차단 대상은 "발행"뿐이다.

**B. 운영 준비 게이트(임시 스위치 — 포함 여부는 승인 질의에서 확정)**: 바로빌은 선불 포인트
방식인데 운영 포인트가 미충전이라, 지금 발행 설정을 마친 사용자가 300원을 결제하면 결제만 되고
발행이 실패한다(환불 수동). 외부 유입 전에 바로빌 운영 준비(계약·충전·법인 등록)가 끝나지 않으면
발행 기능 전체를 잠가야 한다. 기본값은 꺼짐(fail-closed)이고, 바로빌 운영 준비 완료 뒤 켠다.

## 규모·파이프라인

- **Full** — 0→1→✋→2→3→4→5→6?→7→8→9. 새 비즈니스 규칙(TAX-3·TAX-4)과 전역 설정이
  들어가고 변경 파일이 3개를 넘는다.
- 호출 프로필(일반): `badeuldon-developer` → `badeuldon-reviewer` → `badeuldon-tester`.
  reviewer는 2026-11-23 GLM-5.4로 올린 뒤 첫 실제 스폰 — 위임 실측 필수.

## 관련 Rule ID

| Rule ID | 내용 | 이번 작업 |
|:---|:---|:---|
| TAX-1 | 전자세금계산서 발행(바로빌·건당 300원·인증서 등록 전제) | 기존 — 가드 추가의 기준 |
| TAX-2 | 발행 결과(승인번호) 기록·조조회 | 기존 — 변경 없음 |
| **TAX-3(신설)** | 발급 자격 — 과세 유형이 간이과세·면세사업자면 발행 불가(안내) | A |
| **TAX-4(신설)** | 운영 준비 게이트 — 발행 기능 전역 활성 스위치(기본 꺼짐) | B |
| P5 | 규제 경계 내 | 세무 증빙 오발급 방지 관점 |
| LP-12 | 문구 원칙 | 신규 안내 문구(Reviewer 집중 검증) |

결정 기록: **Q25**(간이과세·면세사업자 발행 차단 — 영구), **Q26**(운영 준비 게이트 — B 채택 시).

## 설계 확정 사항 (Developer 지시 기준)

### A. 발급 자격

1. **판정 단일 출처** — `User`에 과세 유형 자격 판정을 둔다(`tax_type == :general`만 발급 가능,
   네이밍은 규약 §5). 이유 문구는 헬퍼/상수 한 곳에서 공급해 패널·컨트롤러·설정 화면이 같은
   문구를 쓴다.
2. **차단 지점 4곳(이중화)** — 아래 전부. 어느 하나만 막으면 우회 경로가 남는다.
   - `App::InvoicesController#set_tax_invoice_context` — 새 패널 상태 `:tax_type_ineligible`.
     우선순위: 기존 발행 기록(있으면 그대로 표시) > 자격 없음 > settings_missing > client_missing >
     paid_pending > ready.
   - `App::TaxInvoicesController#issue_guard_message` — new·create 진입 차단(안내 문구).
   - `TaxInvoices::CreateOrderService` — **결제 전** 차단. 부적격이면 주문을 만들지 않는다
     (300원 결제가 일어나지 않게 하는 핵심 지점).
   - `TaxInvoices::IssueService#verify_guards!` — 결제 완료 뒤 경로(FulfillTaxInvoiceService)의
     최종 방어선. 가드 순서 맨 앞.
3. **화면**
   - 청구서 상세 패널(`_tax_invoice_panel`): `:tax_type_ineligible` 분기 추가 — 발급 불가 안내,
     버튼 없음(기존 `client_missing` 분기의 톤·여백 동일).
   - 발행 설정(`tax_invoice_settings/show`): 과세 유형 선택 아래 안내. 간이과세·면세사업자면
     "세금계산서를 발급할 수 없습니다" + 대안(계산서·영수증) + 간이과세만 예외 고지. 저장은 허용.
   - 인증서 등록 완료 안내(`confirm_certificate`의 "이제 전자세금계산서를 발행할 수 있습니다")는
     부적격 사용자에겐 사실이 아니므로 조건부로 바꾼다.
4. **안내 문구 초안**(LP-12 — Reviewer 검증 대상)
   - 간이과세: "간이과세자는 전자세금계산서를 발급할 수 없습니다. 거래처에는 계산서나 영수증을
     발급해 주세요. 매출 규모에 따라 예외가 적용될 수 있으니 세무사에게 확인해 주세요."
   - 면세사업자: "면세사업자는 전자세금계산서를 발급할 수 없습니다. 거래처에는 계산서나 영수증을
     발급해 주세요."
   - 기존 "세무 자문 아님" 고지(TAX-1 ⑥)는 그대로.
5. **유지되는 것** — 과세 유형 선택지·사업자 정보 저장·바로빌 회원 등록·기존 발행 내역 조회·취소.
   취소 후 재발행 버튼은 부적격 사용자에겐 비활성.

### B. 운영 준비 게이트 (채택 시)

1. **스위치** — 환경 변수 `TAX_INVOICE_ENABLED`. 접근자는 한 곳(`TaxInvoice.feature_enabled?`
   등 — 모델이 ENV를 직접 읽지 않게 초기화나 config 경로로 감싼다). 기본값 **false**.
   켜기 = `config/deploy.yml`의 env에 `"true"` 지정 → 커밋·배포(변경 이력이 남는 방식).
2. **꺼졌을 때**
   - 사이드바 "전자세금계산서" 메뉴 비노출(`App::BaseHelper` 내비 항목).
   - 청구서 상세 패널: 새 상태 `:feature_disabled` — "전자세금계산서 발행은 현재 준비 중입니다."
     (기존 발행 기록이 있는 청구는 그대로 표시).
   - `tax_invoices`의 new·create, `tax_invoice_setting`의 전 액션 → 직접 URL 접속 시 대시보드로
     리다이렉트 + 같은 안내.
   - **허용 유지**: 기존 주문 `show`와 `cancel` — 이미 결제·발행한 사용자의 상태 조회·취소 경로는
     끊지 않는다.
3. **테스트 환경** — 기본값 false면 기존 세금계산서 테스트(11파일 약 81건)가 깨진다. 테스트 전역
   헬퍼로 명시적으로 켜고(기본 켜짐), 끈 상태 테스트는 개별 케이스로 둔다.

### 랜딩

변경 없음. `_all_features` 카드·FAQ는 "런칭 시점엔 스위치 켜짐"이 전제다(리스크 3).

## 변경 예상 파일

| 영역 | 파일 | 내용 |
|:---|:---|:---|
| Model | `app/models/user.rb` | 과세 유형 자격 판정·이유 문구 |
| Model/Config | `app/models/tax_invoice.rb` (+ 필요 시 initializer) | B: 기능 활성 접근자 |
| Service | `app/services/tax_invoices/create_order_service.rb` | 결제 전 차단 |
| Service | `app/services/tax_invoices/issue_service.rb` | `verify_guards!` 자격 가드 |
| Controller | `app/controllers/app/invoices_controller.rb` | 패널 상태 2종 추가 |
| Controller | `app/controllers/app/tax_invoices_controller.rb` | 가드 문구·B: 진입 차단 |
| Controller | `app/controllers/app/tax_invoice_settings_controller.rb` | 완료 안내 조건화·B: 진입 차단 |
| View | `app/views/app/invoices/_tax_invoice_panel.html.erb` | 분기 2종 추가 |
| View | `app/views/app/tax_invoice_settings/show.html.erb` | 과세 유형 안내 |
| Helper | `app/helpers/app/base_helper.rb` | B: 메뉴 조건부 |
| Deploy | `config/deploy.yml` | B: env 항목(주석 포함) |
| Test | 위 대응 테스트 + `test/test_helper.rb`(헬퍼) | Tester |
| Docs | `PRD.md`·`AGENTS.md` | Phase 2·9 (오케스트레이터) |

마이그레이션 없음. 라우트 변경 없음.

## 에이전트 지시 요약

- **Developer**: 위 설계 기준 구현. 레이어 순서 — Model/Config → Service → Controller → View →
  Helper → Deploy 설정. `_workspace/03_implementation.md`에 파일 목록·Rule ID별 매핑 기록.
  **소유권 제한**: 걸려 있는 미커밋 3파일(`Gemfile.lock`·`test/application_system_test_case.rb`·
  `test/test_helpers/capybara_chrome_compat.rb`)은 건드리지 않는다.
- **Reviewer**: TAX-1·TAX-3·TAX-4·P5·LP-12. 우선 검증 — ① 우회 경로 없음(4지점 전부) ② 결제가
  일어나지 않음 ③ 신규 안내 문구의 정확성(예외 고지 포함) ④ B 채택 시 show·cancel이 끊기지
  않는지 ⑤ fail-closed 기본값 ⑥ UI 품질 기준(상태색·터치 타깃·여백 리듬).
- **Tester**: TAX-3 정상(일반과세 허용)·경계(선택지 저장은 허용·발행만 차단)·예외(간이과세·
  면세: 주문 미생성·가드 문구·패널 분기·서비스 가드). TAX-4 꺼짐(메뉴·패널·직접 URL 차단,
  기존 주문 show·cancel 허용)·켜짐(기존 동작). 기존 세금계산서 테스트 전수 회귀.

## 리스크·모호점

1. **스위치 기본값 false** — B 채택 시 배포 즉시 운영에서 세금계산서 기능 전체가 사라진다(의도된
   동작). 켜는 조건은 "바로빌 운영 준비 완료(계약·포인트 충전·법인 등록 스모크)".
2. **법적 근거의 확인 수준** — 법령 원문은 직접 대조하지 못했고 검색 자료들의 설명이 일치한다.
   예외(§64의2)는 지원하지 않으며 안내로 고지한다. 세무 확인은 사용자 몫.
3. **랜딩 불일치** — 스위치가 꺼진 채로 외부에 공개되면 랜딩의 세금계산서 카드·FAQ와 어긋난다.
   랜딩은 스위치와 연동하지 않는다(런칭 전 켜기 전제).
4. **켜짐 + 포인트 미충전** — 스위치만 켜고 바로빌 준비를 건너뛰면 결제만 되고 발행이 실패한다.
5. **기존 테스트 영향(B)** — 기본값 변경으로 약 81건이 영향권. 테스트 헬퍼로 보호한다.
6. **미커밋 3파일과 공존** — 이번 작업 파일과 겹치지 않는다. 마지막 커밋 시 분리한다.

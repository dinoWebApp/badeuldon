# 03_implementation — T-F2 REF 추심 상담 소개 화면 (2026-11-11, 절약 모드)

## 변경 파일 목록

| 파일 | 구분 | 내용 |
|---|---|---|
| `app/controllers/app/referrals_controller.rb` | 신규 | `App::ReferralsController` — index 1액션(본문 5줄). `Current.user.invoices.unsettled.where(due_on: ...Date.current - 30)` 로 D+30 도달 목록 적재. 소유권 격리(Current.user 스코프) |
| `app/views/app/referrals/index.html.erb` | 신규 | 통합 화면 — ①헤더 ②P5 고지 ③자료 범위 고지 ④레퍼럴 고지 ⑤D+30 목록(청구번호·거래처·금액·경과일) ⑥준비 중 안내 |
| `app/views/app/invoices/_referral_banner.html.erb` | 신규 | D+30 도달·미수 청구 상세 상단 배너 → referrals index 링크 |
| `app/controllers/app/invoices_controller.rb` | 수정 | `before_action :set_referral_banner, only: :show` + private 판정 메서드 8줄(주석 포함) |
| `app/views/app/invoices/show.html.erb` | 수정 | `<%= render "referral_banner" if @referral_banner %>` 1줄(+주석 2줄) |
| `test/controllers/app/referrals_controller_test.rb` | 신규 | 6테스트 — routes 미결선이라 결선 감지 시 자동 활성화, 그 전 skip(스위트 녹색 유지) |

## P5 고지 문구 전문 (검토용 — REF-2 원문 준용)

- 서비스 역할 고지(②): **"받을돈은 채권 수임·중개 행위를 수행하지 않습니다. 의뢰·계약은 회원님과 제휴 상담사 사이에서 성립합니다."**
- 전달 자료 범위(③ REF-3): **"위탁 시 전달되는 자료는 청구 내역·발송·약속 이력 등 회원님이 동의한 항목으로 한정됩니다. 동의하지 않은 정보는 외부에 전달되지 않습니다."**
- 레퍼럴 고지(④ REF-4): **"수수료·의뢰 조건은 제휴사와의 계약에 따릅니다."**
- 준비 중 안내(⑥): **"제휴 상담사 연결은 준비 중입니다. 계약 완료 후 이 화면에서 연결됩니다."**
- 배너(REF-1): "장기 미수금 안내 — 만기일이 30일 이상 지났습니다. 전문 추심 상담 안내를 확인할 수 있습니다." (과장·홍보 문구 없음)

## D+30 판정 정의

- **판정식**: `Invoice.unsettled` && `due_on + 30 < Date.current` — 경계일(due+30 == today)·29일 이하는 미포함, 31일 경과부터 포함(지시서 판정식 그대로).
- 목록 컨트롤러와 배너 컨트롤러(`set_referral_banner`)가 동일 판정식 공유 — 모집합 일치 보장.
- 컨트롤러에서만 판정하며 뷰는 @변수만 소비(뷰 쿼리 금지). `Date.current`(KST·TIME-1).

## routes 인계 (3-S)

```ruby
resources :referrals, only: :index   # app 스코프 내 — 헬퍼 app_referrals_path
```
- 컨트롤러·테스트는 `get "/app/referrals"` 경로 기준 작성 — 결선 즉시 테스트 자동 활성화.
- 뷰 내 링크 2곳(목록 복귀·배너)은 임시 하드코딩 + `3-S 결선 후 app_referrals_path 헬퍼로 교체` 주석 인계.
- 제휴사 계약 후: ⑥ 섹션 위치에 제휴사 레코드(모델) 반영 — 뷰에 데이터 반영 구조 주석 명시.

## 자기 스코프 검증 결과

1. **D+30 판정(test env runner, 임시 레코드 생성 후 전량 파기)**:
   - 31일 경과 포함: true / 30일 경과(경계일) 제외: true / 29일 경과 제외: true / paid·voided 제외: true — 5/5 통과
2. **스코프 격리**: 모든 조회가 `Current.user.invoices`(delta 소유) 기준 — gamma는 청구 0건이므로 목록 비어야 함(테스트 검증 — 결선 후 활성화)
3. **테스트**: `bin/rails test test/controllers/app/referrals_controller_test.rb` → 6 runs, 0 failures, 5 skips(routes 미결선 skip — 결선 후 자동 활성화), `test/controllers/app/invoices_controller_test.rb` → 37 runs 0 failures(배너 1줄 추가 회귀 없음)
4. `bin/rubocop` 소유 파일 4종 0 offense / `bin/rails zeitwerk:check` 통과
5. **금지 항목 준수**: routes·LEGAL(T-F1)·models·마이그레이션·문서 미수정, 임시 레코드 정리 완료(cleanup_done: true)

## Rule ID 매핑

| Rule ID | 구현 |
|---|---|
| REF-1 | D+30 도달·미수 배너 → 소개 화면 + 화면 내 대상 청구 목록 |
| REF-2 | P5 고지 박스(수임·중개 비수행·의뢰 계약은 U1과 제휴사 사이) |
| REF-3 | 전달 자료 범위 고지(동의 항목 한정·미동의 외부 전달 없음) |
| REF-4 | 수수료·의뢰 조건은 제휴 계약에 따름 고지 |
| P5 | 소개 화면 한정 — 데이터 전송 경로 없음(코드 실측: 외부 API 호출 0) |
| TIME-1 | `Date.current` KST 날짜 판정 |

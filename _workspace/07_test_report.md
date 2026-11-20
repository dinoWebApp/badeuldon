# 07_test_report — LP-16 랜딩 재구성 Phase 7 (2026-11-20 · 일반 모드)

대상: `test/controllers/landing_controller_test.rb`(기존 갱신 3건 + 신규 10건) · `test/controllers/pages_policy_test.rb`(T1 법무 검토 정합 갱신). 근거: `_workspace/05_review.md`(APPROVED·Tester 지시 A·B) · `_workspace/03_implementation.md`(§6 인계 3건) · PRD LP-16·LP-12·SURF-4.

## 최종 결과

| 게이트 | 결과 |
|---|---|
| `bin/rails test test/controllers/landing_controller_test.rb` | **41 runs, 561 assertions, 0 failures, 0 errors** (갱신 전 31 runs, 3 failures → 전부 예측된 단정 갱신 대상) |
| `bin/rails test test/controllers/pages_policy_test.rb` | **6 runs, 86 assertions, 0 failures, 0 errors** (T1 갱신 — 5→6 runs) |
| `bin/rails test` 전체 회귀 | **1,477 runs, 9,287 assertions, 0 failures, 0 errors, 0 skips** |
| `bin/rubocop` | 412 files inspected, **no offenses** |
| 코드 버그 | **0건** — 실패 3건 전부 테스트 오류(기존 단정 미갱신)로 분류, 소스 수정 0건 |

## 1. 기존 갱신 3건 (03 문서 §6 인계 = 05_review §A)

| # | 테스트(갱신 후 이름) | 갱신 내용 | 원인 분류 |
|---|---|---|---|
| 1 | `주 CTA는 히어로·all_features·sales_program·LP-10 최종에서 가입 화면 실링크다 (SURF-4, AUTH-1 반전, LP-16)` | `new_registration_path` 링크 `count: 2 → 4`, 문구 단정 `/무료로 시작하기/` `count: 2 → 4` — all_features 끝 "이 모든 기능, 무료로 시작하기"·sales_program 끝 CTA 반영(LP-16 "CTA 반복 배치") | 테스트 오류(단정 미갱신) |
| 2 | `표면 ①의 a 요소는 가입 CTA·헤더 로그인·법적 고지·인페이지 앵커만 사용한다 (SURF-4 개정 — LP-16 앵커 허용)` | 허용 href 조건에 **인페이지 앵커(`#` 접두 — ② 진입 아님)** 추가 + `a[href^='#'] count: 1`(#all-features 단일) 단정. 가입·로그인·법적 고지 3종·블로그·root·비밀번호 재설정 count 0 기존 단정 유지 | 테스트 오류(화이트리스트 미갱신) |
| 3 | `LP-8 FAQ 12항목의 질문이 모두 노출된다 (LP-8, LP-16 확대)` | `summary` `count: 8 → 12` + 신규 4질문(전자세금계산서·정기 청구·추천 코드·휴대폰 인증) 단정 추가. 기존 8질문 목록 유지 | 테스트 오류(단정 미갱신) |

## 2. 신규 10건 (05_review §B 반영 — LP-16 매핑)

| # | 테스트 | 검증 내용 | Rule ID |
|---|---|---|---|
| 1 | LP-16 재구성 13섹션이 지정 순서로 렌더된다 | hero→pain→how_it_works→features→**all_features**→scenarios→message_samples→control→**sales_program**→positioning→pricing→faq→closing — 섹션별 고유 마커 `body.index` 순서 비교, closing은 문구 공유로 `rindex` 판정 | LP-16·DESIGN-8 |
| 2 | all_features 12카드가 전 기능 커버 그리드를 구성한다 | `section#all-features ul li` count 12 + 12카드 h3 제목 전수 단정 | LP-16 |
| 3 | 배지는 신규 2종·예정 1종만 표기된다 | `신규` span count 2(반복 청구·전자세금계산서)·`예정` span count 1(데이터 내보내기=SEC-4 미구현) + 카드별 배지 소속 검증(h3 인접 span) | LP-16·LP-12 |
| 4 | "더 많은 기능 보기" 앵커가 all_features 섹션에 착지한다 | `a[href="#all-features"]` count 1 + `section#all-features` count 1 — 끊어진 앵커 방지 | LP-16·SURF-4 |
| 5 | sales_program 수치는 SALES 확정 조건 스냅샷과 일치한다 | "Plus 첫 결제 20% 할인(첫 달 7,920원)"·"영업 파트너는 20%(12개월), 지인 추천은 15%(무기한)"·"매주 월요일 자동으로 새 코드로 갱신"·"원천징수(3.3%)" — 수치 변경 시 테스트가 알림 | SALES-1/2/4/5·LP-12 |
| 6 | sales_program 섹션의 링크는 가입 CTA 1개뿐이다 | 섹션 내 `a` 요소 1개 = `new_registration_path` — 외부 href·mailto 0건(참여 문의는 텍스트 안내) | SURF-4 |
| 7 | hero 수치 배지 3종이 PRD 확정치로 렌더된다 | "첫 14일 무료 체험"(PLAN-2)·"청구 건당 최대 5통"(PLAN-3)·"4단계 정중한 안내"(REM-2) — 히어로 섹션 내 span 단정 | LP-16·LP-12 |
| 8 | 신규 섹션 2종은 h2 헤딩을 갖고 h1 1개를 유지한다 | `h1` count 1 + all_features h2 "받을돈이 하는 일, 한눈에"(W-1 반영 문구) + sales_program h2 | LP-16·DESIGN-8 |
| 9 | FAQ 신규 4항목 답변이 확정 수치·조건과 함께 노출된다 | 세금계산서 "수금 마감(입금 완료) 한해·300원·승인번호·공동인증서"(TAX-1·Q21) / 반복 청구 "발행일(1~28일)·일시중지·재개"(INV-7) / 추천 "7,920원·정상가·매주 새로 발급"(SALES-4) / 휴대폰 인증 "알림톡(SMS 폴백)·5분"(AUTH-9) | LP-8·TAX-1·INV-7·SALES-4·AUTH-9 |
| 10 | LP-16 신규 섹션 문구도 과장·보장·근거 없는 수치가 없다 | `전부입니다` 부재(W-1 회귀 방지)·`19종` 부재(03 §4-3 미채택 수치)·`완벽`·`회수율`·`실패 없는` 부재 + 완화 헤드라인 "한눈에" 존재 | LP-12 |

## 3. T1 정책 문서 테스트 갱신 (법무 검토 7건 정합화 반영)

파일: `test/controllers/pages_policy_test.rb` — 기존 5테스트 문구 단정에 법무 검토 반영 문구 추가 + 개정일 통일 신규 1테스트(총 6 runs).

| 법무 검토 항목 | 문서 | 추가 단정 |
|---|---|---|
| 취소 과금 재고지 | 이용약관 제7조 | "결제 전 안내 및 발행 전 확인 화면에서 재고지" |
| 휴대폰 인증 가입 절차 | 이용약관 제4조 | "휴대폰 번호를 필수로 제출하며" |
| 인증서 직접 등록·미보관 | 이용약관 제5조 | "공동인증서는 대행사에 위탁 등록되며 회사가 보관하지 않습니다" |
| 중복 가입 방지 고지(목적) | 개인정보처리방침 제2조 | "휴대폰 인증을 통한 가입 본인 확인(중복 가입 방지 포함)" |
| 인증서 미보관(제4조) | 개인정보처리방침 제4조 | "회사는 이를 보관하지 않습니다" |
| 이용 완료 정의 | 환불 정책 | '"이용 완료"란' + "PDF 다운로드가 가능해진 시점" + "국세청 발행 접수가 완료된 시점" |
| 개정일 통일 | 3종 전체 | 신규 테스트 — 헤더·부칙·공고일자 2026-11-20 통일 + 구 문구 "2026년 10월 15일부터 시행합니다" 잔존 0 (제정일 이력 표기는 허용) |

## 4. 금지 표현 스캔 결과 (LP-12)

전체 페이지 대상 기존 단정 + 신규 10-# 테스트 이중 커버 — **검출 0건**:

- `100%`·`보장`·`마지막 알림` — 기존 LP-12 테스트 통과(신규 카드·sales_program 포함 전체 응답 대상)
- `추심` — 문맥 필터 테스트 통과(부정·의문 문맥만: VIEW-5 고지문·FAQ·positioning)
- 신규 확장 — `전부입니다`(W-1)·`19종`·`완벽`·`회수율`·`실패 없는` 부재 확인
- SALES 수치는 전부 PRD 확정치(SALES-1/2/4/5) — LP-12 "측정 근거 수반" 준수, 테스트가 수치 스냅샷 고정(#5)

## 5. 유의 사항

- 소스(app/) 수정 0건 — 3건 실패는 전부 기존 단정 미갱신(테스트 오류)으로, Phase 7 인계 목록(03 §6)과 1:1 일치해 **코드 버그 0건** 확정.
- `sections#all-features` 배지 검증은 `h3 + span` 인접 선택자로 배지 소속 카드까지 검증 — '예정' 배지가 SEC-4(미구현) 1건뿐임을 데이터 수준에서 고정.
- 전체 스위트 1,477 runs에는 병렬 배치 타 태스크(T1 정책 문서 소스·기술 부채 등) 반영분이 포함 — 타 태스크 테스트 수정은 하지 않았음.
- 시스템 테스트(05_review §C — 모바일 뷰포트 13섹션 스크롤·반응형)는 선택 항목으로 미작성 — 정적 마크업이며 컨트롤러 통합 테스트로 구조·문구·링크 무결성 전수 커버.

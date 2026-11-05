# 03_implementation — LP-14 보강 (Phase 3, 2026-11-02)

## 3 LP-14 보강

### 변경 파일
- `app/views/landing/_scenarios.html.erb` — 카드 2종 추가 + U1 알림 스트립 + 주석 갱신 (4종→6종)
- `test/controllers/landing_controller_test.rb` — 기존 LP-14 assertion 최소 수정(4개→6개 카드·신규 benefit 2건·스트립 assertion 추가)

### 요약
- 시나리오 배열에 ⑤ 발행 안내(SHARE-6·P2), ⑥ 마침 알림(PAY-4) 카드 추가 — 기존 카드와 동일 구조(배지/benefit/detail/미니 목업), 중립 버블 패턴 유지(#FEE500 미사용)
- 카드 그리드 아래 섹션 내부 마지막 요소로 U1 알림 스트립 추가 — border+bg-white 카드형, 기존 svg stroke 문법(벨 아이콘) 재사용, `div` 기반(ol li 미사용 — LP-3 카운트 테스트 충돌 회피)

### Rule ID 매핑
- LP-14: 시나리오 커버 4종→6종 + U1 알림 스트립(PRD v0.24 반영)
- SHARE-6·P2: 카드 ⑤(발행 시 명의 안내 선택, 내 번호 미노출)
- PAY-4: 카드 ⑥(마감 확인·감사 안내, 기본 켬·해제 가능)
- SHARE-4·PROMISE-4·PROMISE-7·NOTI-1: U1 알림 스트립
- LP-12: 과장·수치 인용 없음 — 기능 사실 서술만

### 추가한 문구 전문
- ⑤ badge "발행 안내" / benefit "청구서를 보내는 첫 안내도, 받을돈 명의로 대신합니다." / detail "발행할 때 직접 카톡으로 보내거나, 받을돈 명의의 안내로 보낼지 선택할 수 있습니다. 내 번호는 노출되지 않습니다." / 목업 "발행 직후": "청구서를 안내드립니다. 아래 버튼에서 내용을 확인하실 수 있습니다."
- ⑥ badge "마침 알림" / benefit "수금이 끝나면, 정중한 마무리 인사까지 대신합니다." / detail "마감 처리하면 거래처에게 확인·감사 안내가 발송됩니다. 기본으로 켜져 있고, 원하면 끌 수 있습니다." / 목업 "마감 처리 후": "입금이 확인되었습니다. 감사합니다."
- 스트립: "진행 상황도 알림으로 — 열람·약속·입금 회신이 접수되면 바로 알려드립니다."

### 테스트 수정 내역
- 테스트명 "4개 카드"→"6개 카드", 배지 배열에 "발행 안내·마침 알림" 추가, 신규 benefit 2건 assertion, `상황 미리보기` count 4→6, 스트립 문구 assertion 1건 추가

### 자체 검증
- `bin/rubocop -a`: no offenses (136 files)
- `bin/rails zeitwerk:check`: pass
- `bin/rails test test/controllers/landing_controller_test.rb`: 27 runs, 355 assertions, 0 failures, 0 errors

## 6 리뷰 반영 수정
- `app/views/landing/_scenarios.html.erb` 3행 U1 알림 스트립 주석에 PROMISE-7 추가(SHARE-4·PROMISE-4·PROMISE-7·NOTI-1) — 주석만 수정
- `test/controllers/landing_controller_test.rb` 244행 동일 주석에 PROMISE-7 추가 — 주석만 수정, assertion 변경 없음

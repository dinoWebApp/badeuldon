# FIX2 — I-1 수정 (픽스처 ERB 상수 → 지역 변수)

소유 파일: `test/fixtures/invoices.yml` (유일 변경)

## 변경 전
```erb
<%
  # ERB 상대 만료일 — 로드 시점 KST(Rails TZ) 기준으로 평가된다.
  # 여기서 정의해 두면 각 행에서 참조한다(날짜 폭탄 근본 해소 — T3).
  ACTIVE_TOKEN_EXPIRES_AT = 30.days.from_now.end_of_day
  EXPIRED_TOKEN_EXPIRES_AT = 10.days.ago.end_of_day
%>
...
token_expires_at: <%= ACTIVE_TOKEN_EXPIRES_AT %>
token_expires_at: <%= EXPIRED_TOKEN_EXPIRES_AT %>
```

## 변경 후
```erb
<%
  # ERB 상대 만료일 — 로드 시점 KST(Rails TZ) 기준으로 평가된다.
  # 여기서 정의해 두면 각 행에서 참조한다(날짜 폭탄 근본 해소 — T3).
  active_token_expires_at = 30.days.from_now.end_of_day
  expired_token_expires_at = 10.days.ago.end_of_day
%>
...
token_expires_at: <%= active_token_expires_at %>
token_expires_at: <%= expired_token_expires_at %>
```

- 교체 참조 7곳(active 6·expired 1). 값·의도 불변(30일 뒤/10일 전 end_of_day).
- 주석에는 대문자 표기가 없어 갱신 대상 없음.

## 검증
- `grep -rn "ACTIVE_TOKEN_EXPIRES_AT\|EXPIRED_TOKEN_EXPIRES_AT" test` → 0건 (exit 1)
- 전용 DB: `DATABASE_URL=sqlite3:tmp/parallel/FIX2/test.sqlite3`
- 대상 테스트(viewer_controller / app/invoices_controller / fixtures_no_future_date / models/invoice):
  `115 runs, 714 assertions, 0 failures, 0 errors, 0 skips`
- `grep -c "already initialized constant" /tmp/fix2_test.log` → **0**
- 픽스처 로드(ERB) 오류 없음 — 테스트 통과로 확인

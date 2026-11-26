require "test_helper"

# T1 정책 문서(2026-11-20 개정) 최소 검증 — 라우트 공개 접근·색인 정책(SURF-3)·핵심 문구.
# 가격 문언은 코드 상수(TaxInvoice::ISSUE_FEE=300·Order::LEGAL_DOC_PRICE=5_000·
# Sales 20%)와 PRD(Q21·Q5·Q24·AUTH-9·TAX-1) 대조 완료(05_review) — 여기서는 렌더
# 정합만 고정한다(전문 스냅샷 테스트는 불요 — 지시).
# 2026-11-20 법무 검토 7건 정합화 반영 — 취소 과금 재고지(제7조)·중복 가입 방지 고지(제1·2조)·
# 공동인증서 직접 등록·미보관(제4·5조)·부가서비스 "이용 완료" 정의(환불 정책)·개정일 통일(2026-11-20).
class PagesPolicyTest < ActionDispatch::IntegrationTest
  test "정책 문서 3종은 비로그인으로 접근 가능하고 제목을 렌더한다" do
    { terms_path => "이용약관", privacy_path => "개인정보처리방침",
      refund_path => "환불 정책" }.each do |path, title|
      get path
      assert_response :success, path
      assert_includes response.body, title
    end
  end

  test "정책 문서는 noindex 메타 없이 색인을 허용한다 (SURF-3 — 공개 법적 고지)" do
    [ terms_path, privacy_path, refund_path ].each do |path|
      get path
      assert_select "meta[name=robots]", count: 0, message: path
    end
  end

  test "이용약관에 건당 요금·할인·취소 과금·세무 고지·바로빌이 반영되었다 (TAX-1·Q21·LEGAL-2·Q24)" do
    get terms_path
    assert_includes response.body, "건당 300원"
    assert_includes response.body, "건당 5,000원"
    assert_includes response.body, "20% 할인이 적용"
    assert_includes response.body, "발행 취소 시에도 발행 처리 수수료는 환불되지 않습니다"
    assert_includes response.body, "발행 전 확인 미리보기"
    assert_includes response.body, "세무 자문 서비스가 아니며"
    assert_includes response.body, "바로빌"
    assert_includes response.body, "청구 건당 1회로 제한"
    assert_includes response.body, "사업자등록번호가 없는 개인인 경우 발행할 수 없습니다"
    # 법무 검토 7건 — 취소 과금의 결제 전·발행 전 이중 재고지 명시(제7조)
    assert_includes response.body, "결제 전 안내 및 발행 전 확인 화면에서 재고지"
    # 법무 검토 7건 — 휴대폰 인증 가입 절차(제4조)·공동인증서 위탁 등록·회사 미보관(제5조)
    assert_includes response.body, "휴대폰 번호를 필수로 제출하며"
    assert_includes response.body, "공동인증서는 대행사에 위탁 등록되며 회사가 보관하지 않습니다"
  end

  test "개인정보처리방침에 휴대폰 인증 수집·바로빌 제3자 제공·위탁이 반영되었다 (AUTH-9·TAX-1)" do
    get privacy_path
    assert_includes response.body, "휴대폰 번호(필수)"
    assert_includes response.body, "중복 가입 방지"
    assert_includes response.body, "5분 내 만료되는 1회용 코드"
    assert_includes response.body, "바로빌((주)케이넷)"
    assert_includes response.body, "공동인증서 파일은 회사 서버를 거치지 않고 바로빌에 직접 등록되며"
    assert_includes response.body, "가입 인증번호 발송 포함"
    assert_includes response.body, "전자세금계산서 발행 대행"
    # 법무 검토 7건 — 제2조 수집 목적 고지(중복 가입 방지 포함)·제4조 회사 미보관 명시
    assert_includes response.body, "휴대폰 인증을 통한 가입 본인 확인(중복 가입 방지 포함)"
    assert_includes response.body, "회사는 이를 보관하지 않습니다"
  end

  test "환불 정책에 부가서비스 환불 불가·취소 과금 안내가 반영되었다 (LEGAL-2·TAX-1)" do
    get refund_path
    assert_includes response.body, "환불이 불가"
    assert_includes response.body, "건당 5,000원"
    assert_includes response.body, "건당 300원"
    assert_includes response.body, "발행 취소 시에도 수수료가 과금"
    # 법무 검토 7건 — "이용 완료" 정의 명시(내용증명=PDF 생성 시점·세금계산서=국세청 접수 시점)
    assert_includes response.body, '"이용 완료"란'
    assert_includes response.body, "PDF 다운로드가 가능해진 시점"
    assert_includes response.body, "국세청 발행 접수가 완료된 시점"
  end

  test "정책 문서의 개정일 표기가 각 문서와 일치한다 (약관 2026-11-26·방침·환불 2026-11-20)" do
    {
      terms_path => [ "마지막 수정일: 2026년 11월 26일 · 공고·시행일: 2026년 11월 26일",
                      "2026년 11월 26일에 개정되어 공고·시행됩니다" ],
      privacy_path => [ "마지막 수정일: 2026년 11월 20일 · 시행일: 2026년 11월 20일",
                        "공고일자: 2026년 11월 20일" ],
      refund_path => [ "마지막 수정일: 2026년 11월 20일 · 공고·시행일: 2026년 11월 20일",
                       "2026년 11월 20일에 공고되어 같은 날부터 시행됩니다" ]
    }.each do |path, markers|
      get path
      markers.each { |marker| assert_includes response.body, marker, "#{path} — #{marker}" }
      # 구(舊) 시행일 단독 문구 잔존 없음 — 부칙 문구 교체 확인(제정일은 이력 표기로 허용)
      assert_no_match(/2026년 10월 15일부터 시행합니다/, response.body, path)
    end
  end

  test "이용약관 제11조에 회원 탈퇴 절차(미수 청구 링크 폐기·유료 구독 즉시 종료)가 명시되어 있다 (AUTH-1.5·Q29)" do
    get terms_path
    # ①항 — 미수 청구가 있어도 탈퇴 가능·해당 청구의 링크 폐기
    assert_includes response.body,
                    "미수 청구가 있는 경우에도 탈퇴할 수 있으며, 이 경우 해당 청구의 링크도 폐기됩니다"
    # ②항 — 즉시 종료·이후 결제 없음·제7조 ⑦(해지 시 잔여 기간 이용)과의 관계·제8조 ②③(청약철회·귀책 환불) 예외
    assert_includes response.body,
                    "회원 탈퇴 시 이용 중인 유료 구독은 즉시 종료되며 이후 결제는 청구되지 않습니다(구독만 해지하는 경우와 달리 제7조의 남은 기간 이용은 적용되지 않습니다)"
    assert_includes response.body,
                    "탈퇴 시점에 남은 이용 기간과 남은 이용권(수금 패스)은 환불되지 않습니다"
    assert_includes response.body,
                    "다만 제8조에 따른 청약철회와 회사의 귀책 사유에 의한 환불은 그러하지 아니합니다"
    # 부칙 — 2026-11-26 개정 이력 항목
    assert_includes response.body,
                    "2026년 11월 26일 개정 이력: 회원 탈퇴 절차 명시(제11조 — 설정 화면 탈퇴, 미수 청구 링크 폐기, 유료 구독 즉시 종료)"
    # 부칙 — 정식 오픈 전 당일 공고·시행과 이후 제14조 ② 준수 명시(N-5 — 당일 시행 표기 정합)
    assert_includes response.body,
                    "이 개정은 서비스 정식 오픈 전에 공고되어 같은 날 시행되며, 정식 오픈 이후의 약관 개정은 제14조 ②에 따라 공지합니다"
  end
end

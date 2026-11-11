require "test_helper"

module LegalDocuments
  class ContentProofPdfServiceTest < ActiveSupport::TestCase
    fixtures :invoices, :invoice_items

    # LEGAL-1 — D+30 초과·미수 청구(delta_overdue: due_on 2026-09-01)의 내용증명 양식 PDF 생성.
    # Prawn 스트림은 압축이라 문자열 검증은 pdftotext(로컬 poppler) 전문 추출로 수행한다.
    test "D+30 초과 미수 청구의 PDF를 생성한다 — %PDF 헤더·유효 크기" do
      pdf = ContentProofPdfService.call(invoice: invoices(:delta_overdue))

      assert_not_nil pdf
      assert pdf.start_with?("%PDF")
      assert pdf.bytesize > 10_000, "PDF 바이트가 비정상적으로 작습니다(#{pdf.bytesize})"
    end

    test "pdftotext 한글 전문 추출 — 청구 내역·발송 이력·약속·부분입금·고지문·직접 발송 안내 전부 포함" do
      invoice = invoices(:delta_overdue)
      MessageLog.create!(invoice_id: invoice.id, user_id: invoice.user_id, template_key: "overdue_d1",
                         phone: "01000000000", status: :sent, sent_at: Time.zone.parse("2026-09-02 10:00"))
      MessageLog.create!(invoice_id: invoice.id, user_id: invoice.user_id, template_key: "final_d14",
                         phone: "01000000000", status: :sent, sent_at: Time.zone.parse("2026-09-16 10:00"))
      # 과거 약속 기록은 접수 당시 유효했던 데이터 — 검증(오늘 이후) 우회해 직접 생성한다.
      Promise.new(invoice_id: invoice.id, kind: :date_selected,
                  promised_on: Date.new(2026, 9, 20)).save!(validate: false)
      invoice.payments.create!(amount: 20_000, paid_on: Date.new(2026, 9, 25))

      pdf = ContentProofPdfService.call(invoice: invoice)
      text = extract_text(pdf)

      [
        "내용증명",                              # ① 표제
        invoice.issue_number,                    # ③ 청구번호
        invoice.client.name,                     # ② 수신인(거래처명)
        invoice.issuer_display_name,             # ② 발신인(U1 표시명)
        "청구 내역",                             # ③ 청구 내역
        "공급가액", "부가세",                    # ③ 금액
        "발송 이력", "독촉 2차", "최종 안내",    # ④ 발송 이력(템플릿 라벨)
        "입금 약속 이력", "미이행 (약속일 2026-09-20)",             # ⑤ 약속(Q14 — 도과 전 약속은 판정 중… 도과 후라 "미이행")
        "입금 내역", "입금 합계",                # ⑥ 부분입금
        "법률 자문을 제공하지 않습니다",         # ⑦ LEGAL-3 고지문
        "직접 수행"                              # ⑧ LEGAL-4 직접 발송 안내
      ].each do |needle|
        assert_includes text, needle, "PDF 텍스트에 누락: #{needle}"
      end
    end

    test "Q14 판정 — 도과 전 약속은 판정 중으로 표기한다" do
      invoice = invoices(:delta_issued)  # due_on 2026-10-01

      travel_to Time.zone.local(2026, 11, 5) do  # D+30 초과 && 약속일(2026-11-20) 도과 전
        invoice.promises.create!(kind: :date_selected, promised_on: Date.new(2026, 11, 20))
        text = extract_text(ContentProofPdfService.call(invoice: invoice, today: Date.new(2026, 11, 5)))

        assert_includes text, "판정 중 (약속일 2026-11-20)"
      end
    end

    test "이력이 없는 청구도 렌더한다 — 빈 기록 안내 문구" do
      text = extract_text(ContentProofPdfService.call(invoice: invoices(:delta_overdue)))

      assert_includes text, "기록된 발송 이력이 없습니다"
      assert_includes text, "기록된 입금 약속이 없습니다"
      assert_includes text, "기록된 입금이 없습니다"
    end

    test "unsettled가 아닌 청구는 LegalDocNotAvailable — paid·voided·draft 전부 거부" do
      [ :delta_paid, :delta_voided, :delta_draft ].each do |fixture|
        error = assert_raises(ContentProofPdfService::LegalDocNotAvailable) do
          ContentProofPdfService.call(invoice: invoices(fixture))
        end
        assert_match(/미수금/, error.message)
      end
    end

    test "D+30 경계 — due_on+30일은 거부, +31일부터 허용(초과 한정)" do
      invoice = invoices(:delta_issued)  # due_on 2026-10-01

      travel_to Date.new(2026, 10, 31) do  # due_on + 30 == 오늘 — 아직 "초과" 아님
        assert_raises(ContentProofPdfService::LegalDocNotAvailable) do
          ContentProofPdfService.call(invoice: invoice)
        end
        assert_not ContentProofPdfService.legal_target?(invoice)
      end

      travel_to Date.new(2026, 11, 1) do  # due_on + 30 < 오늘
        assert ContentProofPdfService.legal_target?(invoice)
        assert_nothing_raised { ContentProofPdfService.call(invoice: invoice) }
      end
    end

    test "발송 이력 표기 상한 10건(최근순)" do
      invoice = invoices(:delta_overdue)
      12.times do |i|
        MessageLog.create!(invoice_id: invoice.id, user_id: invoice.user_id, template_key: "d7",
                           phone: "01000000000", status: :sent,
                           sent_at: Time.zone.local(2026, 10, 1) + i.days)
      end

      text = extract_text(ContentProofPdfService.call(invoice: invoice))
      # 10건만 표기 — 12건 전부가 아닌 최근 10건(2026-10-13까지)
      assert_includes text, "2026-10-12"
      assert_not_includes text, "2026-10-02"
    end

    private

    # pdftotext(로컬 poppler)로 한글 전문을 추출한다 — 한글 렌더 실측(Q17 계열 검증).
    def extract_text(pdf)
      dir = Dir.mktmpdir
      path = File.join(dir, "content_proof.pdf")
      File.binwrite(path, pdf)
      output = IO.popen([ "pdftotext", path, "-" ], &:read)
      assert $CHILD_STATUS.success?, "pdftotext 실행 실패"
      output
    ensure
      FileUtils.remove_entry(dir) if dir
    end
  end
end

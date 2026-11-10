# 관리자 2FA(TOTP) 지원 서비스(AUTH-7.1 · EXT-2 내부 구현).
# QR 프로비저닝 이미지(RQRCode → PNG data URI)와 코드 검증 위임을 제공한다.
# verify의 at 인자는 테스트 시계 조작 허용(02 확정 해석 5).
module Admins
  class TotpService
    # 등록 화면용 QR 이미지(data URI) — 최초 등록 1회만 노출(이후 재표시 금지).
    def self.qr_data_url(admin)
      qr = RQRCode::QRCode.new(admin.provisioning_uri)
      png = qr.as_png(size: 240, border_modules: 2)
      "data:image/png;base64,#{Base64.strict_encode64(png.to_s)}"
    end

    # 코드 검증 — Admin#verify_totp!가 ±1 스텝(drift 30초)·재사용 차단을 담당.
    def self.verify(admin, code, at: Time.current)
      admin.verify_totp!(code, at:)
    end
  end
end

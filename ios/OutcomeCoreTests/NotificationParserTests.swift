import XCTest
@testable import OutcomeCore

final class NotificationParserTests: XCTestCase {
    private var ts: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15, minute: 55))!
    }

    func testRealMBBankIncomingFormat() throws {
        let raw = RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: +500,000VND 20/11/26 15:45|SD: 12,500,000VND| ND: NGUYEN VAN A chuyen tien - Ma giao dich/ Trace 123456",
            receivedAt: ts
        )
        let parsed = try XCTUnwrap(NotificationParser.parse(raw))
        XCTAssertEqual(parsed.txType, .income)
        XCTAssertEqual(parsed.direction, .in)
        XCTAssertEqual(parsed.amount, 500_000)
        XCTAssertEqual(parsed.reportedBalanceAfter, 12_500_000)
        XCTAssertEqual(parsed.traceId, "123456")
        XCTAssertEqual(parsed.description, "NGUYEN VAN A chuyen tien")
        XCTAssertEqual(
            parsed.occurredAt,
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15, minute: 45))!
        )
    }

    func testRealMBBankOutgoingFormat() throws {
        let raw = RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000VND 20/11/26 15:50|SD: 12,350,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321",
            receivedAt: ts
        )
        let parsed = try XCTUnwrap(NotificationParser.parse(raw))
        XCTAssertEqual(parsed.txType, .expense)
        XCTAssertEqual(parsed.direction, .out)
        XCTAssertEqual(parsed.amount, 150_000)
        XCTAssertEqual(parsed.reportedBalanceAfter, 12_350_000)
        XCTAssertEqual(parsed.traceId, "654321")
        XCTAssertEqual(parsed.description, "Thanh toan don hang")
    }

    func testMBBankMoMoCashInInternalTransfer() throws {
        let raw = RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -500,000VND 20/11/26 16:00|SD: 11,850,000VND| ND: MOMO-CASHIN 0901234567 - Ma giao dich/ Trace 777888",
            receivedAt: ts
        )
        let parsed = try XCTUnwrap(NotificationParser.parse(raw))
        XCTAssertEqual(parsed.txType, .internalTransfer)
        XCTAssertEqual(parsed.sourceWalletId, .mbbank)
        XCTAssertEqual(parsed.targetWalletId, .momo)
        XCTAssertEqual(parsed.amount, 500_000)
        XCTAssertEqual(parsed.traceId, "777888")
    }

    func testMBBankMoMoCashOutInternalTransfer() throws {
        let raw = RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: +300,000VND 20/11/26 16:10|SD: 12,150,000VND| ND: MOMO-CASHOUT - Ma giao dich/ Trace 999000",
            receivedAt: ts
        )
        let parsed = try XCTUnwrap(NotificationParser.parse(raw))
        XCTAssertEqual(parsed.txType, .internalTransfer)
        XCTAssertEqual(parsed.sourceWalletId, .momo)
        XCTAssertEqual(parsed.targetWalletId, .mbbank)
        XCTAssertEqual(parsed.amount, 300_000)
        XCTAssertEqual(parsed.traceId, "999000")
    }

    func testMoMoReceiveMoneyWithoutPlusSign() throws {
        let raw = RawNotification(
            sourceApp: .momo,
            title: "Nhận tiền thành công",
            body: "Trần Minh Quân đã chuyển cho bạn 120.000đ. Lời nhắn: Tiền cafe sáng",
            receivedAt: ts
        )
        let parsed = try XCTUnwrap(NotificationParser.parse(raw))
        XCTAssertEqual(parsed.txType, .income)
        XCTAssertEqual(parsed.direction, .in)
        XCTAssertEqual(parsed.amount, 120_000)
        XCTAssertEqual(parsed.description, "Trần Minh Quân - Tiền cafe sáng")
    }

    func testMoMoAllRealPopupFormats() throws {
        let r1 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Bạn vừa nhận được tiền",
            body: "Bạn vừa nhận được 120.000đ từ Nguyễn Văn A (0901234567). Lời nhắn: \"Tiền ăn trưa\"",
            receivedAt: ts
        )))
        XCTAssertEqual(r1.txType, .income)
        XCTAssertEqual(r1.amount, 120_000)
        XCTAssertEqual(r1.description, "Nguyễn Văn A - Tiền ăn trưa")

        let r2 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Nhận tiền thành công",
            body: "Bạn vừa nhận được 500.000đ từ NGUYEN VAN B qua VietQR/Chuyển tiền nhanh.",
            receivedAt: ts
        )))
        XCTAssertEqual(r2.txType, .income)
        XCTAssertEqual(r2.amount, 500_000)
        XCTAssertEqual(r2.description, "NGUYEN VAN B")

        let r3 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Bạn đã thanh toán thành công 199.000đ cho dịch vụ Apple Services.",
            receivedAt: ts
        )))
        XCTAssertEqual(r3.txType, .expense)
        XCTAssertEqual(r3.direction, .out)
        XCTAssertEqual(r3.amount, 199_000)
        XCTAssertEqual(r3.description, "Apple Services")

        let r4 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "",
            body: "Bạn vừa được hoàn 50.000đ từ giao dịch Shopee vào Ví MoMo.",
            receivedAt: ts
        )))
        XCTAssertEqual(r4.txType, .income)
        XCTAssertEqual(r4.direction, .in)
        XCTAssertEqual(r4.amount, 50_000)
        XCTAssertEqual(r4.description, "Hoàn tiền - Shopee")

        // 5) Tiền lời Túi Thần Tài -> ignored (does not enter main Ví MoMo cash balance)
        let r5 = NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Tiền lời Túi Thần Tài",
            body: "Chúc mừng bạn nhận được 1.250đ tiền lời hôm nay từ Túi Thần Tài.",
            receivedAt: ts
        ))
        XCTAssertNil(r5)

        // 5b) Rút tiền từ Túi Thần Tài về Ví MoMo -> INCOME on Ví MoMo
        let r5b = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Túi Thần Tài",
            body: "Giao dịch rút 500.000đ từ Túi Thần Tài về Ví MoMo thành công.",
            receivedAt: ts
        )))
        XCTAssertEqual(r5b.txType, .income)
        XCTAssertEqual(r5b.direction, .in)
        XCTAssertEqual(r5b.amount, 500_000)
        XCTAssertEqual(r5b.description, "Rút Túi Thần Tài")

        // 5c) Tự động tích lũy vào Túi Thần Tài -> EXPENSE from Ví MoMo
        let r5c = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Túi Thần Tài",
            body: "[Túi Thần Tài] Hệ thống đã tự động tích lũy 300.000đ từ Ví MoMo của bạn.",
            receivedAt: ts
        )))
        XCTAssertEqual(r5c.txType, .expense)
        XCTAssertEqual(r5c.direction, .out)
        XCTAssertEqual(r5c.amount, 300_000)
        XCTAssertEqual(r5c.description, "Nạp Túi Thần Tài")

        let r6 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Chuyển tiền thành công",
            body: "Bạn đã chuyển 85.000đ cho Lê Minh Khôi (0912345678). Lời nhắn: \"Hoàn tiền cafe\"",
            receivedAt: ts
        )))
        XCTAssertEqual(r6.txType, .expense)
        XCTAssertEqual(r6.amount, 85_000)
        XCTAssertEqual(r6.description, "Chuyển Lê Minh Khôi")

        let r7 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Thanh toán thành công 45.000đ tại Highlands Coffee.",
            receivedAt: ts
        )))
        XCTAssertEqual(r7.txType, .expense)
        XCTAssertEqual(r7.amount, 45_000)
        XCTAssertEqual(r7.description, "Highlands Coffee")

        let r8 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Nạp tiền điện thoại thành công",
            body: "Bạn đã nạp tiền điện thoại 50.000đ cho thuê bao 0901234567.",
            receivedAt: ts
        )))
        XCTAssertEqual(r8.txType, .expense)
        XCTAssertEqual(r8.direction, .out)
        XCTAssertEqual(r8.amount, 50_000)

        let r9 = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Bạn vừa nhận được tiền",
            body: "Bạn vừa nhận được 70.000đ từ Phạm Anh (0988111222). Lời nhắn: \"Chia tiền voucher\"",
            receivedAt: ts
        )))
        XCTAssertEqual(r9.txType, .income)
        XCTAssertEqual(r9.amount, 70_000)
        XCTAssertEqual(r9.description, "Phạm Anh - Chia tiền voucher")
    }

    func testIgnoresPromotionalAndOTPNotifications() {
        let promo = RawNotification(
            sourceApp: .momo,
            title: "Ưu đãi cực sốc",
            body: "Nhận ngay voucher giảm giá 50.000đ khi mua trà sữa hôm nay!",
            receivedAt: ts
        )
        let giftCardPromo = RawNotification(
            sourceApp: .momo,
            title: "Quà tặng dành riêng cho bạn",
            body: "Chúc mừng bạn nhận được thẻ quà 50.000đ thanh toán hóa đơn!",
            receivedAt: ts
        )
        let otp = RawNotification(
            sourceApp: .mbbank,
            title: "Mã OTP",
            body: "Ma OTP cua quy khach la 482910. Khong chia se voi bat ky ai.",
            receivedAt: ts
        )
        XCTAssertNil(NotificationParser.parse(promo))
        XCTAssertNil(NotificationParser.parse(giftCardPromo))
        XCTAssertNil(NotificationParser.parse(otp))
    }

    func testHardenedBankAndMoMoEdgeCases() throws {
        // #1 Credit card statement, credit card spend, savings book -> ignored
        XCTAssertNil(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Thông báo sao kê",
            body: "Thong bao sao ke the tin dung thang 11/2026. Tong du no: VND 5,200,000. Vui long thanh toan truoc ngay 25-11-2026.",
            receivedAt: ts
        )))
        XCTAssertNil(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động thẻ",
            body: "The tin dung VISA 4084xxxxxx phat sinh giao dich chi tieu VND 1,500,000 tai THE COFFEE HOUSE. So du kha dung: VND 18,500,000.",
            receivedAt: ts
        )))
        XCTAssertNil(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Tiết kiệm số",
            body: "Quy khach da mo thanh cong So tiet kiem so 0123xxxxxx so tien 50,000,000 VND.",
            receivedAt: ts
        )))

        // #2 MoMo Ví Trả Sau reminder & postpaid payment -> ignored
        XCTAssertNil(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Nhắc thanh toán Ví Trả Sau",
            body: "Toàn bộ dư nợ Ví Trả Sau của bạn là 1.850.000đ. Vui lòng thanh toán trước ngày 05/12.",
            receivedAt: ts
        )))
        XCTAssertNil(NotificationParser.parse(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Thanh toán thành công 150.000đ cho Shopee bằng nguồn Ví Trả Sau.",
            receivedAt: ts
        )))

        // #4 MOMO_CASHIN variant
        let cashIn = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -200,000VND 21/11/26 10:00|SD: 5,000,000VND| ND: MOMO_CASHIN 0901234567",
            receivedAt: ts
        )))
        XCTAssertEqual(cashIn.txType, .internalTransfer)
        XCTAssertEqual(cashIn.amount, 200_000)

        // #5 & #6 Prefix VND + extended "So du kha dung:" stripping
        let feeTx = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Thông báo thu phí",
            body: "Giao dich tru phi thuong nien the 9704xxxxxx so tien VND 99,000. So du kha dung: VND 1,450,000.",
            receivedAt: ts
        )))
        XCTAssertEqual(feeTx.txType, .expense)
        XCTAssertEqual(feeTx.amount, 99_000)
        XCTAssertEqual(feeTx.reportedBalanceAfter, 1_450_000)

        // #8 Decimal .00 tail
        let decTx = try XCTUnwrap(NotificationParser.parse(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000.00VND 21/11/26 10:15|SD: 4,850,000.00VND| ND: Thanh toan",
            receivedAt: ts
        )))
        XCTAssertEqual(decTx.amount, 150_000)
        XCTAssertEqual(decTx.reportedBalanceAfter, 4_850_000)
    }
}

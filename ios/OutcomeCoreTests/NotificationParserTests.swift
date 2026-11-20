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

    func testIgnoresPromotionalAndOTPNotifications() {
        let promo = RawNotification(
            sourceApp: .momo,
            title: "Ưu đãi cực sốc",
            body: "Nhận ngay voucher giảm giá 50.000đ khi mua trà sữa hôm nay!",
            receivedAt: ts
        )
        let otp = RawNotification(
            sourceApp: .mbbank,
            title: "Mã OTP",
            body: "Ma OTP cua quy khach la 482910. Khong chia se voi bat ky ai.",
            receivedAt: ts
        )
        XCTAssertNil(NotificationParser.parse(promo))
        XCTAssertNil(NotificationParser.parse(otp))
    }
}

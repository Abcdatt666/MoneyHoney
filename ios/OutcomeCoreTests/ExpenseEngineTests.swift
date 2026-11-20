import XCTest
@testable import OutcomeCore

final class ExpenseEngineTests: XCTestCase {
    @MainActor
    func testTraceDeduplicationAndManualFlow() throws {
        let engine = ExpenseEngine()
        let baseDate = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15, minute: 50))!

        try engine.reconcileBalances([.mbbank: 5_000_000, .momo: 200_000], now: baseDate)

        let customTag = try engine.addCustomTag(name: "Thú cưng")
        XCTAssertThrowsError(try engine.addCustomTag(name: "  thú cưng "))

        let res1 = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000VND 20/11/26 15:50|SD: 4,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321",
            receivedAt: baseDate
        ))
        XCTAssertEqual(res1.status, .created)
        XCTAssertEqual(res1.prompt?.shouldPrompt, true)
        XCTAssertEqual(res1.prompt?.title, "MBBank -150.000đ")
        XCTAssertEqual(engine.listPendingTransactions().count, 1)

        let dup = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000VND 20/11/26 15:50|SD: 4,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321",
            receivedAt: baseDate.addingTimeInterval(120)
        ))
        XCTAssertEqual(dup.status, .duplicate)

        let tx1 = try XCTUnwrap(res1.transaction)
        try engine.confirmTransaction(txId: tx1.id, tagId: "tag_mua_sam", note: "Mua đồ Shopee")
        XCTAssertEqual(engine.listPendingTransactions().count, 0)

        let manual = try engine.addManualTransaction(
            walletId: .momo,
            direction: .out,
            amount: 90_000,
            tagId: customTag.id,
            description: "Pet Mart",
            note: "Mua cát mèo bằng ví MoMo",
            occurredAt: baseDate
        )
        XCTAssertEqual(manual.status, .confirmed)

        let summary = engine.getDashboardSummary(year: 2026, month: 11, now: baseDate)
        XCTAssertEqual(summary.mbbankBalance, 4_850_000)
        XCTAssertEqual(summary.momoBalance, 110_000)
        XCTAssertEqual(summary.totalBalance, 4_960_000)
        XCTAssertEqual(summary.monthlyExpense, 240_000)
        XCTAssertEqual(summary.expenseByTag["Mua sắm"], 150_000)
        XCTAssertEqual(summary.expenseByTag["Thú cưng"], 90_000)

        XCTAssertTrue(engine.deleteTransaction(txId: manual.id))
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 200_000)
    }

    @MainActor
    func testCrossAppDuplicateGuardOnInternalTransfer() throws {
        let engine = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 11, minute: 0))!
        try engine.reconcileBalances([.mbbank: 2_000_000, .momo: 100_000], now: t0)

        let rMb = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -500,000VND 20/11/26 11:00|SD: 1,500,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 333444",
            receivedAt: t0.addingTimeInterval(10)
        ))
        XCTAssertEqual(rMb.status, .created)
        XCTAssertEqual(rMb.prompt?.shouldPrompt, false)

        let rMomo = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "MoMo",
            body: "Nạp tiền vào ví +500.000đ từ MBBank",
            receivedAt: t0.addingTimeInterval(25)
        ))
        XCTAssertEqual(rMomo.status, .duplicate)
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 600_000)
        XCTAssertEqual(engine.store.getWallet(.mbbank).balance, 1_500_000)
    }
}

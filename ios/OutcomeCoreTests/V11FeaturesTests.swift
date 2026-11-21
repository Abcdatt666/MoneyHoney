import XCTest
@testable import OutcomeCore

final class V11FeaturesTests: XCTestCase {
    @MainActor
    func testTagSuggesterColdStartAndPersonalLearning() throws {
        let engine = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 9, minute: 0))!

        let rCoffee = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Thanh toán thành công 55.000đ tại Highlands Coffee.",
            receivedAt: t0
        ))
        let txCoffee = try XCTUnwrap(rCoffee.transaction)
        let coffeeSuggestions = engine.suggestTags(for: txCoffee, limit: 3)
        XCTAssertEqual(coffeeSuggestions.count, 3)
        XCTAssertEqual(coffeeSuggestions.first?.id, "tag_cf")

        let rApple = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Bạn đã thanh toán thành công 199.000đ cho dịch vụ Apple Services.",
            receivedAt: t0.addingTimeInterval(300)
        ))
        let txApple = try XCTUnwrap(rApple.transaction)
        XCTAssertEqual(engine.suggestTags(for: txApple, limit: 3).first?.id, "tag_hoa_don")

        // Personal learning: custom tag "Thú cưng" learned from history
        let petTag = try engine.addCustomTag(name: "Thú cưng", now: t0)
        try engine.addManualTransaction(
            walletId: .momo,
            direction: .out,
            amount: 120_000,
            tagId: petTag.id,
            description: "Pet Mart Quận 1",
            occurredAt: t0.addingTimeInterval(600)
        )

        let rPet = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Thanh toán thành công 85.000đ tại Pet Mart Quận 1.",
            receivedAt: t0.addingTimeInterval(3600)
        ))
        let txPet = try XCTUnwrap(rPet.transaction)
        XCTAssertEqual(engine.suggestTags(for: txPet, limit: 3).first?.id, petTag.id)

        // Income refund -> tag_hoan_tien
        let rRefund = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Hoàn tiền thành công",
            body: "Bạn vừa được hoàn 50.000đ từ giao dịch Shopee vào Ví MoMo.",
            receivedAt: t0.addingTimeInterval(7200)
        ))
        let txRefund = try XCTUnwrap(rRefund.transaction)
        XCTAssertEqual(engine.suggestTags(for: txRefund, limit: 3).first?.id, "tag_hoan_tien")
    }

    @MainActor
    func testFullTransactionEditRecalculatesBalances() throws {
        let engine = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 10, minute: 0))!
        try engine.reconcileBalances([.mbbank: 2_000_000, .momo: 500_000], now: t0)

        let tx = try engine.addManualTransaction(
            walletId: .momo,
            direction: .out,
            amount: 100_000,
            tagId: "tag_an_uong",
            description: "Cơm trưa",
            occurredAt: t0
        )
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 400_000)

        let updated = try engine.updateTransaction(
            txId: tx.id,
            walletId: .mbbank,
            direction: .out,
            amount: 250_000,
            tagId: "tag_mua_sam",
            description: "Mua giày thể thao",
            note: "Đặt online",
            occurredAt: t0.addingTimeInterval(1800)
        )
        XCTAssertEqual(updated.sourceWalletId, .mbbank)
        XCTAssertEqual(updated.amount, 250_000)
        XCTAssertEqual(updated.tagId, "tag_mua_sam")
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 500_000)
        XCTAssertEqual(engine.store.getWallet(.mbbank).balance, 1_750_000)
    }

    @MainActor
    func testJSONBackupRestoreAndCSVExport() throws {
        let engineA = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 11, minute: 0))!
        try engineA.reconcileBalances([.mbbank: 4_000_000, .momo: 350_000], now: t0)
        let customTag = try engineA.addCustomTag(name: "Sách", now: t0)
        try engineA.addManualTransaction(
            walletId: .mbbank,
            direction: .out,
            amount: 180_000,
            tagId: customTag.id,
            description: "Fahasa, \"Sách Swift\"",
            note: "Mua đọc cuối tuần",
            occurredAt: t0
        )

        let backupData = try engineA.exportBackupJSON(now: t0)
        let csv = engineA.exportCSV()
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}Ngày giờ,"))
        XCTAssertTrue(csv.contains("\"Fahasa, \"\"Sách Swift\"\"\""))
        XCTAssertTrue(csv.contains("Sách"))

        // Restore into a completely separate store
        let engineB = ExpenseEngine()
        let snapshot = try engineB.previewBackupJSON(backupData)
        XCTAssertEqual(snapshot.transactions.count, 1)
        engineB.restoreBackup(snapshot)

        XCTAssertEqual(engineB.store.getWallet(.mbbank).balance, 3_820_000)
        XCTAssertEqual(engineB.store.getWallet(.momo).balance, 350_000)
        XCTAssertEqual(engineB.listAllTransactions().count, 1)
        XCTAssertTrue(engineB.listTags().contains(where: { $0.name == "Sách" }))
    }

    @MainActor
    func testConvertMoMoCashInInternalTransferToExpense() throws {
        let engine = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 11, minute: 30))!
        try engine.reconcileBalances([.mbbank: 3_000_000, .momo: 200_000], now: t0)

        let rMb = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -220,000VND 21/11/26 11:30|SD: 2,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900111",
            receivedAt: t0
        ))
        let cashInTx = try XCTUnwrap(rMb.transaction)
        XCTAssertEqual(engine.store.getWallet(.mbbank).balance, 2_780_000)
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 420_000)

        let converted = try engine.updateTransaction(
            txId: cashInTx.id,
            walletId: .mbbank,
            direction: .out,
            amount: 220_000,
            tagId: "tag_hoa_don",
            description: "Bill WiFi FPT",
            note: "Tháng 11",
            occurredAt: t0
        )
        XCTAssertNil(converted.targetWalletId)
        XCTAssertEqual(converted.txType, .expense)
        XCTAssertEqual(engine.store.getWallet(.momo).balance, 200_000)
        XCTAssertEqual(engine.store.getWallet(.mbbank).balance, 2_780_000)
        let summary = engine.getDashboardSummary(year: 2026, month: 11, now: t0)
        XCTAssertEqual(summary.monthlyExpense, 220_000)
        XCTAssertEqual(summary.expenseByTag["Hóa đơn"], 220_000)
    }

    @MainActor
    func testMoMoCashInPlusMoMoBillPaymentAutoConvertsBothOrders() throws {
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 14, minute: 0))!

        // Order 1: MBBank MOMO-CASHIN first, MoMo payment 4s later
        let e1 = ExpenseEngine()
        try e1.reconcileBalances([.mbbank: 2_000_000, .momo: 100_000], now: t0)
        _ = e1.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -220,000VND 21/11/26 14:00|SD: 1,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900222",
            receivedAt: t0.addingTimeInterval(1)
        ))
        let rMomo = e1.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Bạn đã thanh toán thành công 220.000đ cho dịch vụ FPT Telecom.",
            receivedAt: t0.addingTimeInterval(5)
        ))
        XCTAssertEqual(rMomo.status, .created)
        XCTAssertEqual(rMomo.prompt?.shouldPrompt, true)
        XCTAssertEqual(e1.listAllTransactions().count, 1)
        XCTAssertEqual(e1.store.getWallet(.mbbank).balance, 1_780_000)
        XCTAssertEqual(e1.store.getWallet(.momo).balance, 100_000)
        XCTAssertEqual(e1.listAllTransactions().first?.description, "FPT Telecom")

        // Order 2: MoMo payment first, MBBank MOMO-CASHIN 5s later
        let e2 = ExpenseEngine()
        try e2.reconcileBalances([.mbbank: 2_000_000, .momo: 100_000], now: t0)
        _ = e2.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Thanh toán thành công",
            body: "Bạn đã thanh toán thành công 220.000đ cho dịch vụ FPT Telecom.",
            receivedAt: t0.addingTimeInterval(2)
        ))
        let rMb = e2.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -220,000VND 21/11/26 14:00|SD: 1,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900333",
            receivedAt: t0.addingTimeInterval(7)
        ))
        XCTAssertEqual(rMb.status, .duplicate)
        XCTAssertEqual(e2.listAllTransactions().count, 1)
        XCTAssertEqual(e2.store.getWallet(.mbbank).balance, 1_780_000)
        XCTAssertEqual(e2.store.getWallet(.momo).balance, 100_000)
        XCTAssertEqual(e2.listAllTransactions().first?.sourceWalletId, .mbbank)
        XCTAssertEqual(e2.listAllTransactions().first?.description, "FPT Telecom")
    }

    @MainActor
    func testMBBankTwoAccountSelfTransferDiscrepancyAndLocation() throws {
        let engine = ExpenseEngine()
        let t0 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 15, minute: 0))!
        try engine.reconcileBalances([.mbbank: 5_000_000, .momo: 200_000], now: t0)

        // #7 Self-transfer between two own MBBank accounts
        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -1,000,000VND 21/11/26 15:05|SD: 4,000,000VND| ND: Chuyen sang TK phu - Trace 101010",
            receivedAt: t0.addingTimeInterval(300)
        ))
        let r2 = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 88886666|GD: +1,000,000VND 21/11/26 15:05|SD: 1,000,000VND| ND: Nhan tu TK chinh - Trace 101011",
            receivedAt: t0.addingTimeInterval(304)
        ))
        XCTAssertEqual(r2.status, .duplicate)
        XCTAssertEqual(engine.listAllTransactions().count, 1)
        XCTAssertEqual(engine.store.getWallet(.mbbank).balance, 5_000_000)
        let summary = engine.getDashboardSummary(year: 2026, month: 11, now: t0)
        XCTAssertEqual(summary.monthlyExpense, 0)
        XCTAssertEqual(summary.monthlyIncome, 0)

        // #9 Discrepancy detection + location propagation
        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -50,000VND 21/11/26 16:00|SD: 4,850,000VND| ND: Cafe - Trace 202020",
            receivedAt: t0.addingTimeInterval(3600),
            locationName: "Đường Nguyễn Huệ, Q.1",
            latitude: 10.7745,
            longitude: 106.7035
        ))
        let discrepancy = try XCTUnwrap(engine.detectMBBankDiscrepancy())
        XCTAssertEqual(discrepancy.reportedBalance, 4_850_000)
        XCTAssertEqual(discrepancy.appBalance, 4_950_000)
        XCTAssertEqual(discrepancy.delta, -100_000)
        XCTAssertEqual(engine.listAllTransactions().first?.locationName, "Đường Nguyễn Huệ, Q.1")
        XCTAssertTrue(engine.exportCSV().contains("Đường Nguyễn Huệ, Q.1"))

        try engine.reconcileBalances([.mbbank: 4_850_000, .momo: 200_000], now: t0.addingTimeInterval(3900))
        XCTAssertNil(engine.detectMBBankDiscrepancy())
    }
}

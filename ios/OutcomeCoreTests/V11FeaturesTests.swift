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
}

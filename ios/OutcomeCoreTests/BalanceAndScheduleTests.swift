import XCTest
@testable import OutcomeCore

final class BalanceAndScheduleTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func makeDate(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: 0))!
    }

    func testMonthEndReminderWeekday() {
        XCTAssertEqual(
            BalanceCalculator.calculateMonthEndReminder(year: 2026, month: 11, calendar: cal),
            makeDate(2026, 11, 30, 12, 0)
        )
    }

    func testMonthEndReminderSaturdayShiftsToFriday() {
        XCTAssertEqual(
            BalanceCalculator.calculateMonthEndReminder(year: 2026, month: 10, calendar: cal),
            makeDate(2026, 10, 30, 12, 0)
        )
        XCTAssertEqual(
            BalanceCalculator.calculateMonthEndReminder(year: 2026, month: 2, calendar: cal),
            makeDate(2026, 2, 27, 12, 0)
        )
    }

    func testMonthEndReminderSundayShiftsToFriday() {
        XCTAssertEqual(
            BalanceCalculator.calculateMonthEndReminder(year: 2026, month: 5, calendar: cal),
            makeDate(2026, 5, 29, 12, 0)
        )
    }

    func testLeapYearFebruary() {
        XCTAssertEqual(
            BalanceCalculator.calculateMonthEndReminder(year: 2024, month: 2, calendar: cal),
            makeDate(2024, 2, 29, 12, 0)
        )
    }

    func testNextReminderRolloverIncludingYearBoundary() {
        XCTAssertEqual(
            BalanceCalculator.getNextReconciliationReminder(now: makeDate(2026, 11, 30, 11, 59), calendar: cal),
            makeDate(2026, 11, 30, 12, 0)
        )
        XCTAssertEqual(
            BalanceCalculator.getNextReconciliationReminder(now: makeDate(2026, 11, 30, 12, 0), calendar: cal),
            makeDate(2026, 12, 31, 12, 0)
        )
        XCTAssertEqual(
            BalanceCalculator.getNextReconciliationReminder(now: makeDate(2026, 12, 31, 12, 5), calendar: cal),
            makeDate(2027, 1, 29, 12, 0)
        )
    }

    @MainActor
    func testBalancesWithInternalTransferAndReconciliationDiscrepancy() throws {
        let engine = ExpenseEngine()
        try engine.reconcileBalances(
            [.mbbank: 10_000_000, .momo: 500_000],
            note: "Initial setup",
            now: makeDate(2026, 11, 1, 8, 0)
        )

        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -1,000,000VND 02/11/26 09:00|SD: 9,000,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 100001",
            receivedAt: makeDate(2026, 11, 2, 9, 0)
        ))

        let rExp = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000VND 03/11/26 12:00|SD: 8,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 100002",
            receivedAt: makeDate(2026, 11, 3, 12, 0)
        ))
        let expTx = try XCTUnwrap(rExp.transaction)
        try engine.confirmTransaction(txId: expTx.id, tagId: "tag_an_uong")

        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: +400,000VND 04/11/26 15:00|SD: 9,250,000VND| ND: MOMO-CASHOUT - Ma giao dich/ Trace 100003",
            receivedAt: makeDate(2026, 11, 4, 15, 0)
        ))

        let summary = engine.getDashboardSummary(year: 2026, month: 11, now: makeDate(2026, 11, 20, 15, 0), calendar: cal)
        XCTAssertEqual(summary.mbbankBalance, 9_250_000)
        XCTAssertEqual(summary.momoBalance, 1_100_000)
        XCTAssertEqual(summary.totalBalance, 10_350_000)
        XCTAssertEqual(summary.monthlyExpense, 150_000)
        XCTAssertEqual(summary.monthlyIncome, 0)

        let recs = try engine.reconcileBalances(
            [.mbbank: 9_250_000, .momo: 1_020_000],
            note: "Chốt số dư cuối tháng 11",
            now: makeDate(2026, 11, 30, 12, 0)
        )
        let momoRec = try XCTUnwrap(recs.first(where: { $0.walletId == .momo }))
        XCTAssertEqual(momoRec.expectedBalance, 1_100_000)
        XCTAssertEqual(momoRec.actualBalance, 1_020_000)
        XCTAssertEqual(momoRec.discrepancy, -80_000)
    }
}

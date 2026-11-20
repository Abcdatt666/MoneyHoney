import Foundation

/// Wallet balance mutations, reconciliation, and month-end reminder scheduling.
public enum BalanceCalculator {
    public enum BalanceError: Error, Equatable {
        case internalTransferMissingTarget
        case negativeActualBalance(WalletId)
    }

    private static func applyDelta(
        store: ExpenseStore,
        tx: Transaction,
        multiplier: Int
    ) throws {
        switch tx.txType {
        case .expense:
            var wallet = store.getWallet(tx.sourceWalletId)
            wallet.balance -= multiplier * tx.amount
            store.saveWallet(wallet)

        case .income:
            var wallet = store.getWallet(tx.sourceWalletId)
            wallet.balance += multiplier * tx.amount
            store.saveWallet(wallet)

        case .internalTransfer:
            guard let targetId = tx.targetWalletId else {
                throw BalanceError.internalTransferMissingTarget
            }
            var src = store.getWallet(tx.sourceWalletId)
            var dst = store.getWallet(targetId)
            src.balance -= multiplier * tx.amount
            dst.balance += multiplier * tx.amount
            store.saveWallet(src)
            store.saveWallet(dst)
        }
    }

    @MainActor
    public static func applyTransactionBalances(
        store: ExpenseStore,
        tx: Transaction,
        syncReportedBalance: Bool = false
    ) throws {
        try applyDelta(store: store, tx: tx, multiplier: 1)

        if syncReportedBalance,
           let reported = tx.reportedBalanceAfter,
           tx.sourceWalletId == .mbbank || tx.targetWalletId == .mbbank {
            var mb = store.getWallet(.mbbank)
            mb.balance = reported
            store.saveWallet(mb)
        }
    }

    @MainActor
    public static func reverseTransactionBalances(
        store: ExpenseStore,
        tx: Transaction
    ) throws {
        try applyDelta(store: store, tx: tx, multiplier: -1)
    }

    @MainActor
    public static func reconcileWalletBalances(
        store: ExpenseStore,
        actualBalances: [WalletId: Int],
        reconciledAt: Date,
        note: String = ""
    ) throws -> [BalanceReconciliation] {
        var records: [BalanceReconciliation] = []
        for walletId in WalletId.allCases {
            guard let actual = actualBalances[walletId] else { continue }
            guard actual >= 0 else {
                throw BalanceError.negativeActualBalance(walletId)
            }

            var wallet = store.getWallet(walletId)
            let expected = wallet.balance
            let discrepancy = actual - expected

            let rec = BalanceReconciliation(
                walletId: walletId,
                expectedBalance: expected,
                actualBalance: actual,
                discrepancy: discrepancy,
                reconciledAt: reconciledAt,
                note: note
            )
            store.saveReconciliation(rec)

            wallet.balance = actual
            wallet.lastReconciledBalance = actual
            wallet.lastReconciledAt = reconciledAt
            store.saveWallet(wallet)

            records.append(rec)
        }
        return records
    }

    /// Return 12:00 PM on the last weekday of (year, month).
    /// If the last calendar day falls on Saturday or Sunday, shift back to Friday.
    public static func calculateMonthEndReminder(
        year: Int,
        month: Int,
        calendar: Calendar = .current
    ) -> Date {
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = month
        startComponents.day = 1
        startComponents.hour = 12
        startComponents.minute = 0
        startComponents.second = 0

        let firstOfMonth = calendar.date(from: startComponents) ?? Date()
        let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) ?? 1..<29
        let lastDay = dayRange.upperBound - 1

        var targetComponents = startComponents
        targetComponents.day = lastDay
        var targetDate = calendar.date(from: targetComponents) ?? firstOfMonth

        // Calendar weekday: 1 = Sunday, 7 = Saturday
        let weekday = calendar.component(.weekday, from: targetDate)
        if weekday == 7 {
            targetDate = calendar.date(byAdding: .day, value: -1, to: targetDate) ?? targetDate
        } else if weekday == 1 {
            targetDate = calendar.date(byAdding: .day, value: -2, to: targetDate) ?? targetDate
        }

        return targetDate
    }

    /// Return the next upcoming month-end balance reminder at 12:00 PM.
    public static func getNextReconciliationReminder(
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)

        let candidate = calculateMonthEndReminder(year: year, month: month, calendar: calendar)
        if now < candidate {
            return candidate
        }

        let nextYear = month == 12 ? year + 1 : year
        let nextMonth = month == 12 ? 1 : month + 1
        return calculateMonthEndReminder(year: nextYear, month: nextMonth, calendar: calendar)
    }
}

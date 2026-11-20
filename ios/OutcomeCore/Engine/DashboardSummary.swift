import Foundation

/// Aggregated balances, pending queue count, and monthly totals.
public struct DashboardSummary: Equatable, Sendable {
    public let mbbankBalance: Int
    public let momoBalance: Int
    public let totalBalance: Int
    public let pendingCount: Int
    public let monthlyExpense: Int
    public let monthlyIncome: Int
    public let expenseByTag: [String: Int]
    public let nextReconciliationReminder: Date

    public init(
        mbbankBalance: Int,
        momoBalance: Int,
        totalBalance: Int,
        pendingCount: Int,
        monthlyExpense: Int,
        monthlyIncome: Int,
        expenseByTag: [String: Int],
        nextReconciliationReminder: Date
    ) {
        self.mbbankBalance = mbbankBalance
        self.momoBalance = momoBalance
        self.totalBalance = totalBalance
        self.pendingCount = pendingCount
        self.monthlyExpense = monthlyExpense
        self.monthlyIncome = monthlyIncome
        self.expenseByTag = expenseByTag
        self.nextReconciliationReminder = nextReconciliationReminder
    }
}

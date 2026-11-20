import Foundation

/// Snapshot recorded when the user reconciles actual wallet balance.
public struct BalanceReconciliation: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let walletId: WalletId
    public let expectedBalance: Int
    public let actualBalance: Int
    public let discrepancy: Int
    public let reconciledAt: Date
    public let note: String

    public init(
        id: String = UUID().uuidString,
        walletId: WalletId,
        expectedBalance: Int,
        actualBalance: Int,
        discrepancy: Int,
        reconciledAt: Date,
        note: String = ""
    ) {
        self.id = id
        self.walletId = walletId
        self.expectedBalance = expectedBalance
        self.actualBalance = actualBalance
        self.discrepancy = discrepancy
        self.reconciledAt = reconciledAt
        self.note = note
    }
}

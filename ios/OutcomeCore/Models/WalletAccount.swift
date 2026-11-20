import Foundation

/// Represents a tracked wallet or bank account.
public struct WalletAccount: Identifiable, Equatable, Codable, Sendable {
    public let id: WalletId
    public var name: String
    public var balance: Int
    public var lastReconciledBalance: Int
    public var lastReconciledAt: Date?

    public init(
        id: WalletId,
        name: String,
        balance: Int = 0,
        lastReconciledBalance: Int = 0,
        lastReconciledAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.balance = balance
        self.lastReconciledBalance = lastReconciledBalance
        self.lastReconciledAt = lastReconciledAt
    }
}

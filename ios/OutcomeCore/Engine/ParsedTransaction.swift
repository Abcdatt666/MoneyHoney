import Foundation

/// Structured output produced from a raw bank or wallet notification.
public struct ParsedTransaction: Equatable, Sendable {
    public let txType: TransactionType
    public let sourceWalletId: WalletId
    public let targetWalletId: WalletId?
    public let amount: Int
    public let direction: Direction
    public let description: String
    public let traceId: String?
    public let reportedBalanceAfter: Int?
    public let occurredAt: Date

    public init(
        txType: TransactionType,
        sourceWalletId: WalletId,
        targetWalletId: WalletId?,
        amount: Int,
        direction: Direction,
        description: String,
        traceId: String?,
        reportedBalanceAfter: Int?,
        occurredAt: Date
    ) {
        self.txType = txType
        self.sourceWalletId = sourceWalletId
        self.targetWalletId = targetWalletId
        self.amount = amount
        self.direction = direction
        self.description = description
        self.traceId = traceId
        self.reportedBalanceAfter = reportedBalanceAfter
        self.occurredAt = occurredAt
    }
}

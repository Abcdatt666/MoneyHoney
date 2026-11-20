import Foundation

/// A financial event parsed from a notification or added manually.
public struct Transaction: Identifiable, Equatable, Codable, Sendable, Hashable {
    public let id: String
    public var txType: TransactionType
    public var sourceWalletId: WalletId
    public var targetWalletId: WalletId?
    public var amount: Int
    public var direction: Direction
    public var description: String
    public var occurredAt: Date
    public var createdAt: Date
    public var status: TransactionStatus
    public var tagId: String?
    public var note: String
    public var isManual: Bool
    public var traceId: String?
    public var rawNotificationText: String?
    public var reportedBalanceAfter: Int?
    public var confirmedAt: Date?

    public init(
        id: String = UUID().uuidString,
        txType: TransactionType,
        sourceWalletId: WalletId,
        amount: Int,
        direction: Direction,
        description: String,
        occurredAt: Date,
        createdAt: Date,
        status: TransactionStatus = .pending,
        targetWalletId: WalletId? = nil,
        tagId: String? = nil,
        note: String = "",
        isManual: Bool = false,
        traceId: String? = nil,
        rawNotificationText: String? = nil,
        reportedBalanceAfter: Int? = nil,
        confirmedAt: Date? = nil
    ) {
        self.id = id
        self.txType = txType
        self.sourceWalletId = sourceWalletId
        self.targetWalletId = targetWalletId
        self.amount = amount
        self.direction = direction
        self.description = description
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.status = status
        self.tagId = tagId
        self.note = note
        self.isManual = isManual
        self.traceId = traceId
        self.rawNotificationText = rawNotificationText
        self.reportedBalanceAfter = reportedBalanceAfter
        self.confirmedAt = confirmedAt
    }
}

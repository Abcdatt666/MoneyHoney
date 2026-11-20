import Foundation

/// High-level accounting classification of a transaction.
public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case expense = "EXPENSE"
    case income = "INCOME"
    case internalTransfer = "INTERNAL_TRANSFER"
}

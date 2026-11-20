import Foundation

/// User confirmation state of a transaction.
public enum TransactionStatus: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING"
    case confirmed = "CONFIRMED"
}

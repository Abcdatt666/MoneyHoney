import Foundation

/// Cash flow direction relative to a wallet.
public enum Direction: String, Codable, CaseIterable, Sendable {
    case out = "OUT"
    case `in` = "IN"
}

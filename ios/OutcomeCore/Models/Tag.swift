import Foundation

/// Unified category tag for both expenses and incoming transactions.
public struct Tag: Identifiable, Equatable, Codable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var isDefault: Bool
    public var sortOrder: Int
    public var createdAt: Date

    public init(
        id: String,
        name: String,
        isDefault: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}

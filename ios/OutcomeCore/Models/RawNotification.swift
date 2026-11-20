import Foundation

/// Incoming push notification payload forwarded by iOS Shortcuts.
public struct RawNotification: Equatable, Sendable {
    public let sourceApp: WalletId
    public let title: String
    public let body: String
    public let receivedAt: Date

    public init(
        sourceApp: WalletId,
        title: String,
        body: String,
        receivedAt: Date = Date()
    ) {
        self.sourceApp = sourceApp
        self.title = title
        self.body = body
        self.receivedAt = receivedAt
    }
}

import Foundation

/// Outcome of processing an incoming push notification.
public struct IngestResult: Equatable, Sendable {
    public enum Status: String, Sendable {
        case created = "CREATED"
        case ignored = "IGNORED"
        case duplicate = "DUPLICATE"
    }

    public let status: Status
    public let transaction: Transaction?
    public let prompt: NotificationPrompt?
    public let reason: String?

    public init(
        status: Status,
        transaction: Transaction? = nil,
        prompt: NotificationPrompt? = nil,
        reason: String? = nil
    ) {
        self.status = status
        self.transaction = transaction
        self.prompt = prompt
        self.reason = reason
    }
}

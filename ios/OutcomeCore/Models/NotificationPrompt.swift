import Foundation

/// Instruction describing the local notification to display to the user.
public struct NotificationPrompt: Equatable, Sendable {
    public let shouldPrompt: Bool
    public let transactionId: String
    public let title: String
    public let body: String

    public init(shouldPrompt: Bool, transactionId: String, title: String, body: String) {
        self.shouldPrompt = shouldPrompt
        self.transactionId = transactionId
        self.title = title
        self.body = body
    }
}

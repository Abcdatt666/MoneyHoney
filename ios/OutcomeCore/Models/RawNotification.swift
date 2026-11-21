import Foundation

/// Incoming push notification payload forwarded by iOS Shortcuts.
public struct RawNotification: Equatable, Sendable {
    public let sourceApp: WalletId
    public let title: String
    public let body: String
    public let receivedAt: Date
    public let locationName: String?
    public let latitude: Double?
    public let longitude: Double?

    public init(
        sourceApp: WalletId,
        title: String,
        body: String,
        receivedAt: Date = Date(),
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.sourceApp = sourceApp
        self.title = title
        self.body = body
        self.receivedAt = receivedAt
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
    }
}

import Foundation

/// Supported money sources in Phase 1.
public enum WalletId: String, Codable, CaseIterable, Sendable, Identifiable {
    case mbbank = "MBBANK"
    case momo = "MOMO"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mbbank:
            return "MBBank"
        case .momo:
            return "Ví MoMo"
        }
    }
}

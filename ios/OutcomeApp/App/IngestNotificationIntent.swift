import AppIntents
import Foundation
import OutcomeCore

enum ShortcutWalletSource: String, AppEnum {
    case mbbank = "MBBANK"
    case momo = "MOMO"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nguồn thông báo")
    static let caseDisplayRepresentations: [ShortcutWalletSource: DisplayRepresentation] = [
        .mbbank: DisplayRepresentation(title: "MBBank"),
        .momo: DisplayRepresentation(title: "MoMo"),
    ]

    var walletId: WalletId {
        switch self {
        case .mbbank: return .mbbank
        case .momo: return .momo
        }
    }
}

/// Invoked automatically by iOS Shortcuts when MBBank or MoMo pushes a notification.
struct IngestNotificationIntent: AppIntent {
    static let title: LocalizedStringResource = "Ghi nhận biến động số dư"
    static let description = IntentDescription(
        "Phân tích thông báo từ MBBank hoặc MoMo, cập nhật số dư ví và nhắc chọn tag."
    )
    static let openAppWhenRun: Bool = false

    @Parameter(title: "Ứng dụng nguồn")
    var sourceApp: ShortcutWalletSource

    @Parameter(title: "Tiêu đề thông báo", default: "")
    var notificationTitle: String

    @Parameter(title: "Nội dung thông báo")
    var notificationBody: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = SwiftDataExpenseStore()
        let engine = ExpenseEngine(store: store)
        let raw = RawNotification(
            sourceApp: sourceApp.walletId,
            title: notificationTitle,
            body: notificationBody,
            receivedAt: Date()
        )
        let result = engine.ingestNotification(raw)

        if result.status == .created,
           let prompt = result.prompt,
           prompt.shouldPrompt {
            let suggestedTags = result.transaction.map { engine.suggestTags(for: $0, limit: 3) } ?? []
            await ReminderScheduler.scheduleTransactionPrompt(prompt, suggestedTags: suggestedTags)
        }

        return .result()
    }
}

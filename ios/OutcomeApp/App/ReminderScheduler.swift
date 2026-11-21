import Foundation
import OutcomeCore
import UserNotifications

enum ReminderScheduler {
    static let quickTagActionPrefix = "outcome.tag."
    static let openTagSheetActionId = "outcome.open"
    private static let txCategoryPrefix = "outcome.tx.cat."
    private static let monthEndNotificationIdentifier = "outcome.month_end_reconciliation"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    static func scheduleTransactionPrompt(
        _ prompt: NotificationPrompt,
        suggestedTags: [Tag] = []
    ) async {
        guard prompt.shouldPrompt else { return }

        let center = UNUserNotificationCenter.current()
        let categoryId = "\(txCategoryPrefix)\(prompt.transactionId)"

        if !suggestedTags.isEmpty {
            let category = makeQuickTagCategory(
                identifier: categoryId,
                suggestedTags: Array(suggestedTags.prefix(3))
            )
            let existing = await center.notificationCategories()
            var retained = existing.filter { !$0.identifier.hasPrefix(txCategoryPrefix) }
            let recentDynamic = existing
                .filter { $0.identifier.hasPrefix(txCategoryPrefix) && $0.identifier != categoryId }
                .prefix(14)
            retained.formUnion(recentDynamic)
            retained.insert(category)
            center.setNotificationCategories(retained)
        }

        let content = UNMutableNotificationContent()
        content.title = prompt.title
        content.body = suggestedTags.isEmpty
            ? prompt.body
            : "\(prompt.body) Giữ thông báo để chọn nhanh."
        content.sound = .default
        content.userInfo = ["transactionId": prompt.transactionId]
        if !suggestedTags.isEmpty {
            content.categoryIdentifier = categoryId
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "outcome.tx.\(prompt.transactionId)",
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    static func removeDeliveredTransactionPrompt(txId: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: ["outcome.tx.\(txId)"]
        )
    }

    static func scheduleNextMonthEndReminder(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [monthEndNotificationIdentifier])

        let nextDate = BalanceCalculator.getNextReconciliationReminder(now: now)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: nextDate
        )

        let content = UNMutableNotificationContent()
        content.title = "Đối soát số dư cuối tháng"
        content.body = "Kiểm tra số dư thực tế MBBank và Ví MoMo để chốt sổ tháng này."
        content.sound = .default
        content.userInfo = ["route": "reconcile"]

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: monthEndNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private static func makeQuickTagCategory(
        identifier: String,
        suggestedTags: [Tag]
    ) -> UNNotificationCategory {
        var actions: [UNNotificationAction] = suggestedTags.enumerated().map { idx, tag in
            let title = idx == 0 ? "\(tag.name) (Gợi ý)" : tag.name
            let symbol = OutcomeTheme.symbol(forTagId: tag.id)
            return UNNotificationAction(
                identifier: "\(quickTagActionPrefix)\(tag.id)",
                title: title,
                options: [],
                icon: UNNotificationActionIcon(systemImageName: symbol)
            )
        }

        actions.append(
            UNNotificationAction(
                identifier: openTagSheetActionId,
                title: "Chọn tag khác & Ghi chú…",
                options: [.foreground],
                icon: UNNotificationActionIcon(systemImageName: "tag.fill")
            )
        )

        return UNNotificationCategory(
            identifier: identifier,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }
}

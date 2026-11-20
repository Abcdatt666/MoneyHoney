import Foundation
import OutcomeCore
import UserNotifications

enum ReminderScheduler {
    private static let monthEndNotificationIdentifier = "outcome.month_end_reconciliation"

    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    static func scheduleTransactionPrompt(_ prompt: NotificationPrompt) async {
        guard prompt.shouldPrompt else { return }

        let content = UNMutableNotificationContent()
        content.title = prompt.title
        content.body = prompt.body
        content.sound = .default
        content.userInfo = ["transactionId": prompt.transactionId]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "outcome.tx.\(prompt.transactionId)",
            content: content,
            trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
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
}

import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onSelectTransactionId: ((String) -> Void)?
    var onOpenReconcile: (() -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let txId = userInfo["transactionId"] as? String
        let route = userInfo["route"] as? String

        await MainActor.run {
            if let txId {
                self.onSelectTransactionId?(txId)
            } else if route == "reconcile" {
                self.onOpenReconcile?()
            }
        }
    }
}

@main
struct OutcomeApp: App {
    @State private var coordinator = AppCoordinator()
    @State private var notificationDelegate = NotificationCenterDelegate()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .task {
                    notificationDelegate.onSelectTransactionId = { txId in
                        coordinator.openTransactionFromNotification(txId: txId)
                    }
                    notificationDelegate.onOpenReconcile = {
                        coordinator.selectedTab = .wallets
                    }
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    await ReminderScheduler.requestAuthorizationIfNeeded()
                    await ReminderScheduler.scheduleNextMonthEndReminder()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        coordinator.refresh()
                    }
                }
        }
        .modelContainer(OutcomeModelContainer.shared)
    }
}

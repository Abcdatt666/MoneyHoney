import SwiftData
import SwiftUI
import UserNotifications

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCenterDelegate()

    @MainActor var onSelectTransactionId: ((String) -> Void)?
    @MainActor var onOpenReconcile: (() -> Void)?
    @MainActor var onReceiveForegroundNotification: (() -> Void)?

    @MainActor private var pendingTransactionId: String?
    @MainActor private var pendingOpenReconcile: Bool = false

    private override init() {
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
        Task { @MainActor in
            self.onReceiveForegroundNotification?()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let txId = userInfo["transactionId"] as? String
        let route = userInfo["route"] as? String

        completionHandler()

        Task { @MainActor in
            if let txId {
                if let handler = self.onSelectTransactionId {
                    handler(txId)
                } else {
                    self.pendingTransactionId = txId
                }
            } else if route == "reconcile" {
                if let handler = self.onOpenReconcile {
                    handler()
                } else {
                    self.pendingOpenReconcile = true
                }
            }
        }
    }

    @MainActor
    func consumePendingRouteIfNeeded() {
        if let txId = pendingTransactionId {
            pendingTransactionId = nil
            onSelectTransactionId?(txId)
        } else if pendingOpenReconcile {
            pendingOpenReconcile = false
            onOpenReconcile?()
        }
    }
}

@main
struct OutcomeApp: App {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(coordinator)
                .task {
                    let delegate = NotificationCenterDelegate.shared
                    delegate.onSelectTransactionId = { txId in
                        coordinator.openTransactionFromNotification(txId: txId)
                    }
                    delegate.onOpenReconcile = {
                        coordinator.selectedTab = .wallets
                    }
                    delegate.onReceiveForegroundNotification = {
                        coordinator.refresh()
                    }
                    delegate.consumePendingRouteIfNeeded()

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

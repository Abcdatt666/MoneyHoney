import OutcomeCore
import SwiftData
import SwiftUI
import UserNotifications

private final class SendableCompletion: @unchecked Sendable {
    let call: () -> Void
    init(_ call: @escaping () -> Void) {
        self.call = call
    }
}

final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationCenterDelegate()

    @MainActor var onSelectTransactionId: ((String) -> Void)?
    @MainActor var onOpenReconcile: (() -> Void)?
    @MainActor var onReceiveForegroundNotification: (() -> Void)?
    @MainActor var onDidQuickTagTransaction: (() -> Void)?

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
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        let txId = userInfo["transactionId"] as? String
        let route = userInfo["route"] as? String

        // Background 1-tap quick tag directly from Lock Screen / Notification banner
        if actionId.hasPrefix(ReminderScheduler.quickTagActionPrefix), let txId {
            let tagId = String(actionId.dropFirst(ReminderScheduler.quickTagActionPrefix.count))
            let completion = SendableCompletion(completionHandler)
            Task { @MainActor in
                let store = SwiftDataExpenseStore()
                let engine = ExpenseEngine(store: store)
                _ = try? engine.confirmTransaction(txId: txId, tagId: tagId, note: "")
                ReminderScheduler.removeDeliveredTransactionPrompt(txId: txId)
                self.onDidQuickTagTransaction?()
                completion.call()
            }
            return
        }

        completionHandler()

        if actionId == UNNotificationDismissActionIdentifier {
            return
        }

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
    @State private var lockManager = BiometricLockManager()
    @AppStorage("outcome.requireBiometricLock") private var requireBiometricLock: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()
                    .environment(coordinator)

                if requireBiometricLock && lockManager.isLocked {
                    LockScreenOverlayView(lockManager: lockManager)
                        .transition(.opacity)
                }
            }
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
                delegate.onDidQuickTagTransaction = {
                    coordinator.refresh()
                }
                delegate.consumePendingRouteIfNeeded()

                if requireBiometricLock {
                    lockManager.lockIfRequired(isEnabled: true)
                    await lockManager.authenticate()
                }

                await ReminderScheduler.requestAuthorizationIfNeeded()
                await ReminderScheduler.scheduleNextMonthEndReminder()
            }
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .background:
                    lockManager.lockIfRequired(isEnabled: requireBiometricLock)
                case .active:
                    coordinator.refresh()
                    if requireBiometricLock && lockManager.isLocked {
                        Task {
                            await lockManager.authenticate()
                        }
                    }
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onChange(of: requireBiometricLock) { _, enabled in
                if !enabled {
                    lockManager.isLocked = false
                }
            }
        }
        .modelContainer(OutcomeModelContainer.shared)
    }
}

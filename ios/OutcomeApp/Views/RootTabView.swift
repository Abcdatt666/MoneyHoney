import OutcomeCore
import SwiftUI

struct RootTabView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        @Bindable var bindableCoordinator = coordinator

        TabView(selection: $bindableCoordinator.selectedTab) {
            Tab("Tổng quan", systemImage: "house.fill", value: OutcomeTab.overview) {
                OverviewView()
            }

            Tab("Chờ duyệt", systemImage: "tray.full.fill", value: OutcomeTab.pending) {
                PendingInboxView()
            }
            .badge(coordinator.pendingTransactions.count)

            Tab("Ví", systemImage: "wallet.bifold.fill", value: OutcomeTab.wallets) {
                WalletsReconcileView()
            }
        }
        .modifier(TabBarMinimizeModifier())
        .sheet(item: $bindableCoordinator.activeTaggingTransaction) { tx in
            TagAssignmentSheet(item: tx)
        }
        .sheet(isPresented: $bindableCoordinator.isPresentingManualEntry) {
            ManualEntrySheet()
        }
        .alert(
            "Thông báo",
            isPresented: Binding(
                get: { coordinator.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { coordinator.errorMessage = nil }
                }
            )
        ) {
            Button("Đóng", role: .cancel) {
                coordinator.errorMessage = nil
            }
        } message: {
            Text(coordinator.errorMessage ?? "")
        }
    }
}

private struct TabBarMinimizeModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.never)
        } else {
            content
        }
    }
}

#Preview {
    RootTabView()
        .environment(AppCoordinator.preview())
}

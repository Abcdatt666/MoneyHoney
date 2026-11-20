import OutcomeCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedWalletFilter: WalletId?
    @State private var pendingDeletion: Transaction?

    private var filteredRecentTransactions: [Transaction] {
        let base = coordinator.allTransactions
        let filtered: [Transaction]
        if let walletId = selectedWalletFilter {
            filtered = base.filter {
                $0.sourceWalletId == walletId || $0.targetWalletId == walletId
            }
        } else {
            filtered = base
        }
        return Array(filtered.prefix(12))
    }

    private var currentMonthNumber: Int {
        Calendar.current.component(.month, from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutcomeTheme.Layout.sectionSpacing) {
                    heroHeader

                    dualWalletRow

                    SpendingAllocationCard(
                        monthlyExpense: coordinator.summary.monthlyExpense,
                        expenseByTag: coordinator.summary.expenseByTag,
                        monthNumber: currentMonthNumber
                    )

                    recentActivitySection
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.vertical, 12)
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Tổng quan")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addTransactionButton
                }
            }
            .confirmationDialog(
                "Xóa giao dịch này?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { pendingDeletion = nil }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button("Xóa và hoàn số dư", role: .destructive) {
                    if let tx = pendingDeletion {
                        coordinator.deleteTransaction(txId: tx.id)
                    }
                    pendingDeletion = nil
                }
                Button("Hủy", role: .cancel) {
                    pendingDeletion = nil
                }
            } message: {
                if let tx = pendingDeletion {
                    Text("\(tx.description) · \(VNDFormatter.format(tx.amount))")
                }
            }
        }
    }

    private var heroHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tổng tài sản hiện có")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(VNDFormatter.format(coordinator.summary.totalBalance))
                    .font(.system(.largeTitle, design: .rounded))
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            Spacer()

            if coordinator.summary.pendingCount > 0 {
                Button {
                    coordinator.selectedTab = .pending
                } label: {
                    Text("\(coordinator.summary.pendingCount) mới")
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                        .background(OutcomeTheme.Colors.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mở \(coordinator.summary.pendingCount) giao dịch chờ gắn tag")
            }
        }
        .padding(.top, 4)
    }

    private var dualWalletRow: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: OutcomeTheme.Layout.tileSpacing))
            : AnyLayout(HStackLayout(spacing: OutcomeTheme.Layout.tileSpacing))

        return layout {
            ForEach(coordinator.wallets) { wallet in
                WalletBentoTile(wallet: wallet) {
                    if selectedWalletFilter == wallet.id {
                        selectedWalletFilter = nil
                    } else {
                        selectedWalletFilter = wallet.id
                    }
                }
                .overlay {
                    if selectedWalletFilter == wallet.id {
                        RoundedRectangle(cornerRadius: OutcomeTheme.Layout.tileRadius)
                            .stroke(OutcomeTheme.Colors.accent, lineWidth: 2)
                    }
                }
            }
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedWalletFilter == nil ? "Mới nhất" : "Lọc: \(selectedWalletFilter?.displayName ?? "")")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if selectedWalletFilter != nil {
                    Button("Hiện tất cả") {
                        selectedWalletFilter = nil
                    }
                    .font(.footnote.bold())
                    .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                }
            }

            if filteredRecentTransactions.isEmpty {
                ContentUnavailableView(
                    "Chưa có giao dịch",
                    systemImage: "tray",
                    description: Text("Thông báo MBBank/MoMo từ Shortcuts hoặc giao dịch nhập tay sẽ hiện tại đây.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredRecentTransactions) { tx in
                        Button {
                            if tx.txType != .internalTransfer {
                                coordinator.activeTaggingTransaction = tx
                            }
                        } label: {
                            TransactionRow(
                                transaction: tx,
                                tagName: coordinator.tagName(for: tx.tagId)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if tx.txType != .internalTransfer {
                                Button("Chọn tag & ghi chú", systemImage: "tag") {
                                    coordinator.activeTaggingTransaction = tx
                                }
                            }
                            Button("Xóa giao dịch", systemImage: "trash", role: .destructive) {
                                pendingDeletion = tx
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }

    @ViewBuilder
    private var addTransactionButton: some View {
        let button = Button("Thêm giao dịch", systemImage: "plus") {
            coordinator.isPresentingManualEntry = true
        }
        .labelStyle(.iconOnly)

        if #available(iOS 26, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button
        }
    }
}

#Preview {
    OverviewView()
        .environment(AppCoordinator.preview())
}

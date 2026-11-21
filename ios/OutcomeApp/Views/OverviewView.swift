import OutcomeCore
import SwiftUI

struct OverviewView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("outcome.hideBalances") private var hideBalances: Bool = false

    @State private var selectedWalletFilter: WalletId?
    @State private var selectedTagFilterName: String?
    @State private var searchText: String = ""
    @State private var isShowingAllTransactions: Bool = false
    @State private var pendingDeletion: OutcomeCore.Transaction?
    @State private var dismissedDiscrepancyTimestamp: Date?

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var hasActiveFilter: Bool {
        selectedWalletFilter != nil || selectedTagFilterName != nil
    }

    private var allFilteredTransactions: [OutcomeCore.Transaction] {
        // When typing in search, look across all months so older items are immediately findable.
        var base = isSearching ? coordinator.allTransactions : coordinator.monthTransactions

        if let walletId = selectedWalletFilter {
            base = base.filter {
                $0.sourceWalletId == walletId || $0.targetWalletId == walletId
            }
        }

        if let tagFilter = selectedTagFilterName {
            base = base.filter { tx in
                guard tx.txType != .internalTransfer else { return false }
                let resolvedTagName = coordinator.tagName(for: tx.tagId) ?? "Chưa phân loại"
                return resolvedTagName == tagFilter
            }
        }

        if isSearching {
            let query = trimmedSearch.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            base = base.filter { tx in
                let tagName = coordinator.tagName(for: tx.tagId) ?? ""
                let haystack = "\(tx.description) \(tx.note) \(tagName) \(tx.sourceWalletId.displayName) \(tx.amount) \(VNDFormatter.format(tx.amount))"
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                return haystack.contains(query)
            }
        }

        return base
    }

    private var visibleTransactions: [OutcomeCore.Transaction] {
        if isShowingAllTransactions || isSearching {
            return allFilteredTransactions
        }
        return Array(allFilteredTransactions.prefix(12))
    }

    private var activityHeaderTitle: String {
        if isSearching {
            return "Kết quả tìm kiếm (\(allFilteredTransactions.count))"
        }
        var parts: [String] = []
        if let wallet = selectedWalletFilter {
            parts.append(wallet.displayName)
        }
        if let tagName = selectedTagFilterName {
            parts.append(tagName)
        }
        if !parts.isEmpty {
            return "Lọc: \(parts.joined(separator: " · "))"
        }
        return "Giao dịch \(coordinator.selectedMonthLabel.lowercased())"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutcomeTheme.Layout.sectionSpacing) {
                    if !isSearching {
                        heroHeader

                        if let discrepancy = coordinator.mbbankDiscrepancy,
                           dismissedDiscrepancyTimestamp != discrepancy.reportedAt {
                            mbbankDiscrepancyBanner(discrepancy)
                        }

                        dualWalletRow

                        SpendingAllocationCard(
                            monthlyExpense: coordinator.summary.monthlyExpense,
                            monthlyIncome: coordinator.summary.monthlyIncome,
                            expenseByTag: coordinator.summary.expenseByTag,
                            monthLabel: coordinator.selectedMonthLabel,
                            canGoNextMonth: coordinator.canGoToNextMonth,
                            hideBalance: hideBalances,
                            selectedTagName: selectedTagFilterName,
                            onPreviousMonth: {
                                selectedTagFilterName = nil
                                isShowingAllTransactions = false
                                coordinator.goToPreviousMonth()
                            },
                            onNextMonth: {
                                selectedTagFilterName = nil
                                isShowingAllTransactions = false
                                coordinator.goToNextMonth()
                            },
                            onSelectTagName: { tagName in
                                if selectedTagFilterName == tagName {
                                    selectedTagFilterName = nil
                                } else {
                                    selectedTagFilterName = tagName
                                }
                                isShowingAllTransactions = false
                            }
                        )
                    }

                    recentActivitySection
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable {
                coordinator.refresh()
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Tổng quan")
            .searchable(text: $searchText, prompt: "Tìm nội dung, ghi chú, tag…")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    privacyToggleButton
                }
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

                Text(hideBalances ? "••••••••" : VNDFormatter.format(coordinator.summary.totalBalance))
                    .font(.system(.largeTitle, design: .rounded))
                    .bold()
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .accessibilityLabel(
                        hideBalances
                            ? "Tổng tài sản đang ẩn"
                            : "Tổng tài sản \(VNDFormatter.format(coordinator.summary.totalBalance))"
                    )
            }

            Spacer(minLength: 8)

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
                .fixedSize()
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
                WalletBentoTile(wallet: wallet, hideBalance: hideBalances) {
                    if selectedWalletFilter == wallet.id {
                        selectedWalletFilter = nil
                    } else {
                        selectedWalletFilter = wallet.id
                    }
                    isShowingAllTransactions = false
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
                Text(activityHeaderTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                if hasActiveFilter {
                    Button("Xóa lọc") {
                        selectedWalletFilter = nil
                        selectedTagFilterName = nil
                        isShowingAllTransactions = false
                    }
                    .font(.footnote.bold())
                    .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                }
            }

            if visibleTransactions.isEmpty {
                if isSearching {
                    ContentUnavailableView.search(text: trimmedSearch)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    ContentUnavailableView(
                        hasActiveFilter ? "Không có giao dịch khớp bộ lọc" : "Chưa có giao dịch",
                        systemImage: hasActiveFilter ? "line.3.horizontal.decrease.circle" : "tray",
                        description: Text(
                            hasActiveFilter
                                ? "Thử bỏ lọc ví hoặc tag để xem toàn bộ giao dịch trong tháng."
                                : "Thông báo MBBank/MoMo từ Shortcuts hoặc giao dịch nhập tay sẽ hiện tại đây."
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(visibleTransactions.enumerated(), id: \.element.id) { idx, tx in
                        if idx > 0 {
                            Divider()
                                .padding(.leading, 50)
                        }
                        Button {
                            coordinator.activeTaggingTransaction = tx
                        } label: {
                            TransactionRow(
                                item: tx,
                                tagName: coordinator.tagName(for: tx.tagId)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(
                                tx.txType == .internalTransfer ? "Đổi thành Chi tiêu & gắn tag" : "Sửa & chọn tag",
                                systemImage: "tag"
                            ) {
                                coordinator.activeTaggingTransaction = tx
                            }
                            Button("Xóa giao dịch", systemImage: "trash", role: .destructive) {
                                pendingDeletion = tx
                            }
                        }
                    }
                }

                if !isSearching && allFilteredTransactions.count > 12 {
                    Button {
                        isShowingAllTransactions.toggle()
                    } label: {
                        Text(isShowingAllTransactions ? "Thu gọn" : "Xem tất cả (\(allFilteredTransactions.count))")
                            .font(.footnote.bold())
                            .foregroundStyle(OutcomeTheme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }

    private func mbbankDiscrepancyBanner(_ discrepancy: MBBankBalanceDiscrepancy) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(OutcomeTheme.Colors.pending)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("MBBank lệch \(VNDFormatter.formatDelta(discrepancy.delta)) so với ngân hàng")
                    .font(.footnote.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text(
                    hideBalances
                        ? "Có thể vừa sót 1 thông báo. Chạm Đối soát để khớp lại."
                        : "Ngân hàng báo \(VNDFormatter.format(discrepancy.reportedBalance)) · Có thể sót 1 thông báo."
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button("Đối soát") {
                coordinator.selectedTab = .wallets
            }
            .font(.footnote.bold())
            .foregroundStyle(OutcomeTheme.Colors.accent)
            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)

            Button("Ẩn cảnh báo", systemImage: "xmark") {
                dismissedDiscrepancyTimestamp = discrepancy.reportedAt
            }
            .labelStyle(.iconOnly)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(minWidth: OutcomeTheme.Layout.minTouchTarget, minHeight: OutcomeTheme.Layout.minTouchTarget)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))
    }

    private var privacyToggleButton: some View {
        Button(
            hideBalances ? "Hiện số dư" : "Ẩn số dư",
            systemImage: hideBalances ? "eye.slash" : "eye"
        ) {
            hideBalances.toggle()
        }
        .labelStyle(.iconOnly)
    }

    private var addTransactionButton: some View {
        Button("Thêm giao dịch", systemImage: "plus") {
            coordinator.isPresentingManualEntry = true
        }
        .labelStyle(.iconOnly)
        .tint(OutcomeTheme.Colors.accent)
        .modifier(GlassProminentButtonModifier())
    }
}

private struct GlassProminentButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content
        }
    }
}

#Preview {
    OverviewView()
        .environment(AppCoordinator.preview())
}

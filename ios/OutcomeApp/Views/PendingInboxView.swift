import OutcomeCore
import SwiftUI

struct PendingInboxView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @State private var pendingDeletion: OutcomeCore.Transaction?

    private var recentInternalTransfers: [OutcomeCore.Transaction] {
        coordinator.allTransactions
            .filter { $0.txType == .internalTransfer }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutcomeTheme.Layout.sectionSpacing) {
                    if coordinator.pendingTransactions.isEmpty {
                        ContentUnavailableView(
                            "Không có giao dịch chờ",
                            systemImage: "checkmark.circle",
                            description: Text("Mọi biến động số dư từ MBBank và MoMo đã được phân loại.")
                        )
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .background(
                            OutcomeTheme.Colors.card,
                            in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius)
                        )
                    } else {
                        VStack(spacing: 10) {
                            ForEach(coordinator.pendingTransactions) { tx in
                                Button {
                                    coordinator.activeTaggingTransaction = tx
                                } label: {
                                    pendingCard(for: tx)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Chọn tag & ghi chú", systemImage: "tag") {
                                        coordinator.activeTaggingTransaction = tx
                                    }
                                    Button("Xóa giao dịch", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = tx
                                    }
                                }
                            }
                        }
                    }

                    if !recentInternalTransfers.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tự khớp chuyển nội bộ")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            VStack(spacing: 10) {
                                ForEach(recentInternalTransfers) { tx in
                                    TransactionRow(item: tx, tagName: nil)
                                        .padding(14)
                                        .background(
                                            OutcomeTheme.Colors.card.opacity(0.75),
                                            in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius)
                                        )
                                        .contextMenu {
                                            Button("Xóa giao dịch", systemImage: "trash", role: .destructive) {
                                                pendingDeletion = tx
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable {
                coordinator.refresh()
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Chờ duyệt")
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

    private func pendingCard(for tx: OutcomeCore.Transaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: OutcomeTheme.symbol(for: tx.sourceWalletId))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(
                    tx.direction == .in ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.accent,
                    in: .circle
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.description)
                    .font(.body.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(tx.sourceWalletId.displayName) · \(tx.occurredAt, format: .dateTime.day().month().hour().minute())")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(VNDFormatter.formatSigned(tx.amount, direction: tx.direction))
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(tx.direction == .in ? OutcomeTheme.Colors.income : .primary)
                    .lineLimit(1)

                Text("Chạm chọn")
                    .font(.footnote.bold())
                    .foregroundStyle(OutcomeTheme.Colors.accent)
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }
}

#Preview {
    PendingInboxView()
        .environment(AppCoordinator.preview())
}

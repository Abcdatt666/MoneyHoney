import Foundation
import Observation
import OutcomeCore

enum OutcomeTab: Hashable {
    case overview
    case pending
    case wallets
}

@Observable
@MainActor
final class AppCoordinator {
    private let engine: ExpenseEngine

    var selectedTab: OutcomeTab = .overview
    var summary: DashboardSummary
    var wallets: [WalletAccount] = []
    var tags: [Tag] = []
    var pendingTransactions: [Transaction] = []
    var allTransactions: [Transaction] = []
    var reconciliations: [BalanceReconciliation] = []

    var activeTaggingTransaction: Transaction?
    var isPresentingManualEntry: Bool = false
    var errorMessage: String?

    init(store: ExpenseStore? = nil) {
        let resolvedStore = store ?? SwiftDataExpenseStore()
        let engine = ExpenseEngine(store: resolvedStore)
        self.engine = engine
        self.summary = engine.getDashboardSummary()
        refresh()
    }

    static func preview() -> AppCoordinator {
        let store = InMemoryExpenseStore()
        let engine = ExpenseEngine(store: store)
        let now = Date()
        _ = try? engine.reconcileBalances([.mbbank: 12_500_000, .momo: 1_100_000], now: now)
        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -150,000VND 20/11/26 15:50|SD: 12,350,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321",
            receivedAt: now
        ))
        _ = engine.ingestNotification(RawNotification(
            sourceApp: .momo,
            title: "Nhận tiền thành công",
            body: "Trần Minh Quân đã chuyển cho bạn 120.000đ. Lời nhắn: Tiền cafe sáng",
            receivedAt: now.addingTimeInterval(-1200)
        ))
        _ = engine.ingestNotification(RawNotification(
            sourceApp: .mbbank,
            title: "Biến động số dư",
            body: "TK 0901234567|GD: -500,000VND 20/11/26 09:00|SD: 11,850,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 777888",
            receivedAt: now.addingTimeInterval(-7200)
        ))
        _ = try? engine.addManualTransaction(
            walletId: .momo,
            direction: .out,
            amount: 45_000,
            tagId: "tag_an_uong",
            description: "Cơm trưa văn phòng",
            occurredAt: now.addingTimeInterval(-3600)
        )
        return AppCoordinator(store: store)
    }

    func refresh(now: Date = Date()) {
        summary = engine.getDashboardSummary(now: now)
        wallets = engine.listWallets()
        tags = engine.listTags()
        pendingTransactions = engine.listPendingTransactions()
        allTransactions = engine.listAllTransactions()
        reconciliations = engine.listReconciliations()
    }

    func confirmTransaction(txId: String, tagId: String, note: String) {
        do {
            try engine.confirmTransaction(txId: txId, tagId: tagId, note: note)
            activeTaggingTransaction = nil
            refresh()
        } catch {
            errorMessage = "Không thể lưu phân loại giao dịch."
        }
    }

    func addManualTransaction(
        walletId: WalletId,
        direction: Direction,
        amount: Int,
        tagId: String,
        description: String,
        note: String
    ) {
        do {
            try engine.addManualTransaction(
                walletId: walletId,
                direction: direction,
                amount: amount,
                tagId: tagId,
                description: description,
                note: note
            )
            isPresentingManualEntry = false
            refresh()
        } catch {
            errorMessage = "Vui lòng kiểm tra lại số tiền và tag."
        }
    }

    func addCustomTag(name: String) -> Tag? {
        do {
            let tag = try engine.addCustomTag(name: name)
            refresh()
            return tag
        } catch {
            errorMessage = "Tên tag không hợp lệ hoặc đã tồn tại."
            return nil
        }
    }

    func deleteTransaction(txId: String) {
        if engine.deleteTransaction(txId: txId) {
            refresh()
        }
    }

    func reconcileBalances(mbActual: Int, momoActual: Int, note: String) {
        do {
            try engine.reconcileBalances(
                [.mbbank: mbActual, .momo: momoActual],
                note: note
            )
            refresh()
            Task {
                await ReminderScheduler.scheduleNextMonthEndReminder()
            }
        } catch {
            errorMessage = "Số dư thực tế không thể âm."
        }
    }

    func openTransactionFromNotification(txId: String) {
        refresh()
        if let tx = allTransactions.first(where: { $0.id == txId }),
           tx.txType != .internalTransfer {
            selectedTab = .pending
            activeTaggingTransaction = tx
        }
    }

    func tagName(for tagId: String?) -> String? {
        guard let tagId else { return nil }
        return tags.first(where: { $0.id == tagId })?.name
    }
}

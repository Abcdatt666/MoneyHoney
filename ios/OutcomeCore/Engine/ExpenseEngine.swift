import Foundation

/// Main orchestration facade for the offline expense tracker core logic.
@MainActor
public final class ExpenseEngine {
    public enum EngineError: Error, Equatable {
        case transactionNotFound(String)
        case cannotTagInternalTransfer
        case tagNotFound(String)
        case nonPositiveAmount
        case emptyTagName
        case duplicateTagName(String)
    }

    public let store: ExpenseStore
    public let syncMBBankReportedBalance: Bool

    public init(
        store: ExpenseStore? = nil,
        syncMBBankReportedBalance: Bool = false
    ) {
        self.store = store ?? InMemoryExpenseStore()
        self.syncMBBankReportedBalance = syncMBBankReportedBalance
    }

    public func ingestNotification(_ raw: RawNotification) -> IngestResult {
        guard let parsed = NotificationParser.parse(raw) else {
            return IngestResult(
                status: .ignored,
                reason: "Notification is promotional, OTP, or not a valid transaction."
            )
        }

        if isDuplicateNotification(raw: raw, parsed: parsed) {
            return IngestResult(
                status: .duplicate,
                reason: "Matching transaction already recorded within deduplication window."
            )
        }

        let createdAt = raw.receivedAt
        let rawText = "\(raw.title) | \(raw.body)"
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|")))

        if parsed.txType == .internalTransfer {
            let tx = Transaction(
                txType: .internalTransfer,
                sourceWalletId: parsed.sourceWalletId,
                amount: parsed.amount,
                direction: parsed.direction,
                description: parsed.description,
                occurredAt: parsed.occurredAt,
                createdAt: createdAt,
                status: .confirmed,
                targetWalletId: parsed.targetWalletId,
                isManual: false,
                traceId: parsed.traceId,
                rawNotificationText: rawText,
                reportedBalanceAfter: parsed.reportedBalanceAfter,
                confirmedAt: createdAt
            )
            try? BalanceCalculator.applyTransactionBalances(
                store: store,
                tx: tx,
                syncReportedBalance: syncMBBankReportedBalance
            )
            store.saveTransaction(tx)

            let targetCode = parsed.targetWalletId?.rawValue ?? ""
            return IngestResult(
                status: .created,
                transaction: tx,
                prompt: NotificationPrompt(
                    shouldPrompt: false,
                    transactionId: tx.id,
                    title: "Chuyển tiền nội bộ",
                    body: "\(parsed.sourceWalletId.rawValue) -> \(targetCode): \(VNDFormatter.format(tx.amount))"
                )
            )
        }

        let tx = Transaction(
            txType: parsed.txType,
            sourceWalletId: parsed.sourceWalletId,
            amount: parsed.amount,
            direction: parsed.direction,
            description: parsed.description,
            occurredAt: parsed.occurredAt,
            createdAt: createdAt,
            status: .pending,
            targetWalletId: nil,
            isManual: false,
            traceId: parsed.traceId,
            rawNotificationText: rawText,
            reportedBalanceAfter: parsed.reportedBalanceAfter
        )
        try? BalanceCalculator.applyTransactionBalances(
            store: store,
            tx: tx,
            syncReportedBalance: syncMBBankReportedBalance
        )
        store.saveTransaction(tx)

        return IngestResult(
            status: .created,
            transaction: tx,
            prompt: buildPrompt(for: tx)
        )
    }

    @discardableResult
    public func confirmTransaction(
        txId: String,
        tagId: String,
        note: String = "",
        now: Date = Date()
    ) throws -> Transaction {
        guard var tx = store.getTransaction(txId) else {
            throw EngineError.transactionNotFound(txId)
        }
        guard tx.txType != .internalTransfer else {
            throw EngineError.cannotTagInternalTransfer
        }
        guard let tag = store.getTag(tagId) else {
            throw EngineError.tagNotFound(tagId)
        }

        tx.tagId = tag.id
        tx.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        tx.status = .confirmed
        tx.confirmedAt = now
        store.saveTransaction(tx)
        return tx
    }

    @discardableResult
    public func addManualTransaction(
        walletId: WalletId,
        direction: Direction,
        amount: Int,
        tagId: String,
        description: String = "",
        note: String = "",
        occurredAt: Date = Date()
    ) throws -> Transaction {
        guard amount > 0 else {
            throw EngineError.nonPositiveAmount
        }
        guard let tag = store.getTag(tagId) else {
            throw EngineError.tagNotFound(tagId)
        }

        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let tx = Transaction(
            txType: direction == .out ? .expense : .income,
            sourceWalletId: walletId,
            amount: amount,
            direction: direction,
            description: cleanDescription.isEmpty ? "Nhập tay" : cleanDescription,
            occurredAt: occurredAt,
            createdAt: occurredAt,
            status: .confirmed,
            tagId: tag.id,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            isManual: true,
            confirmedAt: occurredAt
        )
        try BalanceCalculator.applyTransactionBalances(
            store: store,
            tx: tx,
            syncReportedBalance: false
        )
        store.saveTransaction(tx)
        return tx
    }

    @discardableResult
    public func deleteTransaction(txId: String) -> Bool {
        guard let tx = store.getTransaction(txId) else {
            return false
        }
        try? BalanceCalculator.reverseTransactionBalances(store: store, tx: tx)
        return store.deleteTransaction(txId)
    }

    @discardableResult
    public func addCustomTag(name: String, now: Date = Date()) throws -> Tag {
        let cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        guard !cleaned.isEmpty else {
            throw EngineError.emptyTagName
        }

        let existingTags = store.listTags()
        if let existing = existingTags.first(where: {
            $0.name.compare(cleaned, options: .caseInsensitive, locale: .current) == .orderedSame
        }) {
            throw EngineError.duplicateTagName(existing.name)
        }

        let nextOrder = (existingTags.map(\.sortOrder).max() ?? -1) + 1
        let shortId = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
        let tag = Tag(
            id: "tag_custom_\(shortId)",
            name: cleaned,
            isDefault: false,
            sortOrder: nextOrder,
            createdAt: now
        )
        store.saveTag(tag)
        return tag
    }

    @discardableResult
    public func reconcileBalances(
        _ actualBalances: [WalletId: Int],
        note: String = "",
        now: Date = Date()
    ) throws -> [BalanceReconciliation] {
        try BalanceCalculator.reconcileWalletBalances(
            store: store,
            actualBalances: actualBalances,
            reconciledAt: now,
            note: note
        )
    }

    public func listPendingTransactions() -> [Transaction] {
        store.listTransactions().filter { $0.status == .pending }
    }

    public func listAllTransactions() -> [Transaction] {
        store.listTransactions()
    }

    public func listWallets() -> [WalletAccount] {
        store.listWallets()
    }

    public func listTags() -> [Tag] {
        store.listTags()
    }

    public func listReconciliations() -> [BalanceReconciliation] {
        store.listReconciliations()
    }

    public func getDashboardSummary(
        year: Int? = nil,
        month: Int? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DashboardSummary {
        let targetYear = year ?? calendar.component(.year, from: now)
        let targetMonth = month ?? calendar.component(.month, from: now)

        let mb = store.getWallet(.mbbank)
        let momo = store.getWallet(.momo)
        let allTransactions = store.listTransactions()

        let pendingCount = allTransactions.reduce(into: 0) { count, tx in
            if tx.status == .pending { count += 1 }
        }

        var monthlyExpense = 0
        var monthlyIncome = 0
        var expenseByTag: [String: Int] = [:]
        let tagsById = Dictionary(uniqueKeysWithValues: store.listTags().map { ($0.id, $0.name) })

        for tx in allTransactions {
            let txYear = calendar.component(.year, from: tx.occurredAt)
            let txMonth = calendar.component(.month, from: tx.occurredAt)
            guard txYear == targetYear, txMonth == targetMonth else { continue }

            switch tx.txType {
            case .expense:
                monthlyExpense += tx.amount
                let label = tx.tagId.flatMap { tagsById[$0] } ?? "Chưa phân loại"
                expenseByTag[label, default: 0] += tx.amount
            case .income:
                monthlyIncome += tx.amount
            case .internalTransfer:
                break
            }
        }

        return DashboardSummary(
            mbbankBalance: mb.balance,
            momoBalance: momo.balance,
            totalBalance: mb.balance + momo.balance,
            pendingCount: pendingCount,
            monthlyExpense: monthlyExpense,
            monthlyIncome: monthlyIncome,
            expenseByTag: expenseByTag,
            nextReconciliationReminder: BalanceCalculator.getNextReconciliationReminder(
                now: now,
                calendar: calendar
            )
        )
    }

    // MARK: - Deduplication & Prompting

    private func isDuplicateNotification(raw: RawNotification, parsed: ParsedTransaction) -> Bool {
        let rawText = "\(raw.title) | \(raw.body)"
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|")))

        for existing in store.listTransactions() {
            if let traceId = parsed.traceId,
               existing.traceId == traceId,
               existing.sourceWalletId == parsed.sourceWalletId {
                return true
            }

            let deltaSeconds = abs(parsed.occurredAt.timeIntervalSince(existing.occurredAt))

            if deltaSeconds <= 10,
               existing.sourceWalletId == parsed.sourceWalletId,
               existing.amount == parsed.amount,
               existing.direction == parsed.direction,
               existing.rawNotificationText == rawText {
                return true
            }

            if existing.txType == .internalTransfer,
               deltaSeconds <= 120,
               existing.amount == parsed.amount,
               raw.sourceApp == .momo {
                if (existing.description.contains("MOMO-CASHIN") && parsed.direction == .in) ||
                   (existing.description.contains("MOMO-CASHOUT") && parsed.direction == .out) {
                    return true
                }
            }
        }

        return false
    }

    private func buildPrompt(for tx: Transaction) -> NotificationPrompt {
        let sourceLabel = tx.sourceWalletId == .mbbank ? "MBBank" : "MoMo"
        let sign = tx.direction == .out ? "-" : "+"
        let verb = tx.direction == .out ? "chi" : "nhận"
        let descPart: String
        if !tx.description.isEmpty, tx.description != "Không rõ nội dung" {
            descPart = " (\(tx.description))"
        } else {
            descPart = ""
        }

        return NotificationPrompt(
            shouldPrompt: true,
            transactionId: tx.id,
            title: "\(sourceLabel) \(sign)\(VNDFormatter.format(tx.amount))",
            body: "Bạn vừa \(verb) \(VNDFormatter.format(tx.amount))\(descPart). Chạm để chọn tag & ghi chú."
        )
    }
}

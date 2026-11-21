import Foundation

/// Discrepancy between MBBank's latest `SD:` balance and Outcome's computed MBBank balance.
public struct MBBankBalanceDiscrepancy: Equatable, Sendable {
    public let reportedBalance: Int
    public let appBalance: Int
    public let delta: Int
    public let reportedAt: Date

    public init(reportedBalance: Int, appBalance: Int, reportedAt: Date) {
        self.reportedBalance = reportedBalance
        self.appBalance = appBalance
        self.delta = reportedBalance - appBalance
        self.reportedAt = reportedAt
    }
}

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

    private static let crossAppWindowSeconds: TimeInterval = 120
    private static let sameBankSelfTransferWindowSeconds: TimeInterval = 30
    private static let crossAppMergeDelimiter = " || "

    private static let mbAccountRegex = try! NSRegularExpression(
        pattern: #"\bTK\s+(?<acct>[A-Z0-9x*]+)"#,
        options: [.caseInsensitive]
    )

    private static let mbbankMoMoGatewayMarkers: [String] = [
        "MOMO",
        "M_SERVICE",
        "MSERVICE",
        "M SERVICE",
        "VI MOMO",
        "AP-CASHIN",
        "AP CASHIN",
        "BANK2WALLET",
        "NAPAS",
    ]

    private static let momoLinkedPaymentMarkers: [String] = [
        "THANH TOAN",
        "CHO DICH VU",
        "LIEN KET",
        "NGAN HANG",
        "MBBANK",
        "MB BANK",
        "APPLE",
        "GRAB",
        "GOOGLE",
        "SPOTIFY",
        "NETFLIX",
        "YOUTUBE",
        "ICLOUD",
        "APP STORE",
    ]

    private static let genericBankDescMarkers: [String] = [
        "MOMO",
        "M_SERVICE",
        "MSERVICE",
        "M SERVICE",
        "THANH TOAN",
        "TT ",
        "KHONG RO NOI DUNG",
    ]

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

        // Reconcile cross-app linked-bank expense (e.g., Apple Services / Grab / WiFi bill
        // paid through MoMo using linked MBBank account) regardless of arrival order or
        // whether MBBank labels the debit as MOMO-CASHIN.
        if let reconciled = reconcileCrossAppLinkedExpense(raw: raw, parsed: parsed, rawText: rawText) {
            return reconciled
        }

        // Detect self-transfer between two different MBBank accounts of the same user
        // (e.g., TK A -1,000,000 and TK B +1,000,000 within 30s) so monthly stats aren't inflated.
        if let selfTransfer = reconcileSameBankSelfTransfer(raw: raw, parsed: parsed, rawText: rawText) {
            return selfTransfer
        }

        let cleanLocationName = normalizedLocationName(raw.locationName)

        if parsed.txType == .internalTransfer {
            // Self-heal if MoMo fired its wallet-side notification a few seconds
            // before MBBank's authoritative MOMO-CASHIN / MOMO-CASHOUT notification.
            removePrematureMoMoTransferLeg(raw: raw, parsed: parsed)

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
                confirmedAt: createdAt,
                locationName: cleanLocationName,
                latitude: raw.latitude,
                longitude: raw.longitude
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
            reportedBalanceAfter: parsed.reportedBalanceAfter,
            locationName: cleanLocationName,
            latitude: raw.latitude,
            longitude: raw.longitude
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

    /// Update any editable field of a transaction (including converting a
    /// `MOMO-CASHIN` / `MOMO-CASHOUT` internal transfer into a regular expense or
    /// income) while keeping both wallet balances mathematically exact.
    @discardableResult
    public func updateTransaction(
        txId: String,
        walletId: WalletId,
        direction: Direction,
        amount: Int,
        tagId: String,
        description: String,
        note: String,
        occurredAt: Date,
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        clearLocation: Bool = false,
        now: Date = Date()
    ) throws -> Transaction {
        guard let existing = store.getTransaction(txId) else {
            throw EngineError.transactionNotFound(txId)
        }
        guard amount > 0 else {
            throw EngineError.nonPositiveAmount
        }
        guard let tag = store.getTag(tagId) else {
            throw EngineError.tagNotFound(tagId)
        }

        try BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)

        var updated = existing
        updated.sourceWalletId = walletId
        updated.targetWalletId = nil
        updated.direction = direction
        updated.txType = direction == .out ? .expense : .income
        updated.amount = amount
        let cleanDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = cleanDesc.isEmpty ? existing.description : cleanDesc
        updated.tagId = tag.id
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.occurredAt = occurredAt
        updated.status = .confirmed
        updated.confirmedAt = existing.confirmedAt ?? now

        if clearLocation {
            updated.locationName = nil
            updated.latitude = nil
            updated.longitude = nil
        } else {
            if let locationName {
                updated.locationName = normalizedLocationName(locationName)
            }
            if let latitude {
                updated.latitude = latitude
            }
            if let longitude {
                updated.longitude = longitude
            }
        }

        try BalanceCalculator.applyTransactionBalances(
            store: store,
            tx: updated,
            syncReportedBalance: false
        )
        store.saveTransaction(updated)
        return updated
    }

    public func detectMBBankDiscrepancy() -> MBBankBalanceDiscrepancy? {
        let mb = store.getWallet(.mbbank)
        let mbTransactions = store.listTransactions().filter {
            $0.sourceWalletId == .mbbank || $0.targetWalletId == .mbbank
        }
        guard let newestMbTx = mbTransactions.first,
              let reported = newestMbTx.reportedBalanceAfter else {
            return nil
        }
        // If this was a self-transfer between two MBBank accounts, `SD:` belongs to only
        // one sub-account rather than total MBBank balance, so skip false discrepancy alerts.
        if newestMbTx.txType == .internalTransfer && newestMbTx.targetWalletId == .mbbank {
            return nil
        }
        if let reconciledAt = mb.lastReconciledAt, reconciledAt >= newestMbTx.occurredAt {
            return nil
        }
        guard reported != mb.balance else {
            return nil
        }
        return MBBankBalanceDiscrepancy(
            reportedBalance: reported,
            appBalance: mb.balance,
            reportedAt: newestMbTx.occurredAt
        )
    }

    public func suggestTags(for tx: Transaction, limit: Int = 3) -> [Tag] {
        TagSuggester.suggest(
            for: tx,
            history: store.listTransactions(),
            availableTags: store.listTags(),
            limit: limit
        )
    }

    public func exportBackupJSON(now: Date = Date()) throws -> Data {
        try OutcomeBackupCodec.encodeJSON(from: store, now: now)
    }

    public func previewBackupJSON(_ data: Data) throws -> OutcomeBackupSnapshot {
        try OutcomeBackupCodec.decodeJSON(data)
    }

    public func restoreBackup(_ snapshot: OutcomeBackupSnapshot) {
        OutcomeBackupCodec.restore(snapshot, into: store)
    }

    public func exportCSV() -> String {
        OutcomeBackupCodec.encodeCSV(from: store)
    }

    @discardableResult
    public func addManualTransaction(
        walletId: WalletId,
        direction: Direction,
        amount: Int,
        tagId: String,
        description: String = "",
        note: String = "",
        occurredAt: Date = Date(),
        locationName: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
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
            confirmedAt: occurredAt,
            locationName: normalizedLocationName(locationName),
            latitude: latitude,
            longitude: longitude
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

    // MARK: - Deduplication, Cross-App Merging & Prompting

    private func normalizedLocationName(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func extractMBAccountNumber(from text: String?) -> String? {
        guard let text else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = Self.mbAccountRegex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let nsRange = match.range(withName: "acct")
        guard nsRange.location != NSNotFound, let swiftRange = Range(nsRange, in: text) else {
            return nil
        }
        return String(text[swiftRange]).uppercased()
    }

    private func reconcileSameBankSelfTransfer(
        raw: RawNotification,
        parsed: ParsedTransaction,
        rawText: String
    ) -> IngestResult? {
        guard raw.sourceApp == .mbbank,
              parsed.txType == .expense || parsed.txType == .income,
              let incomingAcct = extractMBAccountNumber(from: rawText) else {
            return nil
        }

        for existing in store.listTransactions() {
            if existing.isManual { continue }
            guard existing.sourceWalletId == .mbbank,
                  existing.txType == .expense || existing.txType == .income,
                  existing.direction != parsed.direction,
                  existing.amount == parsed.amount else {
                continue
            }
            if let existingRaw = existing.rawNotificationText,
               existingRaw.contains(Self.crossAppMergeDelimiter) {
                continue
            }
            let occurredDelta = abs(parsed.occurredAt.timeIntervalSince(existing.occurredAt))
            let receivedDelta = abs(raw.receivedAt.timeIntervalSince(existing.createdAt))
            guard min(occurredDelta, receivedDelta) <= Self.sameBankSelfTransferWindowSeconds else {
                continue
            }
            guard let existingAcct = extractMBAccountNumber(from: existing.rawNotificationText),
                  existingAcct != incomingAcct else {
                continue
            }

            try? BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)
            var updated = existing
            updated.txType = .internalTransfer
            updated.sourceWalletId = .mbbank
            updated.targetWalletId = .mbbank
            updated.direction = .out
            updated.status = .confirmed
            updated.confirmedAt = raw.receivedAt
            updated.description = "Chuyển giữa 2 TK MBBank"
            updated.rawNotificationText = [existing.rawNotificationText, rawText]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: Self.crossAppMergeDelimiter)
            store.saveTransaction(updated)

            return IngestResult(
                status: .duplicate,
                transaction: updated,
                reason: "Merged opposite-direction MBBank notifications across two own accounts into an internal self-transfer."
            )
        }
        return nil
    }

    private static func normalizedUpper(_ text: String) -> String {
        text
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "D")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .uppercased()
    }

    private func isWithinCrossAppWindow(
        existing: Transaction,
        raw: RawNotification,
        parsed: ParsedTransaction
    ) -> Bool {
        let occurredDelta = abs(parsed.occurredAt.timeIntervalSince(existing.occurredAt))
        let receivedDelta = abs(raw.receivedAt.timeIntervalSince(existing.createdAt))
        return min(occurredDelta, receivedDelta) <= Self.crossAppWindowSeconds
    }

    private func matchesLinkedBankPayment(mbbankText: String, momoText: String) -> Bool {
        let mbUpper = Self.normalizedUpper(mbbankText)
        let momoUpper = Self.normalizedUpper(momoText)
        return Self.mbbankMoMoGatewayMarkers.contains(where: { mbUpper.contains($0) }) ||
            Self.momoLinkedPaymentMarkers.contains(where: { momoUpper.contains($0) })
    }

    private func shouldUpgradeBankDescription(
        current: String,
        with momoDescription: String
    ) -> Bool {
        guard !momoDescription.isEmpty, momoDescription != "Không rõ nội dung" else {
            return false
        }
        if current.isEmpty || current == "Không rõ nội dung" {
            return true
        }
        let currentUpper = Self.normalizedUpper(current)
        return Self.genericBankDescMarkers.contains(where: { currentUpper.contains($0) })
    }

    private func reconcileCrossAppLinkedExpense(
        raw: RawNotification,
        parsed: ParsedTransaction,
        rawText: String
    ) -> IngestResult? {
        // Case A: Incoming MBBank MOMO-CASHIN arriving right after a MoMo bill payment
        // expense of the exact same amount -> re-home the MoMo expense to MBBank
        // instead of creating a fake internal transfer.
        if parsed.txType == .internalTransfer,
           parsed.sourceWalletId == .mbbank,
           parsed.targetWalletId == .momo {
            for existing in store.listTransactions() {
                if existing.isManual { continue }
                guard existing.txType == .expense,
                      existing.direction == .out,
                      existing.sourceWalletId == .momo,
                      existing.amount == parsed.amount else {
                    continue
                }
                if let existingRaw = existing.rawNotificationText,
                   existingRaw.contains(Self.crossAppMergeDelimiter) {
                    continue
                }
                guard isWithinCrossAppWindow(existing: existing, raw: raw, parsed: parsed) else {
                    continue
                }

                try? BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)
                var updated = existing
                updated.sourceWalletId = .mbbank
                updated.targetWalletId = nil
                if let traceId = parsed.traceId {
                    updated.traceId = traceId
                }
                if let reportedBalance = parsed.reportedBalanceAfter {
                    updated.reportedBalanceAfter = reportedBalance
                }
                updated.occurredAt = parsed.occurredAt
                updated.rawNotificationText = [existing.rawNotificationText, rawText]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: Self.crossAppMergeDelimiter)

                try? BalanceCalculator.applyTransactionBalances(
                    store: store,
                    tx: updated,
                    syncReportedBalance: syncMBBankReportedBalance
                )
                store.saveTransaction(updated)
                return IngestResult(
                    status: .duplicate,
                    transaction: updated,
                    reason: "Re-homed MoMo bill payment to MBBank from matching MOMO-CASHIN."
                )
            }
            return nil
        }

        guard parsed.txType == .expense, parsed.direction == .out else {
            return nil
        }

        for existing in store.listTransactions() {
            if existing.isManual { continue }
            guard existing.amount == parsed.amount else { continue }
            if let existingRaw = existing.rawNotificationText,
               existingRaw.contains(Self.crossAppMergeDelimiter) {
                continue
            }
            guard isWithinCrossAppWindow(existing: existing, raw: raw, parsed: parsed) else {
                continue
            }

            // Case B: MBBank MOMO-CASHIN arrived first (silently logged as internal transfer),
            // then MoMo bill payment expense arrived within 120s -> convert the internal
            // transfer into a single MBBank expense with MoMo's merchant name and prompt user!
            if parsed.sourceWalletId == .momo,
               existing.txType == .internalTransfer,
               existing.sourceWalletId == .mbbank,
               existing.targetWalletId == .momo {
                try? BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)
                var updated = existing
                updated.txType = .expense
                updated.sourceWalletId = .mbbank
                updated.targetWalletId = nil
                updated.direction = .out
                updated.status = .pending
                updated.confirmedAt = nil
                if !parsed.description.isEmpty, parsed.description != "Không rõ nội dung" {
                    updated.description = parsed.description
                }
                updated.rawNotificationText = [existing.rawNotificationText, rawText]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: Self.crossAppMergeDelimiter)

                try? BalanceCalculator.applyTransactionBalances(
                    store: store,
                    tx: updated,
                    syncReportedBalance: syncMBBankReportedBalance
                )
                store.saveTransaction(updated)
                return IngestResult(
                    status: .created,
                    transaction: updated,
                    prompt: buildPrompt(for: updated),
                    reason: "Converted MOMO-CASHIN internal transfer into MBBank expense using MoMo payment notification."
                )
            }

            guard existing.txType == .expense,
                  existing.direction == .out,
                  existing.sourceWalletId != parsed.sourceWalletId else {
                continue
            }

            // Order 1: MBBank arrived first, MoMo arrived second -> keep MBBank deduction,
            // leave Ví MoMo untouched, and enrich description with MoMo's merchant name.
            if existing.sourceWalletId == .mbbank, parsed.sourceWalletId == .momo {
                let mbText = "\(existing.description) \(existing.rawNotificationText ?? "")"
                let momoText = "\(parsed.description) \(rawText)"
                guard matchesLinkedBankPayment(mbbankText: mbText, momoText: momoText) else {
                    continue
                }

                var updated = existing
                if shouldUpgradeBankDescription(current: updated.description, with: parsed.description) {
                    updated.description = parsed.description
                }
                updated.rawNotificationText = [existing.rawNotificationText, rawText]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: Self.crossAppMergeDelimiter)
                store.saveTransaction(updated)
                return IngestResult(
                    status: .duplicate,
                    transaction: updated,
                    reason: "Merged linked MoMo payment into existing MBBank expense."
                )
            }

            // Order 2: MoMo arrived first, MBBank arrived second -> refund Ví MoMo,
            // re-home the transaction to MBBank, apply MBBank deduction, keep MoMo's
            // clean merchant description and any tag/note the user already picked.
            if existing.sourceWalletId == .momo, parsed.sourceWalletId == .mbbank {
                let mbText = "\(parsed.description) \(rawText)"
                let momoText = "\(existing.description) \(existing.rawNotificationText ?? "")"
                guard matchesLinkedBankPayment(mbbankText: mbText, momoText: momoText) else {
                    continue
                }

                try? BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)
                var updated = existing
                updated.sourceWalletId = .mbbank
                if let traceId = parsed.traceId {
                    updated.traceId = traceId
                }
                if let reportedBalance = parsed.reportedBalanceAfter {
                    updated.reportedBalanceAfter = reportedBalance
                }
                updated.occurredAt = parsed.occurredAt
                if (updated.description.isEmpty || updated.description == "Không rõ nội dung"),
                   !parsed.description.isEmpty {
                    updated.description = parsed.description
                }
                updated.rawNotificationText = [existing.rawNotificationText, rawText]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: Self.crossAppMergeDelimiter)

                try? BalanceCalculator.applyTransactionBalances(
                    store: store,
                    tx: updated,
                    syncReportedBalance: syncMBBankReportedBalance
                )
                store.saveTransaction(updated)
                return IngestResult(
                    status: .duplicate,
                    transaction: updated,
                    reason: "Re-homed linked MoMo expense to MBBank."
                )
            }
        }

        return nil
    }

    private func removePrematureMoMoTransferLeg(
        raw: RawNotification,
        parsed: ParsedTransaction
    ) {
        guard parsed.txType == .internalTransfer else { return }
        let isCashIn = parsed.description.contains("MOMO-CASHIN")
        let isCashOut = parsed.description.contains("MOMO-CASHOUT")
        guard isCashIn || isCashOut else { return }

        for existing in store.listTransactions() {
            if existing.isManual || existing.sourceWalletId != .momo { continue }
            guard existing.amount == parsed.amount,
                  isWithinCrossAppWindow(existing: existing, raw: raw, parsed: parsed) else {
                continue
            }
            if (isCashIn && existing.txType == .income && existing.direction == .in) ||
               (isCashOut && existing.txType == .expense && existing.direction == .out) {
                try? BalanceCalculator.reverseTransactionBalances(store: store, tx: existing)
                _ = store.deleteTransaction(existing.id)
                return
            }
        }
    }

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
               isWithinCrossAppWindow(existing: existing, raw: raw, parsed: parsed),
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

import Foundation
import OutcomeCore
import SwiftData

@Model
final class WalletRecord {
    @Attribute(.unique) var idRaw: String
    var name: String
    var balance: Int
    var lastReconciledBalance: Int
    var lastReconciledAt: Date?

    init(
        idRaw: String,
        name: String,
        balance: Int = 0,
        lastReconciledBalance: Int = 0,
        lastReconciledAt: Date? = nil
    ) {
        self.idRaw = idRaw
        self.name = name
        self.balance = balance
        self.lastReconciledBalance = lastReconciledBalance
        self.lastReconciledAt = lastReconciledAt
    }

    func toDomain() -> WalletAccount {
        WalletAccount(
            id: WalletId(rawValue: idRaw) ?? .mbbank,
            name: name,
            balance: balance,
            lastReconciledBalance: lastReconciledBalance,
            lastReconciledAt: lastReconciledAt
        )
    }
}

@Model
final class TagRecord {
    @Attribute(.unique) var id: String
    var name: String
    var isDefault: Bool
    var sortOrder: Int
    var createdAt: Date

    init(
        id: String,
        name: String,
        isDefault: Bool,
        sortOrder: Int,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    func toDomain() -> Tag {
        Tag(
            id: id,
            name: name,
            isDefault: isDefault,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

@Model
final class TransactionRecord {
    @Attribute(.unique) var id: String
    var txTypeRaw: String
    var sourceWalletIdRaw: String
    var targetWalletIdRaw: String?
    var amount: Int
    var directionRaw: String
    var desc: String
    var occurredAt: Date
    var createdAt: Date
    var statusRaw: String
    var tagId: String?
    var note: String
    var isManual: Bool
    var traceId: String?
    var rawNotificationText: String?
    var reportedBalanceAfter: Int?
    var confirmedAt: Date?

    init(from tx: Transaction) {
        self.id = tx.id
        self.txTypeRaw = tx.txType.rawValue
        self.sourceWalletIdRaw = tx.sourceWalletId.rawValue
        self.targetWalletIdRaw = tx.targetWalletId?.rawValue
        self.amount = tx.amount
        self.directionRaw = tx.direction.rawValue
        self.desc = tx.description
        self.occurredAt = tx.occurredAt
        self.createdAt = tx.createdAt
        self.statusRaw = tx.status.rawValue
        self.tagId = tx.tagId
        self.note = tx.note
        self.isManual = tx.isManual
        self.traceId = tx.traceId
        self.rawNotificationText = tx.rawNotificationText
        self.reportedBalanceAfter = tx.reportedBalanceAfter
        self.confirmedAt = tx.confirmedAt
    }

    func update(from tx: Transaction) {
        txTypeRaw = tx.txType.rawValue
        sourceWalletIdRaw = tx.sourceWalletId.rawValue
        targetWalletIdRaw = tx.targetWalletId?.rawValue
        amount = tx.amount
        directionRaw = tx.direction.rawValue
        desc = tx.description
        occurredAt = tx.occurredAt
        createdAt = tx.createdAt
        statusRaw = tx.status.rawValue
        tagId = tx.tagId
        note = tx.note
        isManual = tx.isManual
        traceId = tx.traceId
        rawNotificationText = tx.rawNotificationText
        reportedBalanceAfter = tx.reportedBalanceAfter
        confirmedAt = tx.confirmedAt
    }

    func toDomain() -> Transaction {
        Transaction(
            id: id,
            txType: TransactionType(rawValue: txTypeRaw) ?? .expense,
            sourceWalletId: WalletId(rawValue: sourceWalletIdRaw) ?? .mbbank,
            amount: amount,
            direction: Direction(rawValue: directionRaw) ?? .out,
            description: desc,
            occurredAt: occurredAt,
            createdAt: createdAt,
            status: TransactionStatus(rawValue: statusRaw) ?? .pending,
            targetWalletId: targetWalletIdRaw.flatMap(WalletId.init(rawValue:)),
            tagId: tagId,
            note: note,
            isManual: isManual,
            traceId: traceId,
            rawNotificationText: rawNotificationText,
            reportedBalanceAfter: reportedBalanceAfter,
            confirmedAt: confirmedAt
        )
    }
}

@Model
final class ReconciliationRecord {
    @Attribute(.unique) var id: String
    var walletIdRaw: String
    var expectedBalance: Int
    var actualBalance: Int
    var discrepancy: Int
    var reconciledAt: Date
    var note: String

    init(from rec: BalanceReconciliation) {
        self.id = rec.id
        self.walletIdRaw = rec.walletId.rawValue
        self.expectedBalance = rec.expectedBalance
        self.actualBalance = rec.actualBalance
        self.discrepancy = rec.discrepancy
        self.reconciledAt = rec.reconciledAt
        self.note = rec.note
    }

    func toDomain() -> BalanceReconciliation {
        BalanceReconciliation(
            id: id,
            walletId: WalletId(rawValue: walletIdRaw) ?? .mbbank,
            expectedBalance: expectedBalance,
            actualBalance: actualBalance,
            discrepancy: discrepancy,
            reconciledAt: reconciledAt,
            note: note
        )
    }
}

enum OutcomeModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            WalletRecord.self,
            TagRecord.self,
            TransactionRecord.self,
            ReconciliationRecord.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Failed to initialize Outcome ModelContainer: \(error)")
        }
    }()
}

@MainActor
final class SwiftDataExpenseStore: ExpenseStore {
    private let context: ModelContext

    init(container: ModelContainer = OutcomeModelContainer.shared) {
        self.context = container.mainContext
        seedDefaultsIfNeeded()
    }

    private func seedDefaultsIfNeeded() {
        for walletId in WalletId.allCases {
            let raw = walletId.rawValue
            let descriptor = FetchDescriptor<WalletRecord>(
                predicate: #Predicate { $0.idRaw == raw }
            )
            let count = (try? context.fetchCount(descriptor)) ?? 0
            if count == 0 {
                context.insert(WalletRecord(idRaw: raw, name: walletId.displayName, balance: 0))
            }
        }

        let tagCount = (try? context.fetchCount(FetchDescriptor<TagRecord>())) ?? 0
        if tagCount == 0 {
            let now = Date()
            for (idx, spec) in DefaultTagSpecs.all.enumerated() {
                context.insert(
                    TagRecord(
                        id: spec.id,
                        name: spec.name,
                        isDefault: true,
                        sortOrder: idx,
                        createdAt: now
                    )
                )
            }
        }
        try? context.save()
    }

    func getWallet(_ walletId: WalletId) -> WalletAccount {
        let raw = walletId.rawValue
        let descriptor = FetchDescriptor<WalletRecord>(
            predicate: #Predicate { $0.idRaw == raw }
        )
        if let record = try? context.fetch(descriptor).first {
            return record.toDomain()
        }
        return WalletAccount(id: walletId, name: walletId.displayName)
    }

    func saveWallet(_ wallet: WalletAccount) {
        let raw = wallet.id.rawValue
        let descriptor = FetchDescriptor<WalletRecord>(
            predicate: #Predicate { $0.idRaw == raw }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.name = wallet.name
            existing.balance = wallet.balance
            existing.lastReconciledBalance = wallet.lastReconciledBalance
            existing.lastReconciledAt = wallet.lastReconciledAt
        } else {
            context.insert(
                WalletRecord(
                    idRaw: raw,
                    name: wallet.name,
                    balance: wallet.balance,
                    lastReconciledBalance: wallet.lastReconciledBalance,
                    lastReconciledAt: wallet.lastReconciledAt
                )
            )
        }
        try? context.save()
    }

    func listWallets() -> [WalletAccount] {
        [getWallet(.mbbank), getWallet(.momo)]
    }

    func getTag(_ tagId: String) -> Tag? {
        let descriptor = FetchDescriptor<TagRecord>(
            predicate: #Predicate { $0.id == tagId }
        )
        return (try? context.fetch(descriptor).first)?.toDomain()
    }

    func saveTag(_ tag: Tag) {
        let id = tag.id
        let descriptor = FetchDescriptor<TagRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.name = tag.name
            existing.isDefault = tag.isDefault
            existing.sortOrder = tag.sortOrder
        } else {
            context.insert(
                TagRecord(
                    id: tag.id,
                    name: tag.name,
                    isDefault: tag.isDefault,
                    sortOrder: tag.sortOrder,
                    createdAt: tag.createdAt
                )
            )
        }
        try? context.save()
    }

    func listTags() -> [Tag] {
        let descriptor = FetchDescriptor<TagRecord>(
            sortBy: [
                SortDescriptor(\TagRecord.sortOrder, order: .forward),
                SortDescriptor(\TagRecord.createdAt, order: .forward),
            ]
        )
        return ((try? context.fetch(descriptor)) ?? []).map { $0.toDomain() }
    }

    func getTransaction(_ txId: String) -> Transaction? {
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == txId }
        )
        return (try? context.fetch(descriptor).first)?.toDomain()
    }

    func saveTransaction(_ tx: Transaction) {
        let id = tx.id
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.update(from: tx)
        } else {
            context.insert(TransactionRecord(from: tx))
        }
        try? context.save()
    }

    func deleteTransaction(_ txId: String) -> Bool {
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate { $0.id == txId }
        )
        guard let existing = try? context.fetch(descriptor).first else {
            return false
        }
        context.delete(existing)
        try? context.save()
        return true
    }

    func listTransactions() -> [Transaction] {
        let descriptor = FetchDescriptor<TransactionRecord>(
            sortBy: [
                SortDescriptor(\TransactionRecord.occurredAt, order: .reverse),
                SortDescriptor(\TransactionRecord.createdAt, order: .reverse),
            ]
        )
        return ((try? context.fetch(descriptor)) ?? []).map { $0.toDomain() }
    }

    func saveReconciliation(_ rec: BalanceReconciliation) {
        context.insert(ReconciliationRecord(from: rec))
        try? context.save()
    }

    func listReconciliations() -> [BalanceReconciliation] {
        let descriptor = FetchDescriptor<ReconciliationRecord>(
            sortBy: [SortDescriptor(\ReconciliationRecord.reconciledAt, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).map { $0.toDomain() }
    }
}

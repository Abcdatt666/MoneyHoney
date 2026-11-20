import Foundation

/// Fast in-memory store for automated tests and SwiftUI previews.
@MainActor
public final class InMemoryExpenseStore: ExpenseStore {
    private var wallets: [WalletId: WalletAccount]
    private var tags: [String: Tag]
    private var transactions: [String: Transaction] = [:]
    private var reconciliations: [BalanceReconciliation] = []

    public init(now: Date = Date()) {
        self.wallets = [
            .mbbank: WalletAccount(id: .mbbank, name: "MBBank", balance: 0),
            .momo: WalletAccount(id: .momo, name: "Ví MoMo", balance: 0),
        ]

        var seededTags: [String: Tag] = [:]
        for (idx, spec) in DefaultTagSpecs.all.enumerated() {
            seededTags[spec.id] = Tag(
                id: spec.id,
                name: spec.name,
                isDefault: true,
                sortOrder: idx,
                createdAt: now
            )
        }
        self.tags = seededTags
    }

    public func getWallet(_ walletId: WalletId) -> WalletAccount {
        wallets[walletId] ?? WalletAccount(id: walletId, name: walletId.displayName)
    }

    public func saveWallet(_ wallet: WalletAccount) {
        wallets[wallet.id] = wallet
    }

    public func listWallets() -> [WalletAccount] {
        [getWallet(.mbbank), getWallet(.momo)]
    }

    public func getTag(_ tagId: String) -> Tag? {
        tags[tagId]
    }

    public func saveTag(_ tag: Tag) {
        tags[tag.id] = tag
    }

    public func listTags() -> [Tag] {
        tags.values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
    }

    public func getTransaction(_ txId: String) -> Transaction? {
        transactions[txId]
    }

    public func saveTransaction(_ tx: Transaction) {
        transactions[tx.id] = tx
    }

    public func deleteTransaction(_ txId: String) -> Bool {
        transactions.removeValue(forKey: txId) != nil
    }

    public func listTransactions() -> [Transaction] {
        transactions.values.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.createdAt > $1.createdAt
        }
    }

    public func saveReconciliation(_ rec: BalanceReconciliation) {
        reconciliations.append(rec)
    }

    public func listReconciliations() -> [BalanceReconciliation] {
        reconciliations.sorted { $0.reconciledAt > $1.reconciledAt }
    }
}

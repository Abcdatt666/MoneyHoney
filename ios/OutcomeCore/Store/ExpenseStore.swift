import Foundation

/// Persistence contract for wallets, tags, transactions, and reconciliations.
@MainActor
public protocol ExpenseStore: AnyObject {
    func getWallet(_ walletId: WalletId) -> WalletAccount
    func saveWallet(_ wallet: WalletAccount)
    func listWallets() -> [WalletAccount]

    func getTag(_ tagId: String) -> Tag?
    func saveTag(_ tag: Tag)
    func listTags() -> [Tag]

    func getTransaction(_ txId: String) -> Transaction?
    func saveTransaction(_ tx: Transaction)
    func deleteTransaction(_ txId: String) -> Bool
    func listTransactions() -> [Transaction]

    func saveReconciliation(_ rec: BalanceReconciliation)
    func listReconciliations() -> [BalanceReconciliation]
}

import Foundation

/// Portable full snapshot of Outcome's offline database for JSON backup & restore.
public struct OutcomeBackupSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let wallets: [WalletAccount]
    public let tags: [Tag]
    public let transactions: [Transaction]
    public let reconciliations: [BalanceReconciliation]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date = Date(),
        wallets: [WalletAccount],
        tags: [Tag],
        transactions: [Transaction],
        reconciliations: [BalanceReconciliation]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.wallets = wallets
        self.tags = tags
        self.transactions = transactions
        self.reconciliations = reconciliations
    }
}

public enum OutcomeBackupError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

/// Encodes/decodes portable JSON backups and UTF-8 Excel-friendly CSV exports.
public enum OutcomeBackupCodec {
    public static let currentSchemaVersion = 1

    @MainActor
    public static func makeSnapshot(from store: ExpenseStore, now: Date = Date()) -> OutcomeBackupSnapshot {
        OutcomeBackupSnapshot(
            schemaVersion: currentSchemaVersion,
            exportedAt: now,
            wallets: store.listWallets(),
            tags: store.listTags(),
            transactions: store.listTransactions(),
            reconciliations: store.listReconciliations()
        )
    }

    @MainActor
    public static func encodeJSON(from store: ExpenseStore, now: Date = Date()) throws -> Data {
        let snapshot = makeSnapshot(from: store, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decodeJSON(_ data: Data) throws -> OutcomeBackupSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(OutcomeBackupSnapshot.self, from: data)
        guard snapshot.schemaVersion <= currentSchemaVersion else {
            throw OutcomeBackupError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        return snapshot
    }

    @MainActor
    public static func restore(_ snapshot: OutcomeBackupSnapshot, into store: ExpenseStore) {
        store.replaceAll(
            wallets: snapshot.wallets,
            tags: snapshot.tags,
            transactions: snapshot.transactions,
            reconciliations: snapshot.reconciliations
        )
    }

    @MainActor
    public static func encodeCSV(from store: ExpenseStore) -> String {
        let tagsById = Dictionary(uniqueKeysWithValues: store.listTags().map { ($0.id, $0.name) })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        // UTF-8 BOM ensures Vietnamese diacritics render cleanly in Microsoft Excel.
        var lines: [String] = [
            "\u{FEFF}Ngày giờ,Ví nguồn,Ví đích,Loại,Hướng,Số tiền (VND),Nội dung,Tag,Ghi chú,Trạng thái,Mã Trace",
        ]

        for tx in store.listTransactions() {
            let dateStr = formatter.string(from: tx.occurredAt)
            let sourceName = tx.sourceWalletId.displayName
            let targetName = tx.targetWalletId?.displayName ?? ""
            let typeLabel: String
            switch tx.txType {
            case .expense: typeLabel = "Chi tiêu"
            case .income: typeLabel = "Thu nhập"
            case .internalTransfer: typeLabel = "Chuyển nội bộ"
            }
            let dirLabel = tx.direction == .out ? "Chi" : "Thu"
            let tagName = tx.tagId.flatMap { tagsById[$0] } ?? ""
            let statusLabel = tx.status == .confirmed ? "Đã duyệt" : "Chờ duyệt"
            let trace = tx.traceId ?? ""

            let fields = [
                dateStr,
                sourceName,
                targetName,
                typeLabel,
                dirLabel,
                String(tx.amount),
                tx.description,
                tagName,
                tx.note,
                statusLabel,
                trace,
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

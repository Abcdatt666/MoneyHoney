import OutcomeCore
import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    let tagName: String?

    private var iconTint: Color {
        if transaction.txType == .internalTransfer {
            return .secondary
        }
        if transaction.status == .pending {
            return OutcomeTheme.Colors.pending
        }
        return transaction.direction == .in ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.accent
    }

    private var subtitleText: String {
        if transaction.txType == .internalTransfer {
            let target = transaction.targetWalletId?.displayName ?? ""
            return "\(transaction.sourceWalletId.displayName) → \(target)"
        }
        let statusOrTag = transaction.status == .pending
            ? "Chờ gắn tag"
            : (tagName ?? "Đã phân loại")
        return "\(transaction.sourceWalletId.displayName) · \(statusOrTag)"
    }

    private var amountText: String {
        if transaction.txType == .internalTransfer {
            return VNDFormatter.format(transaction.amount)
        }
        return VNDFormatter.formatSigned(transaction.amount, direction: transaction.direction)
    }

    private var amountStyle: Color {
        if transaction.txType == .internalTransfer {
            return .secondary
        }
        return transaction.direction == .in ? OutcomeTheme.Colors.income : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: OutcomeTheme.symbol(for: transaction))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(iconTint, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.footnote)
                    .foregroundStyle(transaction.status == .pending ? OutcomeTheme.Colors.pending : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(amountStyle)

                Text(transaction.occurredAt, format: .dateTime.hour().minute())
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
        .contentShape(.rect)
    }
}

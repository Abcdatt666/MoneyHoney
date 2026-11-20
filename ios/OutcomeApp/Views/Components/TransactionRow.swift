import OutcomeCore
import SwiftUI

struct TransactionRow: View {
    let item: OutcomeCore.Transaction
    let tagName: String?

    private var iconTint: Color {
        if item.txType == .internalTransfer {
            return .secondary
        }
        if item.status == .pending {
            return OutcomeTheme.Colors.pending
        }
        return item.direction == .in ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.accent
    }

    private var subtitleText: String {
        if item.txType == .internalTransfer {
            let target = item.targetWalletId?.displayName ?? ""
            return "\(item.sourceWalletId.displayName) → \(target)"
        }
        let statusOrTag = item.status == .pending
            ? "Chờ gắn tag"
            : (tagName ?? "Đã phân loại")
        if !item.note.isEmpty {
            return "\(item.sourceWalletId.displayName) · \(statusOrTag) · \(item.note)"
        }
        return "\(item.sourceWalletId.displayName) · \(statusOrTag)"
    }

    private var amountText: String {
        if item.txType == .internalTransfer {
            return VNDFormatter.format(item.amount)
        }
        return VNDFormatter.formatSigned(item.amount, direction: item.direction)
    }

    private var amountStyle: Color {
        if item.txType == .internalTransfer {
            return .secondary
        }
        return item.direction == .in ? OutcomeTheme.Colors.income : .primary
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: OutcomeTheme.symbol(for: item))
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(iconTint, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.description)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.footnote)
                    .foregroundStyle(item.status == .pending ? OutcomeTheme.Colors.pending : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(amountText)
                    .font(.subheadline.bold())
                    .monospacedDigit()
                    .foregroundStyle(amountStyle)
                    .lineLimit(1)

                Text(item.occurredAt, format: .dateTime.day().month().hour().minute())
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
        .contentShape(.rect)
    }
}

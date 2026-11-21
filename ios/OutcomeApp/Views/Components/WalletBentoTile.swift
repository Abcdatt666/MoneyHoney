import OutcomeCore
import SwiftUI

struct WalletBentoTile: View {
    let wallet: WalletAccount
    var hideBalance: Bool = false
    let action: () -> Void

    private var tileBackground: Color {
        wallet.id == .mbbank ? OutcomeTheme.Colors.mbbankTile : OutcomeTheme.Colors.momoTile
    }

    private var displayBalance: String {
        hideBalance ? "••••••••" : VNDFormatter.format(wallet.balance)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(wallet.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: OutcomeTheme.symbol(for: wallet.id))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Text(displayBalance)
                    .font(.headline.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(tileBackground, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            hideBalance
                ? "\(wallet.name), số dư đang ẩn"
                : "\(wallet.name), số dư \(VNDFormatter.format(wallet.balance))"
        )
    }
}

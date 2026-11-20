import Charts
import OutcomeCore
import SwiftUI

struct SpendingAllocationCard: View {
    let monthlyExpense: Int
    let expenseByTag: [String: Int]
    let monthNumber: Int

    private struct TagSlice: Identifiable {
        let id: String
        let name: String
        let amount: Int
        let sharePercent: Int
        let color: Color
    }

    private var slices: [TagSlice] {
        guard monthlyExpense > 0 else { return [] }
        let sorted = expenseByTag
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }

        return sorted.enumerated().map { idx, entry in
            let pct = Int((Double(entry.value) / Double(monthlyExpense) * 100.0).rounded())
            let color = OutcomeTheme.chartPalette[idx % OutcomeTheme.chartPalette.count]
            return TagSlice(
                id: entry.key,
                name: entry.key,
                amount: entry.value,
                sharePercent: pct,
                color: color
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chi tiêu tháng \(monthNumber)")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(VNDFormatter.format(monthlyExpense))
                    .font(.headline.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            if slices.isEmpty {
                Text("Chưa có khoản chi nào trong tháng này.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(slices) { slice in
                    BarMark(
                        x: .value("Số tiền", slice.amount),
                        y: .value("Tháng", "Chi tiêu")
                    )
                    .foregroundStyle(slice.color)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartXScale(domain: 0...max(monthlyExpense, 1))
                .frame(height: 14)
                .clipShape(.capsule)
                .accessibilityLabel("Biểu đồ phân bổ chi tiêu theo tag")

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 112), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(slices.prefix(4)) { slice in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(slice.color)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)

                            Text("\(slice.name) · \(slice.sharePercent)%")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OutcomeTheme.Colors.track, in: .capsule)
                    }
                }
            }
        }
        .padding(16)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }
}

import Charts
import OutcomeCore
import SwiftUI

struct SpendingAllocationCard: View {
    let monthlyExpense: Int
    let monthlyIncome: Int
    let expenseByTag: [String: Int]
    let monthLabel: String
    let canGoNextMonth: Bool
    var hideBalance: Bool = false
    var selectedTagName: String? = nil
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    var onSelectTagName: ((String) -> Void)? = nil

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
            let pct = max(1, Int((Double(entry.value) / Double(monthlyExpense) * 100.0).rounded()))
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
            HStack(spacing: 4) {
                Button("Tháng trước", systemImage: "chevron.left", action: onPreviousMonth)
                    .labelStyle(.iconOnly)
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(
                        minWidth: OutcomeTheme.Layout.minTouchTarget,
                        minHeight: OutcomeTheme.Layout.minTouchTarget
                    )
                    .buttonStyle(.plain)

                Text(monthLabel)
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Button("Tháng sau", systemImage: "chevron.right", action: onNextMonth)
                    .labelStyle(.iconOnly)
                    .font(.footnote.bold())
                    .foregroundStyle(Color.secondary.opacity(canGoNextMonth ? 1 : 0.35))
                    .frame(
                        minWidth: OutcomeTheme.Layout.minTouchTarget,
                        minHeight: OutcomeTheme.Layout.minTouchTarget
                    )
                    .buttonStyle(.plain)
                    .disabled(!canGoNextMonth)

                Spacer(minLength: 4)

                if monthlyIncome > 0 {
                    Text(hideBalance ? "Thu ••••" : "Thu +\(VNDFormatter.format(monthlyIncome))")
                        .font(.footnote.bold())
                        .monospacedDigit()
                        .foregroundStyle(OutcomeTheme.Colors.income)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, -10)

            HStack(alignment: .firstTextBaseline) {
                Text("Đã chi")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(hideBalance ? "••••••••" : VNDFormatter.format(monthlyExpense))
                    .font(.title3.bold())
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
                        y: .value("Tháng", "Chi tiêu"),
                        height: .fixed(14),
                        stacking: .normalized
                    )
                    .foregroundStyle(slice.color)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartPlotStyle { plotArea in
                    plotArea.frame(height: 14)
                }
                .frame(height: 14)
                .clipShape(.capsule)
                .accessibilityLabel("Biểu đồ phân bổ chi tiêu theo tag")

                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(slices) { slice in
                        let isSelected = selectedTagName == slice.name
                        Button {
                            onSelectTagName?(slice.name)
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(isSelected ? .white : slice.color)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)

                                Text("\(slice.name) · \(slice.sharePercent)%")
                                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                isSelected ? OutcomeTheme.Colors.accent : OutcomeTheme.Colors.track,
                                in: .capsule
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(16)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }
}

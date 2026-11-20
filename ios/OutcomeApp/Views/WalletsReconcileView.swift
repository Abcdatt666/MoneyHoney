import OutcomeCore
import SwiftUI

struct WalletsReconcileView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var mbActualInput: Int = 0
    @State private var momoActualInput: Int = 0
    @State private var reconcileNote: String = ""
    @State private var didSeedInputs: Bool = false
    @State private var reconcileTrigger: Int = 0

    private var mbExpected: Int {
        coordinator.wallets.first(where: { $0.id == .mbbank })?.balance ?? 0
    }

    private var momoExpected: Int {
        coordinator.wallets.first(where: { $0.id == .momo })?.balance ?? 0
    }

    private var mbDelta: Int { mbActualInput - mbExpected }
    private var momoDelta: Int { momoActualInput - momoExpected }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutcomeTheme.Layout.sectionSpacing) {
                    reminderCard

                    reconcileTiles

                    noteAndActionCard

                    if !coordinator.reconciliations.isEmpty {
                        historyCard
                    }
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.vertical, 12)
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Ví & Chốt sổ")
            .onAppear {
                if !didSeedInputs {
                    mbActualInput = mbExpected
                    momoActualInput = momoExpected
                    didSeedInputs = true
                }
            }
            .onChange(of: mbExpected) { _, newValue in
                mbActualInput = newValue
            }
            .onChange(of: momoExpected) { _, newValue in
                momoActualInput = newValue
            }
            .sensoryFeedback(.success, trigger: reconcileTrigger)
        }
    }

    private var reminderCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.title3)
                .foregroundStyle(OutcomeTheme.Colors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("NHẮC ĐỐI SOÁT TIẾP THEO")
                    .font(.footnote.bold())
                    .foregroundStyle(OutcomeTheme.Colors.accent)

                Text(
                    coordinator.summary.nextReconciliationReminder,
                    format: .dateTime.weekday(.wide).day().month().hour().minute()
                )
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }

    private var reconcileTiles: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: OutcomeTheme.Layout.tileSpacing))
            : AnyLayout(HStackLayout(spacing: OutcomeTheme.Layout.tileSpacing))

        return layout {
            reconcileTile(
                title: "MBBank",
                expected: mbExpected,
                delta: mbDelta,
                surface: OutcomeTheme.Colors.mbbankTile,
                inputValue: $mbActualInput
            )

            reconcileTile(
                title: "Ví MoMo",
                expected: momoExpected,
                delta: momoDelta,
                surface: OutcomeTheme.Colors.momoTile,
                inputValue: $momoActualInput
            )
        }
    }

    private func reconcileTile(
        title: String,
        expected: Int,
        delta: Int,
        surface: Color,
        inputValue: Binding<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(.primary)

            Text("App: \(VNDFormatter.format(expected))")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            TextField("Số dư thực", value: inputValue, format: .number)
                .keyboardType(.numberPad)
                .font(.headline.bold())
                .monospacedDigit()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: 12))

            Label(
                VNDFormatter.formatDelta(delta),
                systemImage: delta == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .font(.footnote.bold())
            .monospacedDigit()
            .foregroundStyle(delta == 0 ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.discrepancy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }

    private var noteAndActionCard: some View {
        VStack(spacing: 12) {
            TextField("Ghi chú chốt sổ (tùy chọn)", text: $reconcileNote)
                .padding(14)
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))

            Button {
                reconcileTrigger += 1
                coordinator.reconcileBalances(
                    mbActual: mbActualInput,
                    momoActual: momoActualInput,
                    note: reconcileNote
                )
                reconcileNote = ""
            } label: {
                Text("Chốt số dư thực tế")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.primaryButtonHeight)
                    .background(OutcomeTheme.Colors.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(mbActualInput < 0 || momoActualInput < 0)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lịch sử đối soát")
                .font(.headline)

            ForEach(coordinator.reconciliations.prefix(6)) { rec in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.walletId.displayName)
                            .font(.subheadline.bold())
                        Text(rec.reconciledAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(VNDFormatter.format(rec.actualBalance))
                            .font(.subheadline.bold())
                            .monospacedDigit()
                        Text(VNDFormatter.formatDelta(rec.discrepancy))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(rec.discrepancy == 0 ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.discrepancy)
                    }
                }
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
            }
        }
        .padding(16)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
    }
}

#Preview {
    WalletsReconcileView()
        .environment(AppCoordinator.preview())
}

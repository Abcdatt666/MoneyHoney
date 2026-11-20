import OutcomeCore
import SwiftUI

struct WalletsReconcileView: View {
    private enum Field: Hashable {
        case mbActual
        case momoActual
        case note
    }

    @Environment(AppCoordinator.self) private var coordinator
    @FocusState private var focusedField: Field?

    @State private var mbActualText: String = ""
    @State private var momoActualText: String = ""
    @State private var reconcileNote: String = ""
    @State private var didSeedInputs: Bool = false
    @State private var reconcileTrigger: Int = 0

    private var mbExpected: Int {
        coordinator.wallets.first(where: { $0.id == .mbbank })?.balance ?? 0
    }

    private var momoExpected: Int {
        coordinator.wallets.first(where: { $0.id == .momo })?.balance ?? 0
    }

    private var parsedMbActual: Int? {
        let digits = mbActualText.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private var parsedMomoActual: Int? {
        let digits = momoActualText.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private var mbDelta: Int { (parsedMbActual ?? 0) - mbExpected }
    private var momoDelta: Int { (parsedMomoActual ?? 0) - momoExpected }

    private var canCommit: Bool {
        parsedMbActual != nil && parsedMomoActual != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OutcomeTheme.Layout.sectionSpacing) {
                    reminderCard

                    reconcileCards

                    noteAndActionCard

                    if !coordinator.reconciliations.isEmpty {
                        historyCard
                    }
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .refreshable {
                coordinator.refresh()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    KeyboardDoneBar {
                        focusedField = nil
                    }
                }
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Ví & Chốt sổ")
            .onAppear {
                if !didSeedInputs {
                    mbActualText = String(max(0, mbExpected))
                    momoActualText = String(max(0, momoExpected))
                    didSeedInputs = true
                }
            }
            .onChange(of: mbExpected) { _, newValue in
                if focusedField != .mbActual {
                    mbActualText = String(max(0, newValue))
                }
            }
            .onChange(of: momoExpected) { _, newValue in
                if focusedField != .momoActual {
                    momoActualText = String(max(0, newValue))
                }
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

    private var reconcileCards: some View {
        VStack(spacing: 12) {
            reconcileCard(
                walletId: .mbbank,
                expected: mbExpected,
                actual: parsedMbActual,
                delta: mbDelta,
                surface: OutcomeTheme.Colors.mbbankTile,
                textBinding: $mbActualText,
                field: .mbActual
            )

            reconcileCard(
                walletId: .momo,
                expected: momoExpected,
                actual: parsedMomoActual,
                delta: momoDelta,
                surface: OutcomeTheme.Colors.momoTile,
                textBinding: $momoActualText,
                field: .momoActual
            )
        }
    }

    private func reconcileCard(
        walletId: WalletId,
        expected: Int,
        actual: Int?,
        delta: Int,
        surface: Color,
        textBinding: Binding<String>,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(walletId.displayName, systemImage: OutcomeTheme.symbol(for: walletId))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Text("App: \(VNDFormatter.format(expected))")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Nhập số dư thực tế", text: textBinding)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: field)
                    .font(.title3.bold())
                    .monospacedDigit()
                    .onChange(of: textBinding.wrappedValue) { _, newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(12))
                        if digits != newValue {
                            textBinding.wrappedValue = digits
                        }
                    }

                if !textBinding.wrappedValue.isEmpty {
                    Button("Xóa số dư", systemImage: "xmark.circle.fill") {
                        textBinding.wrappedValue = ""
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: OutcomeTheme.Layout.minTouchTarget, minHeight: OutcomeTheme.Layout.minTouchTarget)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: 50)
            .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: 14))

            HStack {
                if let actual {
                    Text(VNDFormatter.format(actual))
                        .font(.footnote.bold())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if actual != nil {
                    Label(
                        VNDFormatter.formatDelta(delta),
                        systemImage: delta == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .font(.footnote.bold())
                    .monospacedDigit()
                    .foregroundStyle(delta == 0 ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.discrepancy)
                } else {
                    Text("Nhập số dư để tính chênh lệch")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }

    private var noteAndActionCard: some View {
        VStack(spacing: 12) {
            TextField("Ghi chú chốt sổ (tùy chọn)", text: $reconcileNote)
                .focused($focusedField, equals: .note)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .padding(14)
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))

            Button {
                guard let mb = parsedMbActual, let momo = parsedMomoActual else { return }
                focusedField = nil
                reconcileTrigger += 1
                coordinator.reconcileBalances(
                    mbActual: mb,
                    momoActual: momo,
                    note: reconcileNote
                )
                reconcileNote = ""
            } label: {
                Text("Chốt số dư thực tế")
                    .font(.headline)
                    .foregroundStyle(canCommit ? .white : .secondary)
                    .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.primaryButtonHeight)
                    .background(
                        canCommit ? OutcomeTheme.Colors.accent : OutcomeTheme.Colors.track,
                        in: .capsule
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canCommit)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lịch sử đối soát")
                .font(.headline)

            ForEach(coordinator.reconciliations.prefix(8).enumerated(), id: \.element.id) { idx, rec in
                if idx > 0 {
                    Divider()
                }
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

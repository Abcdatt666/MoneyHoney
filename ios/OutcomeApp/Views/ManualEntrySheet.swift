import OutcomeCore
import SwiftUI

struct ManualEntrySheet: View {
    private enum Field: Hashable {
        case amount
        case description
        case note
    }

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    @State private var walletId: WalletId = .momo
    @State private var direction: Direction = .out
    @State private var amountText: String = ""
    @State private var selectedTagId: String? = "tag_an_uong"
    @State private var descriptionText: String = ""
    @State private var noteText: String = ""
    @State private var locationManager = LocationCaptureManager()
    @State private var capturedLocation: CapturedLocation?
    @State private var isShowingNewTagAlert: Bool = false
    @State private var newTagName: String = ""
    @State private var saveTrigger: Int = 0

    private var parsedAmount: Int? {
        let digits = amountText.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private var canSave: Bool {
        parsedAmount != nil && selectedTagId != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Loại giao dịch", selection: $direction) {
                        Text("Chi tiêu").tag(Direction.out)
                        Text("Thu nhập").tag(Direction.in)
                    }
                    .pickerStyle(.segmented)

                    Picker("Nguồn tiền", selection: $walletId) {
                        ForEach(WalletId.allCases) { wallet in
                            Text(wallet.displayName).tag(wallet)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Số tiền (VND)")
                                .font(.footnote.bold())
                                .foregroundStyle(.secondary)

                            Spacer()

                            if let parsedAmount {
                                Text(VNDFormatter.formatSigned(parsedAmount, direction: direction))
                                    .font(.footnote.bold())
                                    .monospacedDigit()
                                    .foregroundStyle(direction == .in ? OutcomeTheme.Colors.income : OutcomeTheme.Colors.accent)
                            }
                        }

                        HStack(spacing: 8) {
                            TextField("Nhập số tiền, ví dụ 50000", text: $amountText)
                                .keyboardType(.numberPad)
                                .focused($focusedField, equals: .amount)
                                .font(.system(.title2, design: .rounded))
                                .bold()
                                .monospacedDigit()
                                .onChange(of: amountText) { _, newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(12))
                                    if digits != newValue {
                                        amountText = digits
                                    }
                                }

                            if !amountText.isEmpty {
                                Button("Xóa số tiền", systemImage: "xmark.circle.fill") {
                                    amountText = ""
                                }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.secondary)
                                .frame(minWidth: OutcomeTheme.Layout.minTouchTarget, minHeight: OutcomeTheme.Layout.minTouchTarget)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .frame(minHeight: 54)
                        .background(
                            OutcomeTheme.Colors.card,
                            in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tag")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)

                        TagGridSelector(
                            tags: coordinator.tags,
                            selectedTagId: $selectedTagId,
                            onSelectTag: {
                                focusedField = nil
                            },
                            onTapCreateTag: {
                                focusedField = nil
                                newTagName = ""
                                isShowingNewTagAlert = true
                            }
                        )
                    }

                    VStack(spacing: 10) {
                        TextField("Nội dung (ví dụ: Cơm trưa)", text: $descriptionText)
                            .focused($focusedField, equals: .description)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .note }
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )

                        TextField("Ghi chú (tùy chọn)", text: $noteText)
                            .focused($focusedField, equals: .note)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )

                        locationAttachRow
                    }
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
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
            .navigationTitle("Nhập giao dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        focusedField = nil
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        guard let amount = parsedAmount, let tagId = selectedTagId else { return }
                        focusedField = nil
                        saveTrigger += 1
                        coordinator.addManualTransaction(
                            walletId: walletId,
                            direction: direction,
                            amount: amount,
                            tagId: tagId,
                            description: descriptionText,
                            note: noteText,
                            locationName: capturedLocation?.name,
                            latitude: capturedLocation?.latitude,
                            longitude: capturedLocation?.longitude
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .alert("Tạo tag mới", isPresented: $isShowingNewTagAlert) {
                TextField("Tên tag", text: $newTagName)
                Button("Tạo") {
                    if let created = coordinator.addCustomTag(name: newTagName) {
                        selectedTagId = created.id
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
        .presentationBackground(OutcomeTheme.Colors.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var locationAttachRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let capturedLocation {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.footnote.bold())
                        .foregroundStyle(OutcomeTheme.Colors.accent)
                        .accessibilityHidden(true)

                    Text(capturedLocation.name)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Button("Gỡ vị trí", systemImage: "xmark.circle.fill") {
                        self.capturedLocation = nil
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .frame(
                        minWidth: OutcomeTheme.Layout.minTouchTarget,
                        minHeight: OutcomeTheme.Layout.minTouchTarget
                    )
                }
                .padding(.horizontal, 14)
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                .background(
                    OutcomeTheme.Colors.card,
                    in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                )
            } else {
                Button {
                    focusedField = nil
                    Task {
                        if let loc = await locationManager.captureCurrentLocation() {
                            capturedLocation = loc
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if locationManager.isCapturing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "location")
                                .font(.footnote.bold())
                                .foregroundStyle(OutcomeTheme.Colors.accent)
                                .accessibilityHidden(true)
                        }

                        Text(locationManager.isCapturing ? "Đang lấy vị trí…" : "Gắn vị trí hiện tại (tùy chọn)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                    .background(
                        OutcomeTheme.Colors.card,
                        in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                    )
                }
                .buttonStyle(.plain)
                .disabled(locationManager.isCapturing)
            }

            if let error = locationManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(OutcomeTheme.Colors.discrepancy)
                    .padding(.horizontal, 4)
            }
        }
    }
}

#Preview {
    ManualEntrySheet()
        .environment(AppCoordinator.preview())
}

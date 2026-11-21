import OutcomeCore
import SwiftUI

struct TagAssignmentSheet: View {
    private enum Field: Hashable {
        case note
        case amount
        case description
        case location
    }

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    let item: OutcomeCore.Transaction

    @State private var selectedTagId: String?
    @State private var note: String
    @State private var walletId: WalletId
    @State private var direction: Direction
    @State private var amountText: String
    @State private var descriptionText: String
    @State private var occurredAt: Date
    @State private var locationNameText: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var isEditingDetails: Bool = false
    @State private var didSeedSuggestion: Bool = false

    @State private var isShowingNewTagAlert: Bool = false
    @State private var isConfirmingDelete: Bool = false
    @State private var newTagName: String = ""
    @State private var saveTrigger: Int = 0

    init(item: OutcomeCore.Transaction) {
        self.item = item
        _selectedTagId = State(initialValue: item.tagId)
        _note = State(initialValue: item.note)
        _walletId = State(initialValue: item.sourceWalletId)
        _direction = State(
            initialValue: item.txType == .internalTransfer && item.sourceWalletId == .mbbank
                ? .out
                : item.direction
        )
        _amountText = State(initialValue: String(item.amount))
        _descriptionText = State(initialValue: item.description)
        _occurredAt = State(initialValue: item.occurredAt)
        _locationNameText = State(initialValue: item.locationName ?? "")
        _latitude = State(initialValue: item.latitude)
        _longitude = State(initialValue: item.longitude)
    }

    private var hasLocation: Bool {
        let trimmedLoc = locationNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedLoc.isEmpty || (latitude != nil && longitude != nil)
    }

    private var parsedAmount: Int? {
        let digits = amountText.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        return value
    }

    private var suggestedTags: [Tag] {
        coordinator.suggestTags(for: item, limit: 3)
    }

    private var isConvertingInternalTransfer: Bool {
        item.txType == .internalTransfer
    }

    private var hasDetailChanges: Bool {
        let trimmedLoc = locationNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalLoc = item.locationName ?? ""
        return isConvertingInternalTransfer ||
            walletId != item.sourceWalletId ||
            direction != item.direction ||
            parsedAmount != item.amount ||
            descriptionText.trimmingCharacters(in: .whitespacesAndNewlines) != item.description ||
            abs(occurredAt.timeIntervalSince(item.occurredAt)) >= 1 ||
            trimmedLoc != originalLoc ||
            latitude != item.latitude ||
            longitude != item.longitude
    }

    private var canSave: Bool {
        selectedTagId != nil && parsedAmount != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    if isConvertingInternalTransfer {
                        internalTransferConvertNotice
                    }

                    if !suggestedTags.isEmpty {
                        suggestedTagsSection
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tất cả Tag")
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ghi chú")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)

                        TextField("Ví dụ: Mua đồ Shopee", text: $note)
                            .focused($focusedField, equals: .note)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )
                    }

                    if hasLocation {
                        TransactionLocationCard(
                            locationName: locationNameText.trimmingCharacters(in: .whitespacesAndNewlines),
                            latitude: latitude,
                            longitude: longitude
                        )
                    }

                    editDetailsSection

                    Button(role: .destructive) {
                        focusedField = nil
                        isConfirmingDelete = true
                    } label: {
                        Label("Xóa giao dịch này", systemImage: "trash")
                            .font(.footnote.bold())
                            .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OutcomeTheme.Colors.discrepancy)
                    .padding(.top, 4)
                    .confirmationDialog(
                        "Xóa giao dịch này?",
                        isPresented: $isConfirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button("Xóa và hoàn số dư", role: .destructive) {
                            coordinator.deleteTransaction(txId: item.id)
                            dismiss()
                        }
                        Button("Hủy", role: .cancel) {}
                    } message: {
                        Text("\(item.description) · \(VNDFormatter.format(item.amount))")
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
            .navigationTitle(
                isConvertingInternalTransfer
                    ? "Đổi thành chi tiêu"
                    : (item.status == .pending ? "Chọn danh mục" : "Chi tiết giao dịch")
            )
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
                        saveTransaction()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                if !didSeedSuggestion, selectedTagId == nil, let topTag = suggestedTags.first {
                    selectedTagId = topTag.id
                }
                didSeedSuggestion = true
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .alert("Tạo tag mới", isPresented: $isShowingNewTagAlert) {
                TextField("Tên tag (ví dụ: Thú cưng)", text: $newTagName)
                Button("Tạo") {
                    if let created = coordinator.addCustomTag(name: newTagName) {
                        selectedTagId = created.id
                    }
                }
                Button("Hủy", role: .cancel) {}
            }
        }
        .presentationBackground(OutcomeTheme.Colors.canvas)
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        let displayAmount = parsedAmount ?? item.amount
        let displayDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(spacing: 4) {
            Text("\(walletId.displayName) · \(displayDesc.isEmpty ? item.description : displayDesc)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(VNDFormatter.formatSigned(displayAmount, direction: direction))
                .font(.system(.title, design: .rounded))
                .bold()
                .monospacedDigit()
                .foregroundStyle(direction == .in ? OutcomeTheme.Colors.income : .primary)

            Text(occurredAt, format: .dateTime.day().month().year().hour().minute())
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }

    private var internalTransferConvertNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.title3)
                .foregroundStyle(OutcomeTheme.Colors.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Chuyển nội bộ → Chi tiêu / Thu nhập")
                    .font(.footnote.bold())
                    .foregroundStyle(.primary)

                Text("Chọn tag và bấm Lưu để tính vào chi tiêu tháng (ví dụ: bill WiFi trả qua MoMo bằng nguồn MBBank). Số dư đã cộng sang Ví MoMo sẽ tự động được hoàn lại.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))
    }

    private var suggestedTagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Gợi ý cho giao dịch này", systemImage: "sparkles")
                .font(.footnote.bold())
                .foregroundStyle(OutcomeTheme.Colors.accent)

            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(suggestedTags) { tag in
                    let isSelected = selectedTagId == tag.id
                    Button {
                        focusedField = nil
                        selectedTagId = tag.id
                    } label: {
                        Label(tag.name, systemImage: OutcomeTheme.symbol(forTagId: tag.id))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                isSelected ? OutcomeTheme.Colors.accent : OutcomeTheme.Colors.card,
                                in: .capsule
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private var editDetailsSection: some View {
        DisclosureGroup(isExpanded: $isEditingDetails) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Số tiền (VND)")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        TextField("Nhập số tiền", text: $amountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .amount)
                            .font(.title3.bold())
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
                            .frame(
                                minWidth: OutcomeTheme.Layout.minTouchTarget,
                                minHeight: OutcomeTheme.Layout.minTouchTarget
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 48)
                    .background(OutcomeTheme.Colors.track, in: .rect(cornerRadius: 12))

                    if let amount = parsedAmount {
                        Text(VNDFormatter.format(amount))
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .foregroundStyle(OutcomeTheme.Colors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ví nguồn")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)

                    Picker("Ví nguồn", selection: $walletId) {
                        Text("MBBank").tag(WalletId.mbbank)
                        Text("Ví MoMo").tag(WalletId.momo)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Loại giao dịch")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)

                    Picker("Loại giao dịch", selection: $direction) {
                        Text("Chi tiền").tag(Direction.out)
                        Text("Nhận tiền").tag(Direction.in)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Nội dung")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)

                    TextField("Nội dung giao dịch", text: $descriptionText)
                        .focused($focusedField, equals: .description)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(12)
                        .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                        .background(OutcomeTheme.Colors.track, in: .rect(cornerRadius: 12))
                }

                DatePicker(
                    "Thời gian",
                    selection: $occurredAt,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .font(.subheadline)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Vị trí")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)

                        Spacer()

                        if hasLocation {
                            Button("Gỡ vị trí", role: .destructive) {
                                locationNameText = ""
                                latitude = nil
                                longitude = nil
                            }
                            .font(.footnote.bold())
                        }
                    }

                    TextField("Tên địa điểm (tùy chọn)", text: $locationNameText)
                        .focused($focusedField, equals: .location)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .padding(12)
                        .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                        .background(OutcomeTheme.Colors.track, in: .rect(cornerRadius: 12))
                }
            }
            .padding(.top, 12)
        } label: {
            Label("Sửa chi tiết giao dịch", systemImage: "slider.horizontal.3")
                .font(.subheadline.bold())
                .foregroundStyle(.primary)
                .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }

    private func saveTransaction() {
        guard let tagId = selectedTagId, let amount = parsedAmount else { return }
        focusedField = nil
        saveTrigger += 1

        if hasDetailChanges {
            let trimmedLocation = locationNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldClearLocation = trimmedLocation.isEmpty && latitude == nil && longitude == nil
            coordinator.updateTransaction(
                txId: item.id,
                walletId: walletId,
                direction: direction,
                amount: amount,
                tagId: tagId,
                description: descriptionText,
                note: note,
                occurredAt: occurredAt,
                locationName: trimmedLocation.isEmpty ? nil : trimmedLocation,
                latitude: latitude,
                longitude: longitude,
                clearLocation: shouldClearLocation
            )
        } else {
            coordinator.confirmTransaction(
                txId: item.id,
                tagId: tagId,
                note: note
            )
        }
        dismiss()
    }
}

import OutcomeCore
import SwiftUI

struct ManualEntrySheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var walletId: WalletId = .momo
    @State private var direction: Direction = .out
    @State private var amount: Int?
    @State private var selectedTagId: String? = "tag_an_uong"
    @State private var descriptionText: String = ""
    @State private var noteText: String = ""
    @State private var isShowingNewTagAlert: Bool = false
    @State private var newTagName: String = ""
    @State private var saveTrigger: Int = 0

    private var canSave: Bool {
        (amount ?? 0) > 0 && selectedTagId != nil
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
                        Text("Số tiền (VND)")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)

                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(.title2, design: .rounded))
                            .bold()
                            .monospacedDigit()
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
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
                            onTapCreateTag: {
                                newTagName = ""
                                isShowingNewTagAlert = true
                            }
                        )
                    }

                    VStack(spacing: 10) {
                        TextField("Nội dung (ví dụ: Cơm trưa)", text: $descriptionText)
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )

                        TextField("Ghi chú (tùy chọn)", text: $noteText)
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )
                    }
                }
                .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
                .padding(.vertical, 12)
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Nhập giao dịch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        guard let amount, amount > 0, let tagId = selectedTagId else { return }
                        saveTrigger += 1
                        coordinator.addManualTransaction(
                            walletId: walletId,
                            direction: direction,
                            amount: amount,
                            tagId: tagId,
                            description: descriptionText,
                            note: noteText
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
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ManualEntrySheet()
        .environment(AppCoordinator.preview())
}

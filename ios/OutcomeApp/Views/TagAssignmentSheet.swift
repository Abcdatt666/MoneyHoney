import OutcomeCore
import SwiftUI

struct TagAssignmentSheet: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNoteFocused: Bool

    let item: OutcomeCore.Transaction

    @State private var selectedTagId: String?
    @State private var note: String
    @State private var isShowingNewTagAlert: Bool = false
    @State private var isConfirmingDelete: Bool = false
    @State private var newTagName: String = ""
    @State private var saveTrigger: Int = 0

    init(item: OutcomeCore.Transaction) {
        self.item = item
        _selectedTagId = State(initialValue: item.tagId)
        _note = State(initialValue: item.note)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chọn Tag")
                            .font(.footnote.bold())
                            .foregroundStyle(.secondary)

                        TagGridSelector(
                            tags: coordinator.tags,
                            selectedTagId: $selectedTagId,
                            onSelectTag: {
                                isNoteFocused = false
                            },
                            onTapCreateTag: {
                                isNoteFocused = false
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
                            .focused($isNoteFocused)
                            .submitLabel(.done)
                            .onSubmit { isNoteFocused = false }
                            .padding(14)
                            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
                            .background(
                                OutcomeTheme.Colors.card,
                                in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                            )
                    }

                    Button(role: .destructive) {
                        isNoteFocused = false
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
                if isNoteFocused {
                    KeyboardDoneBar {
                        isNoteFocused = false
                    }
                }
            }
            .background(OutcomeTheme.Colors.canvas)
            .navigationTitle("Chọn danh mục")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        isNoteFocused = false
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        if let tagId = selectedTagId {
                            isNoteFocused = false
                            saveTrigger += 1
                            coordinator.confirmTransaction(
                                txId: item.id,
                                tagId: tagId,
                                note: note
                            )
                            dismiss()
                        }
                    }
                    .disabled(selectedTagId == nil)
                }
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
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
    }

    private var summaryCard: some View {
        VStack(spacing: 4) {
            Text("\(item.sourceWalletId.displayName) · \(item.description)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(VNDFormatter.formatSigned(item.amount, direction: item.direction))
                .font(.system(.title, design: .rounded))
                .bold()
                .monospacedDigit()
                .foregroundStyle(item.direction == .in ? OutcomeTheme.Colors.income : .primary)

            Text(item.occurredAt, format: .dateTime.day().month().year().hour().minute())
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
    }
}

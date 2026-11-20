import OutcomeCore
import SwiftUI

struct TagGridSelector: View {
    let tags: [Tag]
    @Binding var selectedTagId: String?
    let onSelectTag: (() -> Void)?
    let onTapCreateTag: () -> Void

    init(
        tags: [Tag],
        selectedTagId: Binding<String?>,
        onSelectTag: (() -> Void)? = nil,
        onTapCreateTag: @escaping () -> Void
    ) {
        self.tags = tags
        self._selectedTagId = selectedTagId
        self.onSelectTag = onSelectTag
        self.onTapCreateTag = onTapCreateTag
    }

    var body: some View {
        FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(tags) { tag in
                let isSelected = selectedTagId == tag.id
                Button {
                    selectedTagId = tag.id
                    onSelectTag?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : OutcomeTheme.symbol(forTagId: tag.id))
                            .font(.footnote)
                            .accessibilityHidden(true)

                        Text(tag.name)
                            .font(.footnote.bold())
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: OutcomeTheme.Layout.chipMinHeight)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .background(
                        isSelected ? OutcomeTheme.Colors.accent : OutcomeTheme.Colors.card,
                        in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }

            Button(action: onTapCreateTag) {
                Label("Tag mới", systemImage: "plus")
                    .font(.footnote.bold())
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(minHeight: OutcomeTheme.Layout.chipMinHeight)
                    .foregroundStyle(OutcomeTheme.Colors.accent)
                    .background(OutcomeTheme.Colors.track, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))
            }
            .buttonStyle(.plain)
        }
    }
}

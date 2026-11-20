import OutcomeCore
import SwiftUI

struct TagGridSelector: View {
    let tags: [Tag]
    @Binding var selectedTagId: String?
    let onTapCreateTag: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tags) { tag in
                let isSelected = selectedTagId == tag.id
                Button {
                    selectedTagId = tag.id
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : OutcomeTheme.symbol(forTagId: tag.id))
                            .font(.footnote)
                            .accessibilityHidden(true)

                        Text(tag.name)
                            .font(.footnote.bold())
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.chipMinHeight)
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
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.chipMinHeight)
                    .foregroundStyle(OutcomeTheme.Colors.accent)
                    .background(OutcomeTheme.Colors.track, in: .rect(cornerRadius: OutcomeTheme.Layout.chipRadius))
            }
            .buttonStyle(.plain)
        }
    }
}

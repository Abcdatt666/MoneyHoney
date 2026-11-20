import SwiftUI

/// Floating Liquid Glass "Xong" pill placed cleanly above the keyboard with intentional breathing room.
struct KeyboardDoneBar: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button(action: onDismiss) {
                Label("Xong", systemImage: "keyboard.chevron.compact.down")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 6)
                    .frame(minHeight: 36)
            }
            .tint(OutcomeTheme.Colors.accent)
            .modifier(GlassDoneStyleModifier())
            .frame(minHeight: OutcomeTheme.Layout.minTouchTarget)
        }
        .padding(.horizontal, OutcomeTheme.Layout.horizontalPadding)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}

private struct GlassDoneStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

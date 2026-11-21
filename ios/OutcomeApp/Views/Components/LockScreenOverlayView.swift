import SwiftUI

struct LockScreenOverlayView: View {
    let lockManager: BiometricLockManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(OutcomeTheme.Colors.accent)
                .frame(width: 72, height: 72)
                .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.tileRadius))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Outcome đang khóa")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                Text(lockManager.authErrorMessage ?? "Xác thực bằng Face ID hoặc mật mã để tiếp tục.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await lockManager.authenticate()
                }
            } label: {
                Label("Mở khóa", systemImage: "faceid")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: OutcomeTheme.Layout.primaryButtonHeight)
                    .background(OutcomeTheme.Colors.accent, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(lockManager.isAuthenticating)
            .padding(.top, 4)
        }
        .padding(24)
        .background(OutcomeTheme.Colors.card, in: .rect(cornerRadius: OutcomeTheme.Layout.cardRadius))
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutcomeTheme.Colors.canvas)
        .accessibilityElement(children: .contain)
    }
}

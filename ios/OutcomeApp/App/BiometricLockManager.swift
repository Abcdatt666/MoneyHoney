import Foundation
import LocalAuthentication
import Observation

@Observable
@MainActor
final class BiometricLockManager {
    var isLocked: Bool = false
    var isAuthenticating: Bool = false
    var authErrorMessage: String?

    func lockIfRequired(isEnabled: Bool) {
        if isEnabled {
            isLocked = true
            authErrorMessage = nil
        } else {
            isLocked = false
            authErrorMessage = nil
        }
    }

    func authenticate() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authErrorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = "Để sau"

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &error) else {
            // If device has neither Face ID nor Passcode configured, do not trap the user.
            isLocked = false
            isAuthenticating = false
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: "Mở khóa Outcome để xem số dư và giao dịch"
            )
            if success {
                isLocked = false
            }
        } catch {
            authErrorMessage = "Chưa xác thực được. Chạm nút bên dưới để thử lại."
        }
        isAuthenticating = false
    }
}

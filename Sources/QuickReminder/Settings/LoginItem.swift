import Foundation
import ServiceManagement

/// "Launch at login" through `SMAppService` (macOS 13+): no helper bundle, no deprecated
/// `LSSharedFileList`; the user can also flip it in System Settings → General → Login Items.
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()

    @Published private(set) var isEnabled = false
    /// True when macOS wants the user to approve the item in System Settings first.
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorText: String?

    private init() { refresh() }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        requiresApproval = status == .requiresApproval
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

import Observation
import ServiceManagement

/// The system registration is the source of truth, not a separate saved preference.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    private(set) var isUpdating = false
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        get { self.status == .enabled || self.status == .requiresApproval }
        set {
            guard newValue != self.isEnabled, !self.isUpdating else { return }
            self.isUpdating = true
            self.errorMessage = nil
            Task {
                defer {
                    self.refresh()
                    self.isUpdating = false
                }
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try await SMAppService.mainApp.unregister()
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func refresh() {
        self.status = SMAppService.mainApp.status
    }
}

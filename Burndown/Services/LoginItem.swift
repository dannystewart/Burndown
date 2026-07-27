//
//  LoginItem.swift
//  Burndown
//

import PolyKit
import ServiceManagement

/// Controls whether Burndown launches at login.
///
/// This matters more than it looks: the charts are built from samples Burndown records itself, so
/// history only accumulates while it's running.
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the change took effect.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Couldn't \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
            return false
        }
    }
}

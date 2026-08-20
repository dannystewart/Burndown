import PolyKit
import SwiftUI

// MARK: - BurndownApp

@main
struct BurndownApp: App {
    @State private var monitor: UsageMonitor = .init()
    @State private var preferences: Preferences = .shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: self.monitor)
        } label: {
            MenuBarLabel(monitor: self.monitor, preferences: self.preferences)
        }
        .menuBarExtraStyle(.window)

        // A menu-bar-only app needs Settings declared directly for openSettings to discover it.
        Settings {
            SettingsView(preferences: self.preferences, monitor: self.monitor)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - Logger

nonisolated let logger: PolyLog = .init(capture: true)

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

        Settings {
            SettingsView(preferences: self.preferences, monitor: self.monitor)
        }
    }
}

// MARK: - Logger

nonisolated let log: PolyLog = .init(appGroups: [
    .credentials,
    .network,
    .store,

], capture: true)

extension LogGroup {
    nonisolated static let credentials: LogGroup = .init("credentials", emoji: "🔑")
    nonisolated static let network: LogGroup = .init("network", emoji: "🌐")
    nonisolated static let store: LogGroup = .init("store", emoji: "💾")
}

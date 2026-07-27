//
//  BurndownApp.swift
//  Burndown
//

import SwiftUI

@main
struct BurndownApp: App {
    @State private var monitor = UsageMonitor()
    @State private var preferences = Preferences.shared

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

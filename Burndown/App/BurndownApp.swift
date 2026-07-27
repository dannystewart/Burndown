//
//  BurndownApp.swift
//  Burndown
//

import SwiftUI

@main
struct BurndownApp: App {
    @State private var monitor = UsageMonitor()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(monitor: self.monitor)
        } label: {
            MenuBarLabel(monitor: self.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

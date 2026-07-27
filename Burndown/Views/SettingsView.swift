//
//  SettingsView.swift
//  Burndown
//

import SwiftUI

/// The settings window, opened from the popover's gear.
///
/// A real window rather than more controls crammed into the popover: the popover is for reading a
/// number at a glance, and every row added to it competes with that. Settings are rare enough to
/// live somewhere they can grow.
struct SettingsView: View {
    let preferences: Preferences
    let monitor: UsageMonitor

    @State private var launchesAtLogin: Bool = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Layout", selection: Bindable(self.preferences).menuBarLayout) {
                    ForEach(MenuBarLayout.allCases) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }

                Toggle(isOn: Bindable(self.preferences).menuBarUsesColor) {
                    Text("Use color")
                    Text("Colors the percentage by how much headroom is left")
                }
            }

            Section {
                Toggle("Launch at login", isOn: self.$launchesAtLogin)
                    .onChange(of: self.launchesAtLogin) { _, enabled in
                        // The system is the source of truth here, not us: if registration is
                        // refused, snap the toggle back to what actually happened.
                        if !LoginItem.setEnabled(enabled) {
                            self.launchesAtLogin = LoginItem.isEnabled
                        }
                    }
            }

            Section("Providers") {
                ForEach(Provider.allCases) { provider in
                    LabeledContent(provider.displayName) {
                        Text(self.status(of: provider))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func status(of provider: Provider) -> String {
        let state = self.monitor.state(for: provider)
        if let error = state.error { return error.message }
        if let plan = state.snapshot?.plan { return "Signed in (\(plan.capitalized))" }
        return state.snapshot == nil ? "Checking…" : "Signed in"
    }
}

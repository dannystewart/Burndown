import SwiftUI

/// The settings window, opened from the popover's gear.
///
/// A real window rather than more controls crammed into the popover: the popover is for reading a
/// number at a glance, and every row added to it competes with that. Settings are rare enough to
/// live somewhere they can grow.
struct SettingsView: View {
    @State private var launchesAtLogin: Bool = LoginItem.isEnabled

    let preferences: Preferences
    let monitor: UsageMonitor

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: self.$launchesAtLogin)
                    .onChange(of: self.launchesAtLogin) { _, enabled in
                        // The system is the source of truth here, not us: if registration is
                        // refused, snap the toggle back to what actually happened.
                        if !LoginItem.setEnabled(enabled) {
                            self.launchesAtLogin = LoginItem.isEnabled
                        }
                    }
            }

            Section("Menu Bar") {
                Picker("Layout", selection: Bindable(self.preferences).menuBarLayout) {
                    ForEach(MenuBarLayout.allCases) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }

                Picker("Single-Line Format", selection: Bindable(self.preferences).singleLineFormat) {
                    ForEach(MenuBarFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Two-Line Format", selection: Bindable(self.preferences).stackedFormat) {
                    ForEach(MenuBarFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                Picker("Use Color", selection: Bindable(self.preferences).menuBarColorMode) {
                    ForEach(MenuBarColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
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
        .frame(width: 440, height: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func status(of provider: Provider) -> String {
        let state = self.monitor.state(for: provider)
        if let error = state.error { return error.message }
        if let plan = state.snapshot?.plan { return "Signed in (\(plan.capitalized))" }
        return state.snapshot == nil ? "Checking…" : "Signed in"
    }
}

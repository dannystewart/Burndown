import PolyKit
import SwiftUI

/// The settings window, opened from the popover's gear.
///
/// A real window rather than more controls crammed into the popover: the popover is for reading a
/// number at a glance, and every row added to it competes with that. Settings are rare enough to
/// live somewhere they can grow.
struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case about
    }

    @State private var launchesAtLogin: Bool = LoginItem.isEnabled
    @State private var selectedTab: SettingsTab = .general

    let preferences: Preferences
    let monitor: UsageMonitor

    var body: some View {
        PolySettingsTabs(selection: self.$selectedTab) {
            PolySettingsTab("General", systemImage: "gearshape", tag: SettingsTab.general) {
                self.generalSection
                self.menuBarSection
                self.providersSection
            }

            PolySettingsTab("About", systemImage: "info.circle", tag: SettingsTab.about) {
                PolyAboutView()
            }
        }
    }

    private var generalSection: some View {
        Section("General") {
            PolyToggleRow("Launch at Login", isOn: self.$launchesAtLogin)
                .onChange(of: self.launchesAtLogin) { _, enabled in
                    // The system is the source of truth here, not us: if registration is
                    // refused, snap the toggle back to what actually happened.
                    if !LoginItem.setEnabled(enabled) {
                        self.launchesAtLogin = LoginItem.isEnabled
                    }
                }
        }
    }

    private var menuBarSection: some View {
        Section("Menu Bar") {
            PolyPickerRow(
                "Layout",
                description: "Single Line shows the closest limit; Two Lines shows one provider per line",
                selection: Bindable(self.preferences).menuBarLayout,
            ) {
                ForEach(MenuBarLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            PolyPickerRow("Single-Line Format", selection: Bindable(self.preferences).singleLineFormat) {
                ForEach(MenuBarFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            PolyPickerRow("Two-Line Format", selection: Bindable(self.preferences).stackedFormat) {
                ForEach(MenuBarFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            PolyPickerRow("Use Color", selection: Bindable(self.preferences).menuBarColorMode) {
                ForEach(MenuBarColorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    private var providersSection: some View {
        Section("Providers") {
            ForEach(Provider.allCases) { provider in
                PolySettingsRow {
                    LabeledContent(provider.displayName) {
                        Text(self.status(of: provider))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func status(of provider: Provider) -> String {
        let state = self.monitor.state(for: provider)
        if let error = state.error { return error.message }
        if let plan = state.snapshot?.plan { return "Signed in (\(plan.capitalized))" }
        return state.snapshot == nil ? "Checking…" : "Signed in"
    }
}

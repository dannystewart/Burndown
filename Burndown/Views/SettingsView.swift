import PolyKit
import SwiftUI

/// The settings window, opened from the popover's gear.
struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case providers
        case about
    }

    @State private var selectedTab: SettingsTab = .general

    let preferences: Preferences
    let monitor: UsageMonitor

    private var recorderStatus: String {
        if let connectionError = self.monitor.connectionError {
            return "Unavailable: \(connectionError)"
        }
        return self.monitor.backgroundStatus.description
    }

    private var recorderStatusColor: Color {
        self.monitor.backgroundStatus == .enabled && self.monitor.connectionError == nil ? .secondary : .orange
    }

    var body: some View {
        PolySettingsTabs(selection: self.$selectedTab) {
            PolySettingsTab("General", systemImage: "gearshape", tag: SettingsTab.general) {
                self.menuBarSection
            }

            PolySettingsTab("Providers", systemImage: "cpu", tag: SettingsTab.providers) {
                self.providersSection
            }

            PolySettingsTab("About", systemImage: "info.circle", tag: SettingsTab.about) {
                self.backgroundRecordingSection
                PolyAboutView()
            }
        }
    }

    private var backgroundRecordingSection: some View {
        Section("Background Recording") {
            PolySettingsRow {
                LabeledContent("Recorder") {
                    Text(self.recorderStatus)
                        .foregroundStyle(self.recorderStatusColor)
                }
            }

            if self.monitor.backgroundStatus.needsSystemSettings {
                PolySettingsRow {
                    Button {
                        BackgroundService.openLoginItemsSettings()
                    } label: {
                        Label("Open Login Items Settings", systemImage: "gearshape")
                    }
                }
            } else if self.monitor.backgroundStatus != .enabled || self.monitor.connectionError != nil {
                PolySettingsRow {
                    Button {
                        Task { await self.monitor.retryBackgroundService() }
                    } label: {
                        Label("Retry Background Recorder", systemImage: "arrow.clockwise")
                    }
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

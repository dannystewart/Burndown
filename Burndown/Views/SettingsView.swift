import PolyKit
import SwiftUI

/// The settings window, opened from the popover's gear.
struct SettingsView: View {
    private enum SettingsTab: Hashable {
        case general
        case providers
    }

    @State private var selectedTab: SettingsTab = .general
    @State private var ollamaCookie = ""

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
                self.backgroundMonitorSection
            }

            PolySettingsTab("Providers", systemImage: "cpu", tag: SettingsTab.providers) {
                self.providersSection
            }
        }
    }

    private var backgroundMonitorSection: some View {
        Section("Background Monitor") {
            PolySettingsRow {
                LabeledContent("Status") {
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
                description: "Single Provider shows one provider; Two Providers shows one per row",
                selection: Bindable(self.preferences).menuBarLayout,
            ) {
                ForEach(MenuBarLayout.allCases) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            PolyPickerRow("Preferred Provider", selection: Bindable(self.preferences).preferredProvider) {
                ForEach(MenuBarProviderSelection.allCases) { selection in
                    Text(selection.displayName).tag(selection)
                }
            }

            if self.preferences.menuBarLayout == .twoProviders {
                PolyPickerRow("Preferred Second Provider", selection: Bindable(self.preferences).preferredSecondProvider) {
                    ForEach(MenuBarProviderSelection.allCases) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
            }

            PolyPickerRow("Format", selection: Bindable(self.preferences).menuBarFormat) {
                ForEach(MenuBarFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }

            PolyPickerRow("Show Using Color", selection: Bindable(self.preferences).menuBarColorMode) {
                ForEach(MenuBarColorMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
    }

    @ViewBuilder
    private var providersSection: some View {
        Section("Provider Visibility") {
            ForEach(Provider.allCases) { provider in
                PolySettingsRow {
                    LabeledContent(provider.displayName) {
                        HStack(spacing: 8) {
                            Text(self.status(of: provider))
                                .foregroundStyle(.secondary)

                            Button(self.isHidden(provider) ? "Show" : "Hide") {
                                self.toggleHidden(provider)
                            }
                        }
                    }
                }
            }
        }

        Section {
            PolySettingsRow {
                LabeledContent("Session Cookie") {
                    HStack(spacing: 8) {
                        SecureField(
                            text: self.$ollamaCookie,
                            prompt: Text("aid=...; __Secure-session=..."),
                        ) {
                            EmptyView()
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)

                        Button("Save") {
                            OllamaCloudCredentialStore.save(self.ollamaCookie)
                            self.ollamaCookie = ""
                        }
                        .disabled(
                            self.ollamaCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                && !OllamaCloudCredentialStore.isConfigured,
                        )
                    }
                }
            }
        } header: {
            Text("Ollama Cloud")
        } footer: {
            Text("Copy the Cookie header from ollama.com/settings in your browser and paste it here. Burndown only sends it to ollama.com.")
        }
        .onAppear {
            self.ollamaCookie = (try? OllamaCloudCredentialStore.load())?.cookie ?? ""
        }
    }

    private func status(of provider: Provider) -> String {
        let state = self.monitor.state(for: provider)
        if let error = state.error { return error.message }
        if let plan = state.snapshot?.plan { return "Signed in (\(plan.capitalized))" }
        return state.snapshot == nil ? "Checking…" : "Signed in"
    }

    private func isHidden(_ provider: Provider) -> Bool {
        self.preferences.hiddenProviders.contains(provider)
    }

    private func toggleHidden(_ provider: Provider) {
        if self.preferences.hiddenProviders.contains(provider) {
            self.preferences.hiddenProviders.remove(provider)
        } else {
            self.preferences.hiddenProviders.insert(provider)
        }
    }
}

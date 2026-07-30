import SwiftUI

// MARK: - PopoverView

struct PopoverView: View {
    let monitor: UsageMonitor

    var body: some View {
        // No ScrollView here: a menu bar window proposes no height, so a scroll view would accept
        // zero and collapse. The content is bounded at four cards, so it can size the window itself.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(self.monitor.visibleProviders) { provider in
                    ProviderSection(provider: provider, monitor: self.monitor)
                }
            }
            .padding(12)

            Divider()
            FooterView(monitor: self.monitor)
        }
        .frame(width: 380)
        .task {
            // Opening the popover is a strong signal the numbers are about to be read, but not a
            // reason to re-poll numbers that are seconds old.
            await self.monitor.refreshIfStale()
        }
    }
}

// MARK: - ProviderSection

/// One provider's windows, or an explanation of why there aren't any.
private struct ProviderSection: View {
    let provider: Provider
    let monitor: UsageMonitor

    private var state: ProviderState { self.monitor.state(for: self.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header

            switch self.state {
            case .loading:
                self.note("Loading…")

            case let .failed(error):
                self.failure(error)

            case let .loaded(snapshot):
                if snapshot.windows.isEmpty {
                    self.note("No quota windows reported")
                } else {
                    ForEach(snapshot.windows) { window in
                        QuotaCard(
                            provider: self.provider,
                            window: window,
                            samples: self.monitor.store.series(for: self.provider, window: window),
                        )
                    }
                    self.missingWindowNote(for: snapshot)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: self.provider.symbolName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(self.provider.tint)
            Text(self.provider.displayName)
                .font(.system(size: 13, weight: .semibold))
            if let plan = self.state.snapshot?.plan {
                Text(plan.capitalized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            Spacer()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Color.mutedText)
    }

    private func failure(_ error: UsageError) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(error.message)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)

            if let suggestion = error.recoverySuggestion(for: self.provider) {
                Text(suggestion)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.mutedText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }

    /// Says so when a provider reports one window but not the other.
    ///
    /// Codex reports its windows by length rather than by name, and on some plans only a weekly
    /// limit comes back at all. That's a real answer, not a failure, so it's worth stating plainly
    /// instead of leaving a blank card that looks broken.
    ///
    /// A window we've recorded before is a different situation: Anthropic drops the five-hour
    /// window's reset time between periods, so it disappears for a few minutes at a time. Calling
    /// that a plan limitation would be wrong, so recorded history picks the wording.
    @ViewBuilder
    private func missingWindowNote(for snapshot: UsageSnapshot) -> some View {
        let missing = QuotaWindowKind.allCases.filter { snapshot.window($0) == nil }
        let unsupported = missing.filter {
            !self.monitor.store.hasHistory(for: self.provider, kind: $0)
        }

        if !unsupported.isEmpty {
            self.note("No \(Self.list(unsupported)) window on this plan")
        } else if !missing.isEmpty {
            self.note("\(Self.list(missing)) window is between periods")
        }
    }

    private static func list(_ kinds: [QuotaWindowKind]) -> String {
        kinds.map(\.displayName).joined(separator: " or ")
    }
}

// MARK: - FooterView

private struct FooterView: View {
    @Environment(\.openSettings) private var openSettings

    let monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 8) {
            self.absenceNote

            Spacer()

            if let updated = self.monitor.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mutedText)
                    .monospacedDigit()
            }

            Button {
                // An accessory app has no menu bar of its own, so the settings window would open
                // behind everything without asking for activation first.
                NSApp.activate(ignoringOtherApps: true)
                self.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            Button {
                Task { await self.monitor.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(self.monitor.isRefreshing)
            .help("Refresh now")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Burndown")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Accounts for a provider that isn't set up here.
    ///
    /// Absent providers are dropped from the list entirely rather than shown as errors, but saying
    /// nothing at all would make it look like Burndown had quietly forgotten one. A line in the same
    /// register as the rest of the footer answers the question without asking to be read.
    @ViewBuilder
    private var absenceNote: some View {
        let missing = self.monitor.missingProviders
        if !missing.isEmpty {
            Text("No \(missing.map(\.displayName).joined(separator: " or ")) sign-in detected")
                .font(.system(size: 9))
                .foregroundStyle(Color.mutedText)
        }
    }
}

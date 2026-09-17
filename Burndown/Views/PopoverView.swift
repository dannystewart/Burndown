import SwiftUI

// MARK: - PopoverView

struct PopoverView: View {
    /// The measured height of the scrolling content, which the frame below is pinned to.
    @State private var contentHeight: CGFloat = 0

    let monitor: UsageMonitor

    private var recorderWarning: String? {
        if self.monitor.connectionError != nil {
            return "Background recording is unavailable"
        }
        switch self.monitor.backgroundStatus {
        case .checking, .enabled:
            return nil
        case .requiresApproval:
            return "Approve background recording in Settings"
        case .unavailable:
            return "Background recording is not running"
        }
    }

    /// The tallest the scrolling region is allowed to get, leaving room for the footer and a margin.
    ///
    /// Measured against the screen rather than fixed, so the popover uses a large display without
    /// running off a laptop one.
    private var maximumContentHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, visible * 0.7)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let recorderWarning {
                Label(recorderWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.1))
                Divider()
            }

            // A menu bar window proposes no height, so a scroll view left to size itself accepts zero
            // and collapses. Measuring the content and pinning the frame to it keeps the popover
            // exactly as tall as it needs to be — and scrolling only once it would outgrow the screen,
            // which four providers already can.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(self.monitor.visibleProviders) { provider in
                        ProviderSection(provider: provider, monitor: self.monitor)
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { self.contentHeight = $0 }
            }
            .frame(height: min(self.contentHeight, self.maximumContentHeight))
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            FooterView(monitor: self.monitor)
        }
        .frame(width: 380)
        .task {
            await self.monitor.refreshForPopover()
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
                    self.windows(of: snapshot)
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
                    .foregroundStyle(Color.mutedText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: .capsule)
            }
            Spacer()
        }
    }

    /// One window in full — with its chart — and the rest as a line each, shortest window first.
    ///
    /// Only the session window earns the full card, because the five-hour chart is the only one whose
    /// shape is worth the height; the weekly and monthly windows stay compact regardless. A provider
    /// with no session window (Codex, Cursor) features its nearest limit instead, so it still leads
    /// with a headline rather than a lone one-liner.
    ///
    /// A rolling session window that isn't active — OpenCode Go's, while nothing has been used in the
    /// last five hours — is dropped entirely rather than shown at 0%: its number is uninformative, its
    /// reset time is meaningless, and it has no history to chart. It reappears, as the primary card,
    /// the moment usage anchors it.
    @ViewBuilder
    private func windows(of snapshot: UsageSnapshot) -> some View {
        let ordered = snapshot.windows.sorted { $0.duration < $1.duration }
        let session = ordered.first { $0.kind == .session }
        let sessionActive = session.map(self.isActive) ?? false
        let hasSession = session != nil

        let featured: QuotaWindow? = if let session, sessionActive {
            session
        } else if hasSession {
            nil // A session exists but is idle: no full card, only the compact rows below.
        } else {
            // No session window: the provider's first reported window leads. For Cursor that's the
            // plan-spend window; for single-window providers it's simply their only window.
            ordered.first
        }

        if let featured {
            QuotaCard(
                provider: self.provider,
                window: featured,
                samples: self.monitor.series(for: self.provider, window: featured),
            )
        }

        ForEach(ordered.filter { self.isCompact($0, featured: featured, sessionActive: sessionActive) }) { window in
            CompactWindowRow(window: window)
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

    /// A rolling window is only worth showing once usage has anchored it; a fixed window always is.
    private func isActive(_ window: QuotaWindow) -> Bool {
        if self.provider.windowRolls(window.kind) {
            return window.usedPercent > 0
        }
        return true
    }

    /// Every window except the featured one gets a compact row — but an inactive session window is
    /// hidden outright rather than demoted to a row.
    private func isCompact(_ window: QuotaWindow, featured: QuotaWindow?, sessionActive: Bool) -> Bool {
        if window.id == featured?.id { return false }
        if window.kind == .session, !sessionActive { return false }
        return true
    }
}

// MARK: - CompactWindowRow

/// A secondary window in one line: how much is left, and when it comes back.
///
/// Deliberately not a shrunken `QuotaCard`. The card exists to answer whether the current pace is a
/// problem, which takes a chart and a projection; a window that isn't the nearest limit only has to
/// confirm it isn't in trouble, and the severity color does most of that before the text is read.
private struct CompactWindowRow: View {
    let window: QuotaWindow

    var body: some View {
        HStack(spacing: 6) {
            Text(self.window.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.mutedText)
                .tracking(0.6)

            Text(Format.percent(self.window.remainingPercent))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(self.window.severityColor)

            Spacer(minLength: 8)

            // Matches the card's countdown cadence so the two never disagree on screen.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(context.date)))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mutedText)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.2), in: .rect(cornerRadius: 6))
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

            if self.monitor.isRefreshing {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Updating…")
                }
                .font(.system(size: 9))
                .foregroundStyle(Color.mutedText)
            } else if let updated = self.monitor.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Text("Updated \(Format.age(context.date.timeIntervalSince(updated)))")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.mutedText)
                        .monospacedDigit()
                }
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
            .help("Close Burndown")
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

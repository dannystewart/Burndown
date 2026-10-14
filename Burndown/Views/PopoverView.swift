import SwiftUI

// MARK: - PopoverView

struct PopoverView: View {
    /// The measured height of the scrolling content, which the frame below is pinned to.
    @State private var contentHeight: CGFloat = 0

    let monitor: UsageMonitor
    let onOpenSettings: () -> Void

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

    /// The tallest the scrolling region is allowed to get, leaving room for the footer and a
    /// margin.
    ///
    /// Measured against the screen rather than fixed, so the popover uses a large display without
    /// running off a laptop one. `visibleFrame` already excludes the menu bar and Dock, so this
    /// only needs to hold back a small margin of its own.
    private var maximumContentHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, visible - 60)
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

            // A menu bar window proposes no height, so a scroll view left to size itself accepts
            // zero and collapses. Measuring the content and pinning the frame to it keeps the
            // popover exactly as tall as it needs to be — and scrolling only once it would outgrow
            // the screen, which four providers already can.
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(self.monitor.orderedVisibleProviders) { provider in
                        ProviderSection(provider: provider, monitor: self.monitor)
                    }
                    .reorderable()
                }
                .reorderContainer(for: Provider.self) { difference in
                    let destinationID: Provider.ID? = switch difference.destination.position {
                    case let .before(id): id
                    case .end: nil
                    }
                    Preferences.shared.moveProviders(withIDs: difference.sources, before: destinationID)
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { self.contentHeight = $0 }
            }
            .frame(height: min(self.contentHeight, self.maximumContentHeight))
            .scrollBounceBehavior(.basedOnSize)

            Divider()
            FooterView(monitor: self.monitor, onOpenSettings: self.onOpenSettings)
        }
        .frame(width: 380)
        // The system glass the menu bar window applies by default is too translucent to read over
        // arbitrary wallpapers; a regular material is what the rest of the menu bar ecosystem uses.
        .background(.regularMaterial)
        .task {
            await self.monitor.refreshForPopover()
        }
    }
}

// MARK: - ProviderSection

/// One provider's windows, or an explanation of why there aren't any.
private struct ProviderSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let provider: Provider
    let monitor: UsageMonitor

    private var state: ProviderState { self.monitor.state(for: self.provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
                    self.windows
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: self.provider.symbolName)
                .font(.system(size: 13, weight: .bold))
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

    /// Stable row identities let one card shrink while the selected card expands in place.
    private var windows: some View {
        let ordered = self.monitor.visibleWindows(for: self.provider)
        let featured = self.monitor.featuredWindow(for: self.provider)

        return VStack(spacing: 5) {
            ForEach(ordered) { window in
                let expanded = window.id == featured?.id
                Button {
                    guard !expanded else { return }
                    withAnimation(self.reduceMotion ? nil : .smooth(duration: 0.3)) {
                        Preferences.shared.selectWindow(window, for: self.provider)
                    }
                } label: {
                    QuotaCard(
                        provider: self.provider,
                        window: window,
                        samples: expanded ? self.monitor.series(for: self.provider, window: window) : [],
                        isExpanded: expanded,
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(expanded ? [.isSelected] : [])
            }
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
}

// MARK: - FooterView

private struct FooterView: View {
    @Environment(\.dismiss) private var dismiss

    let monitor: UsageMonitor
    let onOpenSettings: () -> Void

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
                self.dismiss()
                Task { @MainActor in
                    await Task.yield()
                    self.onOpenSettings()
                }
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
    /// nothing at all would make it look like Burndown had quietly forgotten one. A line in the
    /// same register as the rest of the footer answers the question without asking to be read.
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

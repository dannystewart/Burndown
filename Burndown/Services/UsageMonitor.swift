import Foundation
import PolyKit

/// Mirrors the background recorder's state into the menu app. Provider polling and disk writes
/// never happen here, so closing this process has no effect on history collection.
@Observable
@MainActor
final class UsageMonitor {
    private static let synchronizationInterval: TimeInterval = 15

    private(set) var backgroundStatus: RecorderServiceStatus = .checking
    private(set) var connectionError: String?
    private(set) var isRefreshing = false

    private var states: Dictionary = .init(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderState.loading) })
    private var samples: [UsageSample] = []
    private let client: AgentClient = .init()
    private var synchronizationTask: Task<Void, Never>?

    var lastUpdated: Date? {
        self.visibleProviders.compactMap { self.state(for: $0).snapshot?.capturedAt }.min()
    }

    /// Signed-in providers the person hasn't hidden. This is the set every menu bar surface — the
    /// icon label and the dropdown alike — draws from, so hiding a provider removes it from both at
    /// once.
    var visibleProviders: [Provider] {
        Provider.allCases.filter {
            self.state(for: $0).error != .notSignedIn && !Preferences.shared.hiddenProviders.contains($0)
        }
    }

    /// The popover order is manual: changing a timeframe or receiving new usage never moves a row.
    var orderedVisibleProviders: [Provider] {
        let visible = Set(self.visibleProviders)
        return Preferences.shared.providerOrder.filter { visible.contains($0) }
    }

    /// The providers whose quotas changed most recently. A changed reading is used instead of the
    /// polling timestamp so an idle provider does not displace the service the person just used.
    var recentlyActiveProviders: [Provider] {
        self.visibleProviders.sorted { lhs, rhs in
            let leftActivity = self.latestUsageChange(for: lhs)
            let rightActivity = self.latestUsageChange(for: rhs)
            if leftActivity != rightActivity {
                return (leftActivity ?? .distantPast) > (rightActivity ?? .distantPast)
            }
            return lhs.rawValue < rhs.rawValue
        }
    }

    var missingProviders: [Provider] {
        Provider.allCases.filter {
            self.state(for: $0).error == .notSignedIn && !Preferences.shared.hiddenProviders.contains($0)
        }
    }

    var soonestLimit: (provider: Provider, window: QuotaWindow)? {
        Provider.allCases
            .compactMap { provider in self.soonestLimit(for: provider).map { (provider: provider, window: $0) } }
            .min {
                BurnAnalysis.soonest(
                    $0.window,
                    samples: self.series(for: $0.provider, window: $0.window),
                    than: $1.window,
                    samples: self.series(for: $1.provider, window: $1.window),
                )
            }
    }

    init() {
        self.apply(UsageRepository.cachedDashboard())
        self.synchronizationTask = Task { [weak self] in
            await self?.startSynchronization()
        }
    }

    func refresh() async {
        guard self.backgroundStatus == .enabled else { return }
        await self.synchronize(.refresh)
    }

    func refreshForPopover() async {
        guard self.backgroundStatus == .enabled else { return }
        await self.synchronize(.refreshForPopover)
    }

    func retryBackgroundService() async {
        self.backgroundStatus = BackgroundService.prepare()
        guard self.backgroundStatus == .enabled else { return }
        await self.synchronize(.state)
    }

    func state(for provider: Provider) -> ProviderState {
        self.states[provider] ?? .loading
    }

    func series(for provider: Provider, window: QuotaWindow) -> [UsageSample] {
        // A fixed window's samples are grouped by shared reset time, so a new period starts a fresh
        // series. A rolling window has no such boundary and its `resetsAt` slides between samples,
        // so it's grouped by kind and bounded to the window's own span — the trailing five hours —
        // which also keeps the chart from plotting points that fall outside its time axis.
        let rolls = provider.windowRolls(window.kind)
        return self.samples
            .filter {
                guard $0.provider == provider, $0.kind == window.kind, $0.label == window.label else {
                    return false
                }
                return rolls
                    ? $0.at >= window.startedAt
                    : abs($0.resetsAt.timeIntervalSince(window.resetsAt)) < 120
            }
            .sorted { $0.at < $1.at }
    }

    func soonestLimit(for provider: Provider) -> QuotaWindow? {
        self.state(for: provider).snapshot?.windows.min {
            BurnAnalysis.soonest(
                $0,
                samples: self.series(for: provider, window: $0),
                than: $1,
                samples: self.series(for: provider, window: $1),
            )
        }
    }

    /// Idle rolling sessions have no useful reset or history. Keep the other windows selectable.
    func visibleWindows(for provider: Provider) -> [QuotaWindow] {
        let windows = self.state(for: provider).snapshot?.windows ?? []
        return windows
            .filter {
                $0.kind != .session || !provider.windowRolls($0.kind) || $0.usedPercent > 0
            }
            .sorted { $0.duration < $1.duration }
    }

    /// Both the expanded card and menu bar use this window. A missing selection falls back without
    /// overwriting the saved identity, so it returns when the provider reports that window again.
    func featuredWindow(for provider: Provider) -> QuotaWindow? {
        let windows = self.visibleWindows(for: provider)
        let selectedID = Preferences.shared.selectedWindowID(for: provider)
        return windows.first { $0.id == selectedID } ?? windows.first
    }

    private func latestUsageChange(for provider: Provider) -> Date? {
        let series = Dictionary(grouping: self.samples.filter { $0.provider == provider }) {
            "\($0.kind.rawValue)#\($0.label ?? "")"
        }
        return series.values
            .compactMap { samples -> Date? in
                let ordered = samples.sorted { $0.at < $1.at }
                return ordered.indices
                    .reversed()
                    .first { index in
                        ordered[index].usedPercent > 0
                            && (index == ordered.startIndex || ordered[index].usedPercent > ordered[index - 1].usedPercent)
                    }
                    .map { ordered[$0].at }
            }
            .max()
    }

    private func startSynchronization() async {
        self.backgroundStatus = BackgroundService.prepare()

        while !Task.isCancelled {
            self.backgroundStatus = BackgroundService.status
            if self.backgroundStatus == .enabled {
                await self.synchronize(.state)
            } else {
                self.connectionError = nil
            }
            try? await Task.sleep(for: .seconds(Self.synchronizationInterval))
        }
    }

    private func synchronize(_ operation: AgentOperation) async {
        if operation != .state {
            self.isRefreshing = true
        }
        defer {
            if operation != .state {
                self.isRefreshing = false
            }
        }

        do {
            let dashboard = try await self.client.request(operation)
            self.apply(dashboard)
            self.connectionError = nil
        } catch {
            self.connectionError = error.localizedDescription
            logger.warning("Couldn't synchronize with the background recorder: \(error.localizedDescription)")
        }
    }

    private func apply(_ dashboard: AgentDashboard) {
        for provider in Provider.allCases {
            if let state = dashboard.states[provider] {
                self.states[provider] = state
            }
        }
        self.samples = dashboard.samples
        self.isRefreshing = !dashboard.refreshingProviders.isEmpty
    }
}

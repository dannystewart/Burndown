//
//  UsageMonitor.swift
//  Burndown
//

import Foundation
import PolyKit

/// Polls both providers, records what it sees, and publishes the current state to the UI.
@Observable
@MainActor
final class UsageMonitor {
    /// Frequent enough to give the charts useful resolution, slow enough to be a good citizen.
    ///
    /// Anthropic throttles this endpoint, and a five-hour window only has a hundred percentage
    /// points to move through, so three minutes still yields far more detail than the data has.
    private static let pollInterval: Duration = .seconds(180)

    /// How long a manual refresh has to wait after the last one, so reopening the popover
    /// repeatedly can't hammer the providers.
    private static let manualRefreshCooldown: TimeInterval = 30

    /// Ceiling on the throttle backoff, reached after three consecutive 429s.
    private static let maximumBackoff: Int = 8

    private(set) var claude: ProviderState = .loading
    private(set) var codex: ProviderState = .loading
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing: Bool = false

    let store: SampleStore = .init()

    private var pollTask: Task<Void, Never>?

    /// Multiplier applied to the poll interval while a provider is throttling us.
    private(set) var backoff: Int = 1

    /// Polling starts with the app, not with the popover: history has to accumulate whether or not
    /// anyone is looking at it.
    init() {
        self.start()
    }

    /// Begins polling, refreshing immediately and then on a fixed interval.
    func start() {
        guard self.pollTask == nil else { return }
        self.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let backoff = self?.backoff ?? 1
                try? await Task.sleep(for: Self.pollInterval * backoff)
            }
        }
    }

    func stop() {
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    /// Reads both providers concurrently. Neither can block the other: a broken Codex sign-in still
    /// leaves Claude's numbers live.
    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        async let claudeState = Self.load(ClaudeUsageClient.fetch)
        async let codexState = Self.load(CodexUsageClient.fetch)
        let (claude, codex) = await (claudeState, codexState)

        self.claude = Self.merging(claude, over: self.claude)
        self.codex = Self.merging(codex, over: self.codex)

        for state in [claude, codex] {
            if let snapshot = state.snapshot {
                self.store.record(snapshot)
                self.lastUpdated = .now
            }
        }

        // Back off geometrically for as long as anyone is throttling us, and snap straight back to
        // the normal cadence once they stop.
        let throttled = [claude, codex].contains { $0.error == .rateLimited }
        self.backoff = throttled ? min(self.backoff * 2, Self.maximumBackoff) : 1
    }

    /// A manual refresh, ignored if the numbers are already fresh.
    func refreshIfStale() async {
        if let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < Self.manualRefreshCooldown {
            return
        }
        await self.refresh()
    }

    /// Keeps the last good reading when a failure is only temporary.
    private static func merging(_ new: ProviderState, over previous: ProviderState) -> ProviderState {
        guard case let .failed(error) = new, error.isTransient, previous.snapshot != nil else {
            return new
        }
        return previous
    }

    func state(for provider: Provider) -> ProviderState {
        switch provider {
            case .claude: self.claude
            case .codex: self.codex
        }
    }

    /// Providers that are actually set up on this machine.
    ///
    /// A provider whose CLI was never signed in here isn't a failure worth reporting — it's simply
    /// absent, and showing an error card for it would be noise on a machine that only ever uses one
    /// of the two.
    var visibleProviders: [Provider] {
        Provider.allCases.filter { self.state(for: $0).error != .notSignedIn }
    }

    var missingProviders: [Provider] {
        Provider.allCases.filter { self.state(for: $0).error == .notSignedIn }
    }

    /// The window closest to running out, across everything we can currently see.
    ///
    /// This is what the menu bar shows, so it should be whichever number would bite first.
    var tightestWindow: (provider: Provider, window: QuotaWindow)? {
        Provider.allCases
            .compactMap { provider in self.tightestWindow(for: provider).map { (provider: provider, window: $0) } }
            .min { $0.window.remainingPercent < $1.window.remainingPercent }
    }

    /// The window closest to running out for one provider.
    func tightestWindow(for provider: Provider) -> QuotaWindow? {
        self.state(for: provider).snapshot?.windows.min { $0.remainingPercent < $1.remainingPercent }
    }

    private nonisolated static func load(
        _ fetch: () async throws(UsageError) -> UsageSnapshot,
    ) async -> ProviderState {
        do {
            return .loaded(try await fetch())
        } catch {
            log.warning("Usage fetch failed: \(error.message)", group: .network)
            return .failed(error)
        }
    }
}

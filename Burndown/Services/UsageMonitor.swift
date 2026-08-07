import Foundation
import PolyKit

/// Polls both providers, records what it sees, and publishes the current state to the UI.
@Observable
@MainActor
final class UsageMonitor {
    /// Background polling stays conservative; opening the popover has a tighter freshness target.
    private static let backgroundRefreshInterval: TimeInterval = 180
    private static let popoverRefreshInterval: TimeInterval = 60

    private static let schedulerResolution: TimeInterval = 15

    /// How old a reading can be and still be worth showing as though it were current.
    ///
    /// Anthropic's throttle clears in under two minutes, so routine rate limiting should never be
    /// visible. Something still failing a quarter of an hour later is a real problem worth saying
    /// out loud.
    private static let stalenessGrace: TimeInterval = 15 * 60

    private(set) var claude: ProviderState = .loading
    private(set) var codex: ProviderState = .loading

    let store: SampleStore = .init()

    private let cache: SnapshotCache = .init()

    private var pollTask: Task<Void, Never>? = nil
    private var lastAttempt: [Provider: Date] = [:]
    private var refreshingProviders: Set<Provider> = []

    var isRefreshing: Bool { !self.refreshingProviders.isEmpty }

    /// The oldest reading currently represented in the popover. A shared mutable timestamp can be
    /// advanced by one provider and accidentally make stale data from the other look current.
    var lastUpdated: Date? {
        self.visibleProviders.compactMap { self.state(for: $0).snapshot?.capturedAt }.min()
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

    /// The limit closest to biting, across everything we can currently see.
    ///
    /// This is what a single-line menu bar shows, so it should be whichever number would bite first.
    var soonestLimit: (provider: Provider, window: QuotaWindow)? {
        Provider.allCases
            .compactMap { provider in self.soonestLimit(for: provider).map { (provider: provider, window: $0) } }
            .min {
                BurnAnalysis.soonest(
                    $0.window,
                    samples: self.store.series(for: $0.provider, window: $0.window),
                    than: $1.window,
                    samples: self.store.series(for: $1.provider, window: $1.window),
                )
            }
    }

    /// Polling starts with the app, not with the popover: history has to accumulate whether or not
    /// anyone is looking at it.
    ///
    /// The cached readings go up first so a launch that lands on a throttle still has something to
    /// show, rather than greeting you with an error about a limit that clears in two minutes.
    init() {
        for provider in Provider.allCases {
            if let snapshot = self.cache[provider], Self.isFreshEnough(snapshot) {
                self.setState(.loaded(snapshot), for: provider)
            }
        }
        self.start()
    }

    /// Whether a reading is recent enough to stand in for one we couldn't take.
    private static func isFreshEnough(_ snapshot: UsageSnapshot) -> Bool {
        Date.now.timeIntervalSince(snapshot.capturedAt) < self.stalenessGrace
    }

    private nonisolated static func load(_ provider: Provider) async -> ProviderState {
        do {
            let snapshot = switch provider {
            case .claude: try await ClaudeUsageClient.fetch()
            case .codex: try await CodexUsageClient.fetch()
            }
            return .loaded(snapshot)
        } catch {
            log.warning("Usage fetch failed: \(error.message)", group: .network)
            return .failed(error)
        }
    }

    /// Checks frequently enough to notice when a reading comes due without fetching more often than
    /// the background interval. Cached readings are evaluated immediately at launch.
    func start() {
        guard self.pollTask == nil else { return }
        self.pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfOlder(than: Self.backgroundRefreshInterval)
                try? await Task.sleep(for: .seconds(Self.schedulerResolution))
            }
        }
    }

    func stop() {
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    /// Reads both providers concurrently and publishes each result as soon as it arrives.
    /// The refresh button deliberately bypasses the automatic retry floor.
    func refresh() async {
        await self.refresh(Provider.allCases)
    }

    /// Opening the popover asks for substantially fresher data than passive background polling.
    func refreshForPopover() async {
        await self.refreshIfOlder(than: Self.popoverRefreshInterval)
    }

    func state(for provider: Provider) -> ProviderState {
        switch provider {
        case .claude: self.claude
        case .codex: self.codex
        }
    }

    /// The limit this provider will hit soonest — the one worth a menu bar's worth of space.
    func soonestLimit(for provider: Provider) -> QuotaWindow? {
        self.state(for: provider).snapshot?.windows.min {
            BurnAnalysis.soonest(
                $0,
                samples: self.store.series(for: provider, window: $0),
                than: $1,
                samples: self.store.series(for: provider, window: $1),
            )
        }
    }

    private func refreshIfOlder(than maximumAge: TimeInterval) async {
        let now = Date.now
        let due = Provider.allCases.filter { provider in
            guard !self.refreshingProviders.contains(provider) else { return false }
            // A failed attempt obeys the same interval as a successful reading. Popover opens use
            // the tighter interval, while passive retries remain on the conservative cadence.
            if let attempted = self.lastAttempt[provider], now.timeIntervalSince(attempted) < maximumAge {
                return false
            }
            guard let capturedAt = self.state(for: provider).snapshot?.capturedAt else { return true }
            return now.timeIntervalSince(capturedAt) >= maximumAge
        }
        await self.refresh(due)
    }

    private func refresh(_ providers: [Provider]) async {
        let providers = providers.filter { !self.refreshingProviders.contains($0) }
        guard !providers.isEmpty else { return }

        let attemptedAt = Date.now
        for provider in providers {
            self.lastAttempt[provider] = attemptedAt
            self.refreshingProviders.insert(provider)
        }

        await withTaskGroup(of: (Provider, ProviderState).self) { group in
            for provider in providers {
                group.addTask { await (provider, Self.load(provider)) }
            }
            for await (provider, result) in group {
                self.apply(result, for: provider)
                self.refreshingProviders.remove(provider)
            }
        }
    }

    /// Takes the result of one provider's fetch and decides what the UI should say about it.
    ///
    /// Rate limiting is routine on both endpoints, so a transient failure doesn't replace a reading
    /// that's still recent — it just leaves the old one up, with the footer's timestamp as the
    /// honest record of how old it is. Only once nothing has succeeded for `stalenessGrace` does
    /// the failure become the thing worth showing.
    private func apply(_ result: ProviderState, for provider: Provider) {
        switch result {
        case let .loaded(snapshot):
            self.setState(.loaded(snapshot), for: provider)
            self.cache.store(snapshot)
            self.store.record(snapshot)

        case let .failed(error) where error.isTransient:
            let lastGood = self.state(for: provider).snapshot ?? self.cache[provider]
            if let lastGood, Self.isFreshEnough(lastGood) {
                self.setState(.loaded(lastGood), for: provider)
            } else {
                self.setState(.failed(error), for: provider)
            }

        // A credential problem isn't going to age out, so there's nothing to wait for.
        case let .failed(error):
            self.setState(.failed(error), for: provider)

        case .loading:
            break
        }
    }

    private func setState(_ state: ProviderState, for provider: Provider) {
        switch provider {
        case .claude: self.claude = state
        case .codex: self.codex = state
        }
    }
}

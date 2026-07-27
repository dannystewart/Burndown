import Foundation
import PolyKit

/// Polls both providers, records what it sees, and publishes the current state to the UI.
@Observable
@MainActor
final class UsageMonitor {
    /// The minimum spacing between readings, and the only such rule in the app.
    ///
    /// Frequent enough to give the charts useful resolution, slow enough to be a good citizen:
    /// Anthropic throttles this endpoint, and a five-hour window only has a hundred percentage
    /// points to move through, so three minutes still yields far more detail than the data has.
    ///
    /// Every automatic trigger measures against the age of the reading we already have rather than
    /// against its own clock — so launching, reopening the popover, and simply waiting all obey the
    /// same limit, and none of them can be used to fetch faster by repetition. The refresh button
    /// is the deliberate exception.
    private static let pollInterval: TimeInterval = 180

    /// Ceiling on the throttle backoff.
    ///
    /// Deliberately shorter than `stalenessGrace`: backing off for longer than we're willing to
    /// show a stale number would mean reporting a problem we hadn't recently retried.
    private static let maximumBackoff: Int = 4

    /// How old a reading can be and still be worth showing as though it were current.
    ///
    /// Anthropic's throttle clears in under two minutes, so routine rate limiting should never be
    /// visible. Something still failing a quarter of an hour later is a real problem worth saying
    /// out loud.
    private static let stalenessGrace: TimeInterval = 15 * 60

    private(set) var claude: ProviderState = .loading
    private(set) var codex: ProviderState = .loading
    private(set) var lastUpdated: Date? = nil
    private(set) var isRefreshing: Bool = false

    let store: SampleStore = .init()

    /// Multiplier applied to the poll interval while a provider is throttling us.
    private(set) var backoff: Int = 1

    private let cache: SnapshotCache = .init()

    private var pollTask: Task<Void, Never>? = nil

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

    /// How long until the reading we're showing is due to be replaced.
    ///
    /// Zero means fetch now — either it's already due, or we have nothing to show. This is the one
    /// gate every automatic trigger goes through, and because it's measured from the reading rather
    /// than from the trigger, quitting and relaunching gets you no closer to a fetch than waiting.
    private var timeUntilDue: TimeInterval {
        guard let lastUpdated else { return 0 }
        return max(0, Self.pollInterval - Date.now.timeIntervalSince(lastUpdated))
    }

    /// Polling starts with the app, not with the popover: history has to accumulate whether or not
    /// anyone is looking at it.
    ///
    /// The cached readings go up first so a launch that lands on a throttle still has something to
    /// show, rather than greeting you with an error about a limit that clears in two minutes.
    init() {
        var seeded = [Date]()
        for provider in Provider.allCases {
            if let snapshot = self.cache[provider], Self.isFreshEnough(snapshot) {
                self.setState(.loaded(snapshot), for: provider)
                seeded.append(snapshot.capturedAt)
            }
        }
        // The oldest of the two, so `lastUpdated` never overstates how current the popover is —
        // and so the deferred first poll is timed by whichever provider needs it soonest.
        self.lastUpdated = seeded.min()
        self.start()
    }

    /// Whether a reading is recent enough to stand in for one we couldn't take.
    private static func isFreshEnough(_ snapshot: UsageSnapshot) -> Bool {
        Date.now.timeIntervalSince(snapshot.capturedAt) < self.stalenessGrace
    }

    private nonisolated static func load(
        _ fetch: () async throws(UsageError) -> UsageSnapshot,
    ) async -> ProviderState {
        do {
            return try await .loaded(fetch())
        } catch {
            log.warning("Usage fetch failed: \(error.message)", group: .network)
            return .failed(error)
        }
    }

    /// Begins polling: immediately, or once the cached reading we launched with comes due.
    func start() {
        guard self.pollTask == nil else { return }
        self.pollTask = Task { [weak self] in
            if let wait = self?.timeUntilDue, wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            while !Task.isCancelled {
                await self?.refresh()
                let backoff = self?.backoff ?? 1
                try? await Task.sleep(for: .seconds(Self.pollInterval * Double(backoff)))
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

        self.apply(claude, for: .claude)
        self.apply(codex, for: .codex)

        // Back off geometrically for as long as anyone is throttling us, and snap straight back to
        // the normal cadence once they stop.
        let throttled = [claude, codex].contains { $0.error == .rateLimited }
        self.backoff = throttled ? min(self.backoff * 2, Self.maximumBackoff) : 1
    }

    /// What opening the popover does: top up the numbers, but only if they're actually due.
    func refreshIfStale() async {
        guard self.timeUntilDue == 0 else { return }
        await self.refresh()
    }

    func state(for provider: Provider) -> ProviderState {
        switch provider {
        case .claude: self.claude
        case .codex: self.codex
        }
    }

    /// The window closest to running out for one provider.
    func tightestWindow(for provider: Provider) -> QuotaWindow? {
        self.state(for: provider).snapshot?.windows.min { $0.remainingPercent < $1.remainingPercent }
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
            self.lastUpdated = snapshot.capturedAt

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

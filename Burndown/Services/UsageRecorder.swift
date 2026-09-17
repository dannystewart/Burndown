import Foundation
import PolyKit

/// Owns provider polling and persistence inside the launchd-managed process.
actor UsageRecorder {
    private static let backgroundRefreshInterval: TimeInterval = 180
    private static let popoverRefreshInterval: TimeInterval = 60
    private static let schedulerResolution: TimeInterval = 15
    private static let stalenessGrace: TimeInterval = 15 * 60

    private let repository: UsageRepository = .init()
    private var states: Dictionary = .init(uniqueKeysWithValues: Provider.allCases.map { ($0, ProviderState.loading) })
    private var lastAttempt: [Provider: Date] = [:]
    private var refreshingProviders: Set<Provider> = []
    private var schedulerTask: Task<Void, Never>? = nil

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
            logger.warning("Usage fetch failed: \(error.message)")
            return .failed(error)
        }
    }

    func start() async {
        guard self.schedulerTask == nil else { return }

        for (provider, snapshot) in await self.repository.snapshots {
            self.states[provider] = .loaded(snapshot)
        }

        self.schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfOlder(than: Self.backgroundRefreshInterval)
                try? await Task.sleep(for: .seconds(Self.schedulerResolution))
            }
        }
        logger.info("Background recorder started.")
    }

    func dashboard() async -> AgentDashboard {
        await AgentDashboard(
            states: self.states,
            samples: self.repository.samples,
            refreshingProviders: self.refreshingProviders,
            lastAttempts: self.lastAttempt,
            generatedAt: .now,
        )
    }

    func handle(_ operation: AgentOperation) async -> AgentDashboard {
        switch operation {
        case .state:
            break
        case .refresh:
            await self.refresh(Provider.allCases)
        case .refreshForPopover:
            await self.refreshIfOlder(than: Self.popoverRefreshInterval)
        }
        return await self.dashboard()
    }

    private func refreshIfOlder(than maximumAge: TimeInterval) async {
        let now = Date.now
        let due = Provider.allCases.filter { provider in
            guard !self.refreshingProviders.contains(provider) else { return false }
            if let attempted = self.lastAttempt[provider], now.timeIntervalSince(attempted) < maximumAge {
                return false
            }
            guard let capturedAt = self.states[provider]?.snapshot?.capturedAt else { return true }
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
                await self.apply(result, for: provider)
                self.refreshingProviders.remove(provider)
            }
        }
    }

    private func apply(_ result: ProviderState, for provider: Provider) async {
        switch result {
        case let .loaded(snapshot):
            await self.repository.record(snapshot)
            self.states[provider] = .loaded(snapshot)

        case let .failed(error) where error.isTransient:
            let cachedSnapshots = await self.repository.snapshots
            let lastGood = self.states[provider]?.snapshot ?? cachedSnapshots[provider]
            if let lastGood, Self.isFreshEnough(lastGood) {
                self.states[provider] = .loaded(lastGood)
            } else {
                self.states[provider] = .failed(error)
            }

        case let .failed(error):
            self.states[provider] = .failed(error)

        case .loading:
            break
        }
    }
}

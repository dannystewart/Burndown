import Foundation
import PolyKit

// MARK: - UsageSample

/// A single observation of one quota window.
nonisolated struct UsageSample: Codable, Sendable, Hashable {
    let provider: Provider
    let kind: QuotaWindowKind
    let at: Date
    let usedPercent: Double
    /// Identifies which window period this belongs to, so a reset starts a fresh series.
    let resetsAt: Date
    /// Matches the source window's label, so metrics that share a kind (Cursor's plan/auto/API)
    /// keep separate series. Nil for single-metric windows.
    let label: String?

    var remainingPercent: Double { (100 - self.usedPercent).clamped(to: 0 ... 100) }

    init(provider: Provider, kind: QuotaWindowKind, at: Date, usedPercent: Double, resetsAt: Date, label: String? = nil) {
        self.provider = provider
        self.kind = kind
        self.at = at
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.label = label
    }
}

// MARK: - UsageRepository

/// The agent's single-writer store for current snapshots and historical observations.
///
/// Snapshots and samples are committed in one atomic file replacement. That keeps the dashboard and
/// its chart history at the same generation and guarantees that a successful record call has
/// reached disk before the agent publishes it.
actor UsageRepository {
    private struct Archive: Codable {
        var snapshots: [Provider: UsageSnapshot]
        var samples: [UsageSample]
    }

    /// How long a flat stretch can go before a point is recorded anyway.
    private static let keyframeInterval: TimeInterval = 15 * 60
    /// History older than this is discarded. Current charts do not look back further than a week.
    private static let retention: TimeInterval = 8 * 86400
    /// Smallest change worth recording, in percentage points.
    private static let significantChange: Double = 0.009

    private static var storageDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Burndown", directoryHint: .isDirectory)
    }

    private var archive: Archive
    private let fileURL: URL

    var snapshots: [Provider: UsageSnapshot] { self.archive.snapshots }
    var samples: [UsageSample] { self.archive.samples }

    init() {
        let directory = Self.storageDirectory
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Couldn't create usage storage: \(error.localizedDescription)")
        }

        self.fileURL = directory.appending(path: "usage-state.json", directoryHint: .notDirectory)
        var archive = Self.loadArchive(from: directory)
        Self.prune(&archive.samples)
        self.archive = archive
    }

    /// Reads old on-disk state for the UI while the agent is unavailable or awaiting approval.
    nonisolated static func cachedDashboard() -> AgentDashboard {
        let archive = self.loadArchive(from: self.storageDirectory)
        let states = Dictionary(uniqueKeysWithValues: archive.snapshots.map { ($0.key, ProviderState.loaded($0.value)) })
        return AgentDashboard(
            states: states,
            samples: archive.samples,
            refreshingProviders: [],
            lastAttempts: [:],
            generatedAt: .now,
        )
    }

    private static func loadArchive(from directory: URL) -> Archive {
        let archiveURL = directory.appending(path: "usage-state.json", directoryHint: .notDirectory)
        if let data = try? Data(contentsOf: archiveURL), let archive = try? JSONDecoder().decode(Archive.self, from: data) {
            return archive
        }

        // Migrate the two files written by versions before the recorder became a separate process.
        let snapshotURL = directory.appending(path: "snapshots.json", directoryHint: .notDirectory)
        let sampleURL = directory.appending(path: "samples.json", directoryHint: .notDirectory)
        let snapshots = (try? Data(contentsOf: snapshotURL))
            .flatMap { try? JSONDecoder().decode([Provider: UsageSnapshot].self, from: $0) } ?? [:]
        let samples = (try? Data(contentsOf: sampleURL))
            .flatMap { try? JSONDecoder().decode([UsageSample].self, from: $0) } ?? []
        return Archive(snapshots: snapshots, samples: samples)
    }

    private static func appendSamples(from snapshot: UsageSnapshot, to samples: inout [UsageSample]) {
        for window in snapshot.windows {
            let previous = samples.last {
                $0.provider == snapshot.provider && $0.kind == window.kind && $0.label == window.label
            }
            let sample = UsageSample(
                provider: snapshot.provider,
                kind: window.kind,
                at: snapshot.capturedAt,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                label: window.label,
            )

            guard let previous else {
                samples.append(sample)
                continue
            }

            // A rolling window has no fixed reset boundary — `resetsAt` slides as usage ages out
            // and, while idle, creeps forward every poll. It is one continuous series with no
            // periods to separate, so the synthetic zero-anchor sawtooth below (which keys off
            // `resetsAt`) would fire on every poll and fill the history with noise. Record its
            // curve directly instead.
            if !snapshot.provider.windowRolls(window.kind) {
                let isSamePeriod = abs(previous.resetsAt.timeIntervalSince(window.resetsAt)) < 120
                if !isSamePeriod {
                    samples.append(
                        UsageSample(
                            provider: snapshot.provider,
                            kind: window.kind,
                            at: window.startedAt,
                            usedPercent: 0,
                            resetsAt: window.resetsAt,
                            label: window.label,
                        ),
                    )
                    samples.append(sample)
                    logger.info("\(snapshot.provider.displayName) \(window.kind.displayName) window reset.")
                    continue
                }
            }

            let moved = abs(sample.usedPercent - previous.usedPercent) >= self.significantChange
            let stale = sample.at.timeIntervalSince(previous.at) >= self.keyframeInterval
            if moved || stale {
                samples.append(sample)
            }
        }
    }

    private static func prune(_ samples: inout [UsageSample]) {
        let cutoff = Date.now.addingTimeInterval(-self.retention)
        samples.removeAll { $0.at < cutoff }
    }

    /// Records a provider reading and atomically commits it with any resulting history points.
    func record(_ snapshot: UsageSnapshot) {
        var next = self.archive
        next.snapshots[snapshot.provider] = snapshot
        Self.appendSamples(from: snapshot, to: &next.samples)
        Self.prune(&next.samples)

        do {
            let data = try JSONEncoder().encode(next)
            try data.write(to: self.fileURL, options: .atomic)
            self.archive = next
        } catch {
            logger.error("Couldn't save usage state: \(error.localizedDescription)")
        }
    }

    private func prune() {
        Self.prune(&self.archive.samples)
    }
}

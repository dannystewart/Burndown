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

    var remainingPercent: Double { (100 - self.usedPercent).clamped(to: 0 ... 100) }
}

// MARK: - SampleStore

/// The recorded history that the burndown charts are drawn from.
///
/// Quota is a step function: it sits flat while you aren't working and jumps when you are. Storing
/// every poll would mean thousands of identical rows for no extra fidelity, so a sample is kept
/// only when the number actually moves, plus a periodic keyframe so long flat stretches still have
/// points to draw between.
@Observable
@MainActor
final class SampleStore {
    /// How long a flat stretch can go before a point is recorded anyway.
    private static let keyframeInterval: TimeInterval = 15 * 60
    /// History older than this is discarded — nothing in the UI looks back further than a week.
    private static let retention: TimeInterval = 8 * 86400
    /// Smallest change worth recording, in percentage points.
    private static let significantChange: Double = 0.009

    private(set) var samples: [UsageSample] = []

    private let fileURL: URL
    private var writeTask: Task<Void, Never>? = nil

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Burndown", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appending(path: "samples.json", directoryHint: .notDirectory)
        self.load()
    }

    /// Records whatever is new in a snapshot, and returns whether anything was stored.
    @discardableResult
    func record(_ snapshot: UsageSnapshot) -> Bool {
        var didChange = false

        for window in snapshot.windows {
            let previous = self.samples.last { $0.provider == snapshot.provider && $0.kind == window.kind }
            let sample = UsageSample(
                provider: snapshot.provider,
                kind: window.kind,
                at: snapshot.capturedAt,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
            )

            guard let previous else {
                self.samples.append(sample)
                didChange = true
                continue
            }

            let isSamePeriod = abs(previous.resetsAt.timeIntervalSince(window.resetsAt)) < 120

            if !isSamePeriod {
                // We watched this window roll over, so we know for certain it began empty. That
                // anchor is only ever synthesized when the reset was actually observed — starting
                // Burndown mid-window leaves the earlier part of the chart honestly blank.
                self.samples.append(
                    UsageSample(
                        provider: snapshot.provider,
                        kind: window.kind,
                        at: window.startedAt,
                        usedPercent: 0,
                        resetsAt: window.resetsAt,
                    ),
                )
                self.samples.append(sample)
                didChange = true
                log.info("\(snapshot.provider.displayName) \(window.kind.displayName) window reset.", group: .store)
                continue
            }

            let moved = abs(sample.usedPercent - previous.usedPercent) >= Self.significantChange
            let stale = sample.at.timeIntervalSince(previous.at) >= Self.keyframeInterval

            if moved || stale {
                self.samples.append(sample)
                didChange = true
            }
        }

        if didChange {
            self.prune()
            self.persist()
        }
        return didChange
    }

    /// The recorded history for the period the given window is currently in.
    func series(for provider: Provider, window: QuotaWindow) -> [UsageSample] {
        self.samples
            .filter {
                $0.provider == provider
                    && $0.kind == window.kind
                    && abs($0.resetsAt.timeIntervalSince(window.resetsAt)) < 120
            }
            .sorted { $0.at < $1.at }
    }

    /// Whether this provider has ever reported the given window kind within the retention period.
    ///
    /// Distinguishes a plan that genuinely has no such window from one that's momentarily between
    /// periods. Anthropic returns a null `resets_at` for a five-hour window that has expired but
    /// not yet restarted, which lasted about eighteen minutes when observed.
    func hasHistory(for provider: Provider, kind: QuotaWindowKind) -> Bool {
        self.samples.contains { $0.provider == provider && $0.kind == kind }
    }

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-Self.retention)
        self.samples.removeAll { $0.at < cutoff }
    }

    private func load() {
        guard let data = try? Data(contentsOf: self.fileURL) else { return }
        do {
            self.samples = try JSONDecoder().decode([UsageSample].self, from: data)
            self.prune()
            log.debug("Loaded \(self.samples.count) samples.", group: .store)
        } catch {
            log.warning("Discarding unreadable sample history: \(error.localizedDescription)", group: .store)
        }
    }

    /// Writes off the main actor, collapsing bursts so a run of quick polls writes once.
    private func persist() {
        guard let data = try? JSONEncoder().encode(self.samples) else { return }
        let url = self.fileURL
        self.writeTask?.cancel()
        self.writeTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                log.error("Couldn't save sample history: \(error.localizedDescription)", group: .store)
            }
        }
    }
}

import Foundation
import PolyKit

/// The last good reading from each provider, kept across launches.
///
/// Both endpoints throttle, and a throttle that lands on a cold start would otherwise leave the app
/// with nothing to show at all. A slightly old number with a timestamp on it is far more useful than
/// an error, so the last reading survives quitting.
@MainActor
final class SnapshotCache {
    private var snapshots: [Provider: UsageSnapshot] = [:]

    private let fileURL: URL
    private var writeTask: Task<Void, Never>? = nil

    init() {
        let directory = URL.applicationSupportDirectory.appending(path: "Burndown", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appending(path: "snapshots.json", directoryHint: .notDirectory)
        self.load()
    }

    subscript(provider: Provider) -> UsageSnapshot? {
        self.snapshots[provider]
    }

    func store(_ snapshot: UsageSnapshot) {
        self.snapshots[snapshot.provider] = snapshot
        self.persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: self.fileURL) else { return }
        do {
            self.snapshots = try JSONDecoder().decode([Provider: UsageSnapshot].self, from: data)
        } catch {
            logger.warning("Discarding unreadable snapshot cache: \(error.localizedDescription)")
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(self.snapshots) else { return }
        let url = self.fileURL
        self.writeTask?.cancel()
        self.writeTask = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Couldn't save snapshot cache: \(error.localizedDescription)")
            }
        }
    }
}

@testable import Burndown
import Foundation
import Testing

struct BurnAnalysisTests {
    @Test(arguments: [
        (QuotaWindowKind.session, 5 * 3600.0, 5.0),
        (QuotaWindowKind.weekly, 7 * 86400.0, 1.0),
    ])
    func `opening usage does not create A projection`(kind: QuotaWindowKind, duration: TimeInterval, used: Double) {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let window = QuotaWindow(kind: kind, usedPercent: used, resetsAt: now.addingTimeInterval(duration), duration: duration)
        let openingReading = self.sample(for: window, at: now, used: used)

        let analysis = BurnAnalysis(window: window, samples: [openingReading], now: now.addingTimeInterval(3600))

        #expect(!analysis.willRunOutBeforeReset)
        #expect(analysis.projectionPoints.isEmpty)
    }

    @Test
    func `continued usage can create exhaustion warning`() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let duration = 5 * 3600.0
        let window = QuotaWindow(
            kind: .session,
            usedPercent: 15,
            resetsAt: startedAt.addingTimeInterval(duration),
            duration: duration,
        )
        let samples = [
            self.sample(for: window, at: startedAt, used: 5),
            self.sample(for: window, at: startedAt.addingTimeInterval(30 * 60), used: 15),
        ]

        let analysis = BurnAnalysis(window: window, samples: samples, now: samples[1].at)

        #expect(analysis.willRunOutBeforeReset)
        #expect(!analysis.projectionPoints.isEmpty)
    }

    @Test
    func `synthesized reset anchor is not treated as observed consumption`() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let duration = 7 * 86400.0
        let window = QuotaWindow(
            kind: .weekly,
            usedPercent: 1,
            resetsAt: startedAt.addingTimeInterval(duration),
            duration: duration,
        )
        let samples = [
            self.sample(for: window, at: startedAt, used: 0),
            self.sample(for: window, at: startedAt.addingTimeInterval(5 * 60), used: 1),
        ]

        let analysis = BurnAnalysis(window: window, samples: samples, now: samples[1].at)

        #expect(!analysis.willRunOutBeforeReset)
        #expect(analysis.projectionPoints.isEmpty)
    }

    @Test
    func `early weekly burst does not assume continuous activity`() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let duration = 7 * 86400.0
        let baselineAt = startedAt.addingTimeInterval(24 * 3600)
        let latestAt = baselineAt.addingTimeInterval(40 * 60)
        let window = QuotaWindow(
            kind: .weekly,
            usedPercent: 3,
            resetsAt: startedAt.addingTimeInterval(duration),
            duration: duration,
        )
        let samples = [
            self.sample(for: window, at: baselineAt, used: 0),
            self.sample(for: window, at: latestAt, used: 3),
        ]

        let analysis = BurnAnalysis(window: window, samples: samples, now: latestAt)

        #expect(!analysis.willRunOutBeforeReset)
    }

    @Test
    func `full day of weekly history can still create exhaustion warning`() {
        let startedAt = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let duration = 7 * 86400.0
        let latestAt = startedAt.addingTimeInterval(24 * 3600)
        let window = QuotaWindow(
            kind: .weekly,
            usedPercent: 30,
            resetsAt: startedAt.addingTimeInterval(duration),
            duration: duration,
        )
        let samples = [
            self.sample(for: window, at: startedAt, used: 10),
            self.sample(for: window, at: latestAt, used: 30),
        ]

        let analysis = BurnAnalysis(window: window, samples: samples, now: latestAt)

        #expect(analysis.willRunOutBeforeReset)
    }

    private func sample(for window: QuotaWindow, at: Date, used: Double) -> UsageSample {
        UsageSample(provider: .claude, kind: window.kind, at: at, usedPercent: used, resetsAt: window.resetsAt)
    }
}

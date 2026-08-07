import Foundation
import Testing

@testable import Burndown

struct BurnAnalysisTests {
    @Test(arguments: [
        (QuotaWindowKind.session, 5 * 3600.0, 5.0),
        (QuotaWindowKind.weekly, 7 * 86400.0, 1.0),
    ])
    func openingUsageDoesNotCreateAProjection(kind: QuotaWindowKind, duration: TimeInterval, used: Double) {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let window = QuotaWindow(kind: kind, usedPercent: used, resetsAt: now.addingTimeInterval(duration), duration: duration)
        let openingReading = self.sample(for: window, at: now, used: used)

        let analysis = BurnAnalysis(window: window, samples: [openingReading], now: now.addingTimeInterval(3600))

        #expect(!analysis.willRunOutBeforeReset)
        #expect(analysis.projectionPoints.isEmpty)
    }

    @Test
    func continuedUsageCanCreateExhaustionWarning() {
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
    func synthesizedResetAnchorIsNotTreatedAsObservedConsumption() {
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

    private func sample(for window: QuotaWindow, at: Date, used: Double) -> UsageSample {
        UsageSample(provider: .claude, kind: window.kind, at: at, usedPercent: used, resetsAt: window.resetsAt)
    }
}

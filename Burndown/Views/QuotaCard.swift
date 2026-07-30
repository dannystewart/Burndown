import SwiftUI

/// One rolling window: how much is left, the burndown so far, and where the current pace leads.
struct QuotaCard: View {
    /// Drives the countdown and the projection without waiting for the next poll.
    @State private var now: Date = .now

    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]

    private var analysis: BurnAnalysis { BurnAnalysis(window: self.window, now: self.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.header
            self.headline
            self.bar

            if self.samples.count >= 2 {
                BurndownChart(
                    provider: self.provider,
                    window: self.window,
                    samples: self.samples,
                    analysis: self.analysis,
                )
            } else {
                self.awaitingHistory
            }

            self.summary
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        .task {
            // A slow tick is enough: everything on screen is measured in minutes. This keeps the
            // countdown and the projection moving between the monitor's one-minute polls.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self.now = .now
            }
        }
    }

    private var header: some View {
        HStack {
            Text(self.window.kind.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.mutedText)
                .tracking(0.6)
            Spacer()
            Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(self.now)))")
                .font(.system(size: 9))
                .foregroundStyle(Color.mutedText)
                .monospacedDigit()
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Format.percent(self.window.remainingPercent))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(self.window.severityColor)
            Text("remaining")
                .font(.caption)
                .foregroundStyle(Color.mutedText)
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(self.window.severityColor)
                    .frame(width: geometry.size.width * (self.window.remainingPercent / 100))
            }
        }
        .frame(height: 4)
    }

    private var awaitingHistory: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            Text("Recording history — the chart fills in as Burndown runs")
        }
        .font(.system(size: 9))
        .foregroundStyle(Color.mutedText)
        .frame(height: 76, alignment: .center)
    }

    /// How fast the quota is going, then whether that's a problem.
    ///
    /// One line rather than three. The used percentage is already the headline above, and the gap
    /// from steady burn is only that number subtracted from the elapsed fraction, so spelling out
    /// the rate, the comparison, and the difference was the same fact stated three ways. What's
    /// left is a measurement and a verdict, and pushing them to opposite edges separates the two
    /// without spending another row on it.
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            self.paceLine
            Spacer(minLength: 8)
            self.projectionLine
        }
        .font(.system(size: 9))
        .monospacedDigit()
    }

    /// The burn rate, and whether it's heavier or lighter than spending the window evenly.
    ///
    /// "Under" and "over" rather than "behind" and "ahead of" steady burn: falling behind sounds
    /// like the bad case everywhere else, and here it's the good one.
    private var paceLine: some View {
        let delta = self.analysis.paceDeltaPoints
        let comparison = "\(Format.percent(abs(delta))) \(delta >= 0 ? "over" : "under") pace"

        return HStack(spacing: 4) {
            if let rate = self.analysis.burnRate {
                Text("\(Format.rate(rate.value))%\(rate.unit.suffix)")
                Text("·")
            }
            Text(comparison)
        }
        .foregroundStyle(delta >= 0 ? .orange : Color.mutedText)
    }

    @ViewBuilder
    private var projectionLine: some View {
        if let exhaustion = self.analysis.exhaustionDate {
            Text("Runs out in \(Format.duration(exhaustion.timeIntervalSince(self.now))) (\(Format.dayAndTime(exhaustion)))")
                .foregroundStyle(.red)
        } else if self.analysis.burnRate != nil {
            Text("On track — \(Format.percent(self.analysis.projectedRemainingAtReset)) left at reset")
                .foregroundStyle(Color.mutedText)
        }
    }
}

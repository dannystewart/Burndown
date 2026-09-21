import SwiftUI

/// One rolling window: how much is left, the burndown so far, and where the current pace leads.
struct QuotaCard: View {
    /// Drives the countdown and the projection without waiting for the next poll.
    @State private var now: Date = .now

    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]

    private var analysis: BurnAnalysis {
        BurnAnalysis(window: self.window, samples: self.samples, now: self.now)
    }

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
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        .task {
            // This view can persist while the popover is closed. Rebase immediately when it becomes
            // visible again, then keep the countdown and projection moving between usage polls.
            self.now = .now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self.now = .now
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(self.window.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.mutedText)
                .tracking(0.6)
            Spacer()
            self.resetLine
        }
        .font(.system(size: 9))
        .monospacedDigit()
    }

    /// The countdown to reset, and — when the current pace burns through the window first — the
    /// exhaustion time in the same breath, in red, since that's the deadline that actually matters.
    @ViewBuilder
    private var resetLine: some View {
        if let exhaustion = self.analysis.exhaustionDate {
            HStack(spacing: 4) {
                Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(self.now)))")
                Text("(runs out in \(Format.duration(exhaustion.timeIntervalSince(self.now))))")
                    .foregroundStyle(.red)
            }
            .foregroundStyle(.red)
        } else {
            Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(self.now)))")
                .foregroundStyle(Color.mutedText)
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
        .frame(height: 60, alignment: .center)
    }
}

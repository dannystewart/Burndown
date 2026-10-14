import SwiftUI

/// One rolling window: how much is left, the burndown so far, and where the current pace leads.
struct QuotaCard: View {
    /// Drives the countdown and the projection without waiting for the next poll.
    @State private var now: Date = .now

    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]
    var isExpanded = true

    private var analysis: BurnAnalysis {
        BurnAnalysis(window: self.window, samples: self.samples, now: self.now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            self.header
            if self.isExpanded {
                VStack(alignment: .leading, spacing: 7) {
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
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, self.isExpanded ? 10 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .quaternary.opacity(self.isExpanded ? 0.35 : 0.2),
            in: .rect(cornerRadius: self.isExpanded ? 8 : 6),
        )
        .clipped()
        .contentShape(.rect)
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(self.window.displayName.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.mutedText)
                .tracking(0.6)
            if !self.isExpanded {
                Text(Format.percent(self.window.remainingPercent))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(self.window.severityColor)
                    .transition(.opacity)
            }
            Spacer()
            if self.isExpanded {
                self.resetLine
            } else {
                Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(self.now)))")
                    .foregroundStyle(Color.mutedText)
            }
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

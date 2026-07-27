//
//  QuotaCard.swift
//  Burndown
//

import SwiftUI

/// One rolling window: how much is left, the burndown so far, and where the current pace leads.
struct QuotaCard: View {
    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]

    /// Drives the countdown and the projection without waiting for the next poll.
    @State private var now: Date = .now

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
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            Spacer()
            Text("Resets in \(Format.duration(self.window.resetsAt.timeIntervalSince(self.now)))")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
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
                .foregroundStyle(.secondary)
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
        .foregroundStyle(.tertiary)
        .frame(height: 76, alignment: .center)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let rate = self.analysis.burnRate {
                    Text("Burn \(Format.rate(rate.value))%\(rate.unit.suffix)")
                } else {
                    Text("Burn not measurable yet")
                }
                Text("·")
                Text("Used \(Format.percent(self.analysis.usedPercent)) vs \(Format.percent(self.analysis.steadyPacePercent)) pace")
            }
            .foregroundStyle(.secondary)

            self.paceLine
            self.projectionLine
        }
        .font(.system(size: 9))
        .monospacedDigit()
    }

    /// Whether you're spending faster or slower than an even burn would predict.
    private var paceLine: some View {
        let delta = self.analysis.paceDeltaPoints
        let magnitude = Format.rate(abs(delta))
        let text = delta >= 0
            ? "\(magnitude)pp ahead of steady burn"
            : "\(magnitude)pp behind steady burn"
        return Text(text)
            .foregroundStyle(delta >= 0 ? .orange : Color.secondary)
    }

    @ViewBuilder
    private var projectionLine: some View {
        if let exhaustion = self.analysis.exhaustionDate {
            Text("Runs out in \(Format.duration(exhaustion.timeIntervalSince(self.now))) (\(Format.dayAndTime(exhaustion))) before reset")
                .foregroundStyle(.red)
        } else if self.analysis.burnRate != nil {
            Text("Safe until reset (projected \(Format.percent(self.analysis.projectedRemainingAtReset)) left)")
                .foregroundStyle(.secondary)
        }
    }
}

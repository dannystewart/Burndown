//
//  BurndownChart.swift
//  Burndown
//

import Charts
import SwiftUI

/// Remaining quota over the life of the current window, with a dashed projection to the reset.
struct BurndownChart: View {
    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]
    let analysis: BurnAnalysis

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let remaining: Double
    }

    /// Observed history, extended to the present so the line meets the projection.
    private var observed: [Point] {
        var points = self.samples.map { (date: $0.at, remaining: $0.remainingPercent) }
        if let last = points.last, last.date < self.analysis.now {
            points.append((self.analysis.now, self.window.remainingPercent))
        }
        return points.enumerated().map { Point(id: $0.offset, date: $0.element.date, remaining: $0.element.remaining) }
    }

    private var projected: [Point] {
        self.analysis.projectionPoints.enumerated().map {
            Point(id: $0.offset, date: $0.element.date, remaining: $0.element.remaining)
        }
    }

    private var xDomain: ClosedRange<Date> {
        let start = self.observed.first?.date ?? self.window.startedAt
        let end = self.window.resetsAt
        return start < end ? start ... end : start ... start.addingTimeInterval(60)
    }

    var body: some View {
        Chart {
            ForEach(self.observed) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Remaining", point.remaining),
                )
                .foregroundStyle(
                    .linearGradient(
                        colors: [self.provider.tint.opacity(0.35), self.provider.tint.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                .interpolationMethod(.monotone)
            }

            ForEach(self.observed) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Remaining", point.remaining),
                    series: .value("Series", "observed"),
                )
                .foregroundStyle(self.provider.tint)
                .lineStyle(.init(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }

            ForEach(self.projected) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Remaining", point.remaining),
                    series: .value("Series", "projected"),
                )
                .foregroundStyle(self.analysis.willRunOutBeforeReset ? Color.red : self.provider.tint.opacity(0.7))
                .lineStyle(.init(lineWidth: 1.5, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0 ... 100)
        .chartXScale(domain: self.xDomain)
        .chartYAxis {
            AxisMarks(values: [0.0, 50.0, 100.0]) { mark in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    Text(Format.percent(mark.as(Double.self) ?? 0))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 76)
    }
}

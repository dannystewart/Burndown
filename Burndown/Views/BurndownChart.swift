import Charts
import SwiftUI

/// Remaining quota over the life of the current window, with a dashed projection to the reset.
struct BurndownChart: View {
    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let remaining: Double
    }

    let provider: Provider
    let window: QuotaWindow
    let samples: [UsageSample]
    let analysis: BurnAnalysis

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

    /// Day names across a week, clock times across five hours.
    ///
    /// A seven-day chart labelled `12:00 AM` twice says nothing about where in the week you are —
    /// the axis has to be read at the scale of the window it's describing.
    private var xAxisFormat: Date.FormatStyle {
        switch self.window.kind {
        case .session: .dateTime.hour().minute()
        case .weekly: .dateTime.weekday(.abbreviated)
        }
    }

    /// Ticks on day boundaries for the weekly window, so no two labels can name the same day.
    private var xAxisValues: AxisMarkValues {
        switch self.window.kind {
        case .session: .automatic(desiredCount: 3)
        case .weekly: .stride(by: .day, count: 2)
        }
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
                        colors: [self.provider.tint.opacity(0.5), self.provider.tint.opacity(0.1)],
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
                // Anchored explicitly because the 0 and 100 marks sit on the plot's own edges.
                // Left to itself Charts interpolates an anchor there to avoid clipping, then logs a
                // complaint that the value it computed isn't one of its named constants.
                AxisValueLabel(anchor: .leading) {
                    Text(Format.percent(mark.as(Double.self) ?? 0))
                        .font(.system(size: 8))
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: self.xAxisValues) { mark in
                // Same reason: day-boundary ticks don't line up with a domain that starts mid-day,
                // so the first label sits partway into the leading edge.
                AxisValueLabel(anchor: .top) {
                    Text(mark.as(Date.self) ?? .now, format: self.xAxisFormat)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.mutedText)
                }
            }
        }
        .frame(height: 76)
    }
}

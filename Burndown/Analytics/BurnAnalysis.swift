import Foundation

/// Turns a quota window into pace and projection figures.
///
/// The burn rate is measured from the start of the window rather than from Burndown's own recorded
/// history, because the provider tells us how much of the window is gone and how much quota went
/// with it. That makes the numbers meaningful the moment the app launches, instead of needing hours
/// of samples first.
nonisolated struct BurnAnalysis: Sendable {
    /// Too early in a window to divide by elapsed time without producing nonsense.
    private static let minimumElapsedHours: Double = 1.0 / 60

    let window: QuotaWindow
    let now: Date

    var remainingPercent: Double { self.window.remainingPercent }
    var usedPercent: Double { self.window.usedPercent }

    var elapsedHours: Double {
        max(0, self.now.timeIntervalSince(self.window.startedAt)) / 3600
    }

    var hoursUntilReset: Double {
        max(0, self.window.resetsAt.timeIntervalSince(self.now)) / 3600
    }

    /// Average consumption since the window opened, in percentage points per hour.
    var burnPerHour: Double? {
        guard self.elapsedHours >= Self.minimumElapsedHours else { return nil }
        return self.usedPercent / self.elapsedHours
    }

    /// The burn rate expressed in whichever unit suits this window's timescale.
    var burnRate: (value: Double, unit: BurnRateUnit)? {
        guard let burnPerHour else { return nil }
        let unit = self.window.kind.burnRateUnit
        return (burnPerHour * unit.hours, unit)
    }

    /// What the used percentage would be if the quota were spent perfectly evenly.
    var steadyPacePercent: Double { self.window.elapsedFraction(asOf: self.now) * 100 }

    /// How far ahead of or behind steady burn you are, in percentage points.
    ///
    /// Negative means you've used less than an even pace would predict.
    var paceDeltaPoints: Double { self.usedPercent - self.steadyPacePercent }

    /// Projected consumption by the time the window resets, if the current pace holds.
    var projectedUsedAtReset: Double {
        guard let burnPerHour else { return self.usedPercent }
        return self.usedPercent + burnPerHour * self.hoursUntilReset
    }

    var projectedRemainingAtReset: Double {
        (100 - self.projectedUsedAtReset).clamped(to: 0 ... 100)
    }

    /// When the quota is projected to hit zero, if that happens before the window resets.
    var exhaustionDate: Date? {
        guard let burnPerHour, burnPerHour > 0, self.remainingPercent > 0 else { return nil }
        let hours = self.remainingPercent / burnPerHour
        guard hours <= self.hoursUntilReset else { return nil }
        return self.now.addingTimeInterval(hours * 3600)
    }

    var willRunOutBeforeReset: Bool { self.exhaustionDate != nil }

    /// The dashed forward-looking line for the chart, in remaining-percentage terms.
    ///
    /// If the projection runs out early it flattens along zero to the reset, rather than continuing
    /// into negative quota.
    var projectionPoints: [(date: Date, remaining: Double)] {
        guard self.burnPerHour != nil else { return [] }
        var points: [(date: Date, remaining: Double)] = [(self.now, self.remainingPercent)]
        if let exhaustionDate {
            points.append((exhaustionDate, 0))
            points.append((self.window.resetsAt, 0))
        } else {
            points.append((self.window.resetsAt, self.projectedRemainingAtReset))
        }
        return points
    }

    init(window: QuotaWindow, now: Date = .now) {
        self.window = window
        self.now = now
    }
}

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

    /// How long the remaining quota lasts at the current pace, ignoring the reset.
    ///
    /// `exhaustionDate` deliberately gives up when the window resets first — the right answer for
    /// "will this bite me", but useless for ranking two windows that are both safe. This keeps
    /// going past the reset so there's always something to compare.
    var hoursToEmpty: Double? {
        // An already exhausted window is the limit being felt right now. Treating it as having no
        // projection would sort it behind a longer window that still has quota available.
        guard self.remainingPercent > 0 else { return 0 }
        guard let burnPerHour, burnPerHour > 0 else { return nil }
        return self.remainingPercent / burnPerHour
    }

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

    /// Whether `lhs` is the limit you'd feel first.
    ///
    /// Ranked by projected time to empty rather than by percentage left, because the two disagree
    /// often enough to matter: a weekly window sitting at 20% with five days to run is less pressing
    /// than a five-hour window at 40% being burned through in an afternoon. Windows with no
    /// measurable burn sort last — nothing is imminent if nothing is moving — and ties fall to
    /// whichever has less headroom.
    static func soonest(_ lhs: QuotaWindow, than rhs: QuotaWindow, asOf now: Date = .now) -> Bool {
        let left = BurnAnalysis(window: lhs, now: now).hoursToEmpty ?? .infinity
        let right = BurnAnalysis(window: rhs, now: now).hoursToEmpty ?? .infinity
        if left != right { return left < right }
        return lhs.remainingPercent < rhs.remainingPercent
    }
}

import Foundation

/// Turns a quota window into pace and projection figures.
///
/// Forecasts are based on usage Burndown observes after the first reading in a window. A rolling
/// window commonly opens because one request consumed quota; extrapolating that initial burst from
/// the window's start makes a brand-new window look certain to run out.
nonisolated struct BurnAnalysis: Sendable {
    enum Status: Sendable {
        case normal
        case warning
        case critical
        case exhausted
    }

    /// Too early in a window to divide by elapsed time without producing nonsense.
    private static let minimumElapsedHours: Double = 1.0 / 60
    /// A short weekly observation should not be extrapolated as round-the-clock activity.
    private static let assumedActiveHoursPerDay: Double = 8
    private static let hoursPerDay: Double = 24
    /// Older usage still matters, but its influence halves every few hours instead of defining the
    /// forecast for an entire billing cycle after the work has stopped.
    private static let burnRateHalfLifeHours: Double = 4

    /// A forecast needs this much forward movement before its chart says more than the headline.
    private static let meaningfulProjectionPoints: Double = 10

    let window: QuotaWindow
    let samples: [UsageSample]
    let now: Date

    var remainingPercent: Double { self.window.remainingPercent }
    var usedPercent: Double { self.window.usedPercent }

    var hoursUntilReset: Double {
        max(0, self.window.resetsAt.timeIntervalSince(self.now)) / 3600
    }

    /// Recent consumption observed after Burndown established a baseline, in percentage points per
    /// hour. Each sample interval is exponentially weighted, so the estimate cools continuously
    /// through an idle stretch without letting a few minutes of activity dictate the forecast.
    var burnPerHour: Double? {
        let observed = self.observedSamples
        guard let baseline = observed.first, let latest = observed.last else { return nil }
        let observedHours = self.now.timeIntervalSince(baseline.at) / 3600
        guard observedHours >= Self.minimumElapsedHours else { return nil }

        var observedRate = 0.0
        for (previous, current) in zip(observed, observed.dropFirst()) {
            let intervalHours = current.at.timeIntervalSince(previous.at) / 3600
            guard intervalHours > 0 else { continue }
            let intervalRate = max(0, current.usedPercent - previous.usedPercent) / intervalHours
            let carryover = exp(-intervalHours / Self.burnRateHalfLifeHours)
            observedRate = observedRate * carryover + intervalRate * (1 - carryover)
        }

        // Samples are keyframed every fifteen minutes, but the card recomputes its forecast every
        // fifteen seconds. Continue cooling the estimate during that gap too.
        let idleHours = max(0, self.now.timeIntervalSince(latest.at)) / 3600
        observedRate *= exp(-idleHours / Self.burnRateHalfLifeHours)
        switch self.window.kind {
        case .session:
            return observedRate
        case .weekly, .monthly:
            // Early weekly history usually captures an active coding session but not the sleep and
            // idle time that follows it. Ease from an eight-hour active day toward the actual wall-
            // clock rate; after a full day, the observations themselves contain that daily activity
            // cycle. Monthly windows get the same treatment — the assumption is too coarse for a
            // 30-day window but produces more useful numbers than treating it as round-the-clock.
            let dayCoverage = (observedHours / Self.hoursPerDay).clamped(to: 0 ... 1)
            let activeDayFraction = Self.assumedActiveHoursPerDay / Self.hoursPerDay
            let activityAdjustment = activeDayFraction + (1 - activeDayFraction) * dayCoverage
            let activityAdjustedRate = observedRate * activityAdjustment

            // A burst seen for only an hour or two is weak evidence that the same workload will
            // recur every day. Regularize high early rates toward spending the full allowance
            // evenly, without inflating observations that are already below that pace.
            let sustainableRate = 100 / (self.window.duration / 3600)
            guard activityAdjustedRate > sustainableRate else { return activityAdjustedRate }
            return sustainableRate + (activityAdjustedRate - sustainableRate) * dayCoverage
        }
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

    /// Color calls attention to actionable risk, not a quota that's already spent.
    var status: Status {
        if self.remainingPercent <= 0 { return .exhausted }
        if self.usedPercent >= 90 {
            return self.willRunOutBeforeReset ? .critical : .warning
        }
        return self.willRunOutBeforeReset ? .warning : .normal
    }

    /// How long the remaining quota lasts at the current pace, ignoring the reset.
    ///
    /// `exhaustionDate` deliberately gives up when the window resets first — the right answer for
    /// "will this bite me", but useless for ranking two windows that are both safe. This keeps
    /// going past the reset so there's always something to compare.
    var hoursToEmpty: Double? {
        // An already exhausted window is the limit being felt right now. Treating it as having no
        // projection would sort it behind a longer window that still has quota available.
        guard self.remainingPercent > 0 else { return 0 }
        // A window in the critical zone is that limit being felt too, even while the observed burn
        // is momentarily zero — a pause between requests is not headroom. It outranks every window
        // with real runway left.
        guard self.remainingPercent > QuotaWindow.criticalThreshold else { return 0 }
        guard let burnPerHour, burnPerHour > 0 else { return nil }
        return self.remainingPercent / burnPerHour
    }

    /// Whether this window's chart is worth its height.
    ///
    /// A historical drop is not enough: once the recent rate has cooled, a flat forecast only
    /// repeats the headline. The chart returns when the current pace projects a meaningful change.
    var isChartWorthy: Bool {
        guard let burnPerHour else { return false }
        return burnPerHour * self.hoursUntilReset >= Self.meaningfulProjectionPoints
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

    /// Provider readings, excluding the zero anchor synthesized when a reset is observed.
    private var observedSamples: [UsageSample] {
        self.samples
            .filter {
                abs($0.resetsAt.timeIntervalSince(self.window.resetsAt)) < 120
                    && !($0.usedPercent == 0 && abs($0.at.timeIntervalSince(self.window.startedAt)) < 1)
            }
            .sorted { $0.at < $1.at }
    }

    init(window: QuotaWindow, samples: [UsageSample], now: Date = .now) {
        self.window = window
        self.samples = samples
        self.now = now
    }

    /// Whether `lhs` is the limit you'd feel first.
    ///
    /// Ranked by projected time to empty rather than by percentage left, because the two disagree
    /// often enough to matter: a weekly window sitting at 20% with five days to run is less
    /// pressing than a five-hour window at 40% being burned through in an afternoon. Windows with
    /// no measurable burn sort last — nothing is imminent if nothing is moving — and ties fall to
    /// whichever has less headroom.
    static func soonest(
        _ lhs: QuotaWindow,
        samples lhsSamples: [UsageSample],
        than rhs: QuotaWindow,
        samples rhsSamples: [UsageSample],
        asOf now: Date = .now,
    ) -> Bool {
        let left = BurnAnalysis(window: lhs, samples: lhsSamples, now: now).hoursToEmpty ?? .infinity
        let right = BurnAnalysis(window: rhs, samples: rhsSamples, now: now).hoursToEmpty ?? .infinity
        if left != right { return left < right }
        return lhs.remainingPercent < rhs.remainingPercent
    }
}

import Foundation

// MARK: - QuotaWindowKind

/// The kind of rolling limit a quota window represents.
///
/// Providers don't agree on how they label windows, and Codex in particular reports its windows
/// positionally as "primary" and "secondary" rather than by name — the primary window is weekly on
/// some plans and five-hourly on others. Windows are therefore always classified by their actual
/// duration, never by the position they arrived in.
nonisolated enum QuotaWindowKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// A short rolling window, nominally five hours.
    case session
    /// A long rolling window, nominally seven days.
    case weekly
    /// A multi-week rolling window, nominally thirty days.
    case monthly

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .session: "5-Hour"
        case .weekly: "7-Day"
        case .monthly: "30-Day"
        }
    }

    /// The rate unit that reads most naturally for this window's timescale.
    var burnRateUnit: BurnRateUnit {
        switch self {
        case .session: .perHour
        case .weekly, .monthly: .perDay
        }
    }

    /// Classifies a window by its length. Up to a day is a session window, up to a week is weekly,
    /// and anything longer is treated as monthly.
    init(duration: TimeInterval) {
        if duration <= 86400 { self = .session }
        else if duration <= 7 * 86400 { self = .weekly }
        else { self = .monthly }
    }
}

// MARK: - QuotaWindow

/// A single rolling quota window as reported by a provider.
nonisolated struct QuotaWindow: Codable, Sendable, Hashable, Identifiable {
    let kind: QuotaWindowKind
    /// Percentage of the quota consumed, 0...100.
    let usedPercent: Double
    /// When this window's quota resets.
    let resetsAt: Date
    /// The full length of the window.
    let duration: TimeInterval
    /// Distinguishes windows that share a kind within one provider.
    ///
    /// Most providers report one window per kind, so the kind alone identifies it. Cursor reports
    /// several metrics — plan spend, auto-model usage, API usage — that all live in the same
    /// monthly billing cycle, so they'd otherwise collide on kind. The label separates them for
    /// identity, grouping, and display; it's nil for single-metric windows, which show their kind's
    /// name.
    let label: String?

    var id: String { self.label.map { "\(self.kind.rawValue)#\($0)" } ?? self.kind.rawValue }

    /// What to title this window in the popover: its metric label, or its kind when unlabelled.
    var displayName: String { self.label ?? self.kind.displayName }

    var remainingPercent: Double { (100 - self.usedPercent).clamped(to: 0 ... 100) }

    /// When the current window began.
    var startedAt: Date { self.resetsAt.addingTimeInterval(-self.duration) }

    init(kind: QuotaWindowKind, usedPercent: Double, resetsAt: Date, duration: TimeInterval, label: String? = nil) {
        self.kind = kind
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.duration = duration
        self.label = label
    }

    /// How far through the window we are, 0...1.
    func elapsedFraction(asOf now: Date = .now) -> Double {
        guard self.duration > 0 else { return 0 }
        return (now.timeIntervalSince(self.startedAt) / self.duration).clamped(to: 0 ... 1)
    }

    /// Two windows describe the same period if they reset at effectively the same moment.
    ///
    /// Providers jitter `resetsAt` by fractions of a second between polls, so an exact match would
    /// spuriously treat every poll as a brand new window.
    func isSamePeriod(as other: QuotaWindow) -> Bool {
        self.kind == other.kind
            && abs(self.resetsAt.timeIntervalSince(other.resetsAt)) < 120
    }
}

// MARK: - BurnRateUnit

/// How a burn rate should be expressed.
nonisolated enum BurnRateUnit: Sendable {
    case perHour
    case perDay

    var suffix: String {
        switch self {
        case .perHour: "/hr"
        case .perDay: "/day"
        }
    }

    /// Hours in one unit, for converting a per-hour rate.
    var hours: Double {
        switch self {
        case .perHour: 1
        case .perDay: 24
        }
    }
}

extension Comparable {
    nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

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

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .session: "5-Hour"
        case .weekly: "7-Day"
        }
    }

    /// The rate unit that reads most naturally for this window's timescale.
    var burnRateUnit: BurnRateUnit {
        switch self {
        case .session: .perHour
        case .weekly: .perDay
        }
    }

    /// Classifies a window by its length. Anything up to a day is treated as a session window.
    init(duration: TimeInterval) {
        self = duration <= 86400 ? .session : .weekly
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

    var id: QuotaWindowKind { self.kind }

    var remainingPercent: Double { (100 - self.usedPercent).clamped(to: 0 ... 100) }

    /// When the current window began.
    var startedAt: Date { self.resetsAt.addingTimeInterval(-self.duration) }

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

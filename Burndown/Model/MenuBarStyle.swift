import Foundation

// MARK: - MenuBarLayout

/// How much of the menu bar Burndown is allowed to take up.
nonisolated enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    /// A single row showing whichever window is closest to running out.
    case single
    /// One compact row per provider, stacked within the menu bar's height.
    case stacked

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .single: "Single Line"
        case .stacked: "Two Lines"
        }
    }
}

// MARK: - MenuBarFormat

/// What a menu bar row actually says about a window.
///
/// Kept separate from the layout so the two compose: a single line might be stripped back to a bare
/// percentage while the two-line layout carries reset times, or the other way round.
nonisolated enum MenuBarFormat: String, CaseIterable, Identifiable, Sendable {
    case percentage
    case percentageAndRemaining
    case percentageAndReset
    case remaining
    case reset

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .percentage: "Percentage"
        case .percentageAndRemaining: "Percentage + Time Remaining"
        case .percentageAndReset: "Percentage + Reset Time"
        case .remaining: "Time Remaining"
        case .reset: "Reset Time"
        }
    }

    /// Renders one window in this format.
    func text(for window: QuotaWindow, asOf now: Date) -> String {
        let percent = Format.percent(window.remainingPercent)
        let left = Format.duration(window.resetsAt.timeIntervalSince(now), for: window.kind)
        let at = Format.dayAndTime(window.resetsAt)

        switch self {
        case .percentage: return percent
        case .percentageAndRemaining: return "\(percent) · \(left)"
        case .percentageAndReset: return "\(percent) · \(at)"
        case .remaining: return left
        case .reset: return at
        }
    }
}

// MARK: - MenuBarColorMode

/// When the menu bar is allowed to use color.
nonisolated enum MenuBarColorMode: String, CaseIterable, Identifiable, Sendable {
    case always
    /// Color only once a window crosses into warning or critical territory, so color in the menu bar
    /// means something rather than just being decoration.
    case whenLow
    case never

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .always: "Always"
        case .whenLow: "When Low"
        case .never: "Never"
        }
    }
}

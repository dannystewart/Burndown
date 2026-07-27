import SwiftUI

// MARK: - Format

nonisolated enum Format {
    /// A short human duration: `3d 21h`, `2h 10m`, `45m`.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// A duration whose shape says which window it belongs to.
    ///
    /// The menu bar has room for one number and no room for a label, so the format carries the
    /// distinction: a weekly window always leads with days, even when there are none, while a
    /// five-hour window never shows them. `0d 1h` and `1h 0m` are the same length of time and
    /// different limits, and now they look it.
    static func duration(_ interval: TimeInterval, for kind: QuotaWindowKind) -> String {
        let total = Int(max(0, interval))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60

        return switch kind {
        case .session: hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        case .weekly: days > 0 || hours > 0 ? "\(days)d \(hours)h" : "0d \(minutes)m"
        }
    }

    /// A weekday and time, for reset moments more than a few hours out: `Fri 8:00 AM`.
    static func dayAndTime(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// One decimal place, for burn rates where whole numbers are too coarse.
    static func rate(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

extension Provider {
    /// Distinguishes the two providers' charts at a glance.
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: Color(red: 0.35, green: 0.62, blue: 0.95)
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }
}

extension QuotaWindow {
    /// Below this much headroom a window is worth noticing; below `critical` it's worth worrying.
    static let warningThreshold: Double = 40
    static let criticalThreshold: Double = 15

    /// Color by how much headroom is left, so urgency reads before any of the text does.
    var severityColor: Color {
        switch self.remainingPercent {
        case ..<Self.criticalThreshold: .red
        case ..<Self.warningThreshold: .orange
        default: .green
        }
    }

    /// Whether this window has crossed into territory the menu bar should call out.
    var isLow: Bool { self.remainingPercent < Self.warningThreshold }
}

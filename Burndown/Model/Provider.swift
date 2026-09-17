import Foundation

/// An AI subscription whose quota Burndown tracks.
nonisolated enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case codex
    case cursor
    case opencodeGo = "opencode_go"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .opencodeGo: "OpenCode Go"
        }
    }

    /// Whether this provider reports the given window as a continuously-rolling window rather than one
    /// with a fixed reset boundary.
    ///
    /// Claude, Codex, and Cursor report a fixed `resetsAt` that only changes when a period actually
    /// rolls over, so it works as a stable period identifier. OpenCode Go's five-hour window is a true
    /// rolling window: `resetsAt` tracks when the oldest usage ages out, and while idle it degenerates
    /// to `now + 5h`, sliding forward on every poll. That breaks any logic that treats `resetsAt` as a
    /// period key — reset detection and sample grouping both need to know not to.
    func windowRolls(_ kind: QuotaWindowKind) -> Bool {
        self == .opencodeGo && kind == .session
    }
}

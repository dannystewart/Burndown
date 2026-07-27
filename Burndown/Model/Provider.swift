import Foundation

/// An AI subscription whose quota Burndown tracks.
nonisolated enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case codex
    case claude

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }
}

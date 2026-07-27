//
//  Provider.swift
//  Burndown
//

import Foundation

/// An AI subscription whose quota Burndown tracks.
nonisolated enum Provider: String, Codable, Sendable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
            case .claude: "Claude"
            case .codex: "Codex"
        }
    }
}

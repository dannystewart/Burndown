//
//  Log.swift
//  Burndown
//

import PolyKit

extension LogGroup {
    nonisolated static let credentials: LogGroup = .init("credentials", emoji: "🔑")
    nonisolated static let network: LogGroup = .init("network", emoji: "🌐")
    nonisolated static let store: LogGroup = .init("store", emoji: "💾")
}

/// Shared logger. Deliberately not main-actor bound: the credential readers and usage clients all
/// run off the main actor and still need to report what happened.
nonisolated let log: PolyLog = .init(appGroups: [.credentials, .network, .store], capture: true)

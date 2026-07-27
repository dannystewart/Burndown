//
//  UsageSnapshot.swift
//  Burndown
//

import Foundation

/// One provider's quota state at a single moment.
///
/// Both provider endpoints report only "right now" — there is no history API. Everything historical
/// in Burndown is built from snapshots it recorded itself while running.
nonisolated struct UsageSnapshot: Codable, Sendable, Hashable {
    let provider: Provider
    let capturedAt: Date
    let windows: [QuotaWindow]
    /// The subscription tier, when the provider tells us.
    let plan: String?

    func window(_ kind: QuotaWindowKind) -> QuotaWindow? {
        self.windows.first { $0.kind == kind }
    }
}

/// The result of the most recent attempt to read a provider.
nonisolated enum ProviderState: Sendable {
    case loading
    case loaded(UsageSnapshot)
    case failed(UsageError)

    var snapshot: UsageSnapshot? {
        if case let .loaded(snapshot) = self { snapshot } else { nil }
    }

    var error: UsageError? {
        if case let .failed(error) = self { error } else { nil }
    }
}

//
//  UsageError.swift
//  Burndown
//

import Foundation

/// Why a provider's usage couldn't be read.
///
/// These map to what the user can actually do about it, not to HTTP status codes.
nonisolated enum UsageError: Error, Sendable, Equatable {
    /// No credentials on this machine — the CLI isn't installed, or was never signed in.
    case notSignedIn
    /// Credentials exist but the provider rejected them.
    case credentialsExpired
    /// The credential store exists but couldn't be read (Keychain denial, unreadable file).
    case credentialsUnreadable(String)
    /// The provider is throttling us and we should back off.
    case rateLimited
    /// The request failed before we got a usable answer.
    case network(String)
    /// The response arrived but didn't look like we expect.
    case malformedResponse(String)

    /// Whether this is likely to clear on its own.
    ///
    /// Transient failures shouldn't blank out numbers that were correct a minute ago — a throttled
    /// poll or a closed laptop lid is no reason to hide the quota.
    var isTransient: Bool {
        switch self {
            case .rateLimited, .network, .malformedResponse: true
            case .notSignedIn, .credentialsExpired, .credentialsUnreadable: false
        }
    }

    /// A short explanation suitable for showing in the popover.
    var message: String {
        switch self {
            case .notSignedIn:
                "Not signed in"
            case .credentialsExpired:
                "Sign-in expired"
            case let .credentialsUnreadable(detail):
                detail
            case .rateLimited:
                "Throttled — backing off"
            case let .network(detail):
                detail
            case let .malformedResponse(detail):
                detail
        }
    }

    /// What the user should do, when there's something actionable.
    ///
    /// Burndown never refreshes tokens itself: both providers rotate refresh tokens, so refreshing
    /// here would invalidate the copy the CLI holds and break its sign-in. Re-authentication always
    /// happens in the CLI that owns the credentials.
    func recoverySuggestion(for provider: Provider) -> String? {
        switch self {
            case .notSignedIn, .credentialsExpired:
                switch provider {
                    case .claude: "Run `claude` and sign in"
                    case .codex: "Run `codex login`"
                }
            case .credentialsUnreadable, .network, .malformedResponse, .rateLimited:
                nil
        }
    }
}

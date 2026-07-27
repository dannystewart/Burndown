import Foundation
import PolyKit
import Security

// MARK: - ClaudeCredentials

/// Claude Code's OAuth credentials, as stored in the login Keychain.
nonisolated struct ClaudeCredentials: Sendable {
    let accessToken: String
    let subscriptionType: String?
}

// MARK: - ClaudeCredentialStore

/// Reads (and only ever reads) the credentials Claude Code stores in the Keychain.
///
/// The item is owned by Claude Code, so the first read prompts the user to allow access. Burndown
/// never writes to it, and never refreshes it — see `UsageError.recoverySuggestion(for:)`.
nonisolated enum ClaudeCredentialStore {
    private struct Payload: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let subscriptionType: String?
        }

        let claudeAiOauth: OAuth
    }

    private static let service: String = "Claude Code-credentials"

    static func load() throws(UsageError) -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            break

        case errSecItemNotFound:
            throw .notSignedIn

        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            log.warning("Keychain access to Claude credentials denied.", group: .credentials)
            throw .credentialsUnreadable("Keychain access denied")

        default:
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
            throw .credentialsUnreadable("Keychain error: \(detail)")
        }

        guard let data = item as? Data else {
            throw .credentialsUnreadable("Keychain returned no data")
        }

        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return ClaudeCredentials(
                accessToken: payload.claudeAiOauth.accessToken,
                subscriptionType: payload.claudeAiOauth.subscriptionType,
            )
        } catch {
            throw .credentialsUnreadable("Unrecognized Keychain payload")
        }
    }
}

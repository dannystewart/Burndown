import Foundation

// MARK: - OllamaCloudCredentials

/// The session credentials Burndown itself stores for Ollama.
///
/// Ollama has no quota API, so usage comes from the logged-in `ollama.com/settings` page. The user
/// pastes that page's cookie header (`aid=...; __Secure-session=...`) into Burndown's settings, and
/// it is only ever sent to ollama.com.
nonisolated struct OllamaCloudCredentials: Sendable {
    let cookie: String
}

// MARK: - OllamaCloudCredentialStore

/// Reads the pasted Ollama session cookie that Burndown stores itself.
///
/// Unlike the other credential stores, there is no owning CLI here: the menu-bar app writes the
/// cookie through the settings UI, and the launchd agent reads it when polling. The agent is the
/// same executable but launched by launchd, where the process's default defaults domain is not
/// guaranteed to resolve to the app's bundle identifier — so both sides address an explicit suite
/// name and land on the same predictable plist.
nonisolated enum OllamaCloudCredentialStore {
    private static let suiteName = "com.dannystewart.Burndown.providers"
    private static let cookieKey = "ollamaSessionCookie"

    static var isConfigured: Bool {
        (try? load()) != nil
    }

    static func load() throws(UsageError) -> OllamaCloudCredentials {
        guard
            let cookie = UserDefaults(suiteName: suiteName)?.string(forKey: cookieKey),
            !cookie.isEmpty else
        {
            throw .notSignedIn
        }
        return OllamaCloudCredentials(cookie: cookie)
    }

    static func save(_ cookie: String) {
        UserDefaults(suiteName: self.suiteName)?.set(cookie.trimmedCookie, forKey: self.cookieKey)
    }

    static func clear() {
        UserDefaults(suiteName: self.suiteName)?.removeObject(forKey: self.cookieKey)
    }
}

// MARK: - Cookie normalization

private extension String {
    /// Users paste straight from browser devtools, often including the `Cookie:` header name. Strip
    /// it and surrounding whitespace so what is stored is the bare header value.
    var trimmedCookie: String {
        var value = self.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cookie:") {
            value = String(value.dropFirst("cookie:".count))
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

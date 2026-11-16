import Foundation

// MARK: - OllamaCloudCredentials

/// The API key the user supplies for Ollama's balance endpoint, sent only to ollama.com.
nonisolated struct OllamaCloudCredentials: Sendable {
    let apiKey: String
}

// MARK: - OllamaCloudCredentialStore

/// Reads the Ollama API key that Burndown stores itself.
///
/// Unlike the other credential stores, there is no owning CLI here: the menu-bar app writes the
/// key through the settings UI, and the launchd agent reads it when polling. The agent is the
/// same executable but launched by launchd, where the process's default defaults domain is not
/// guaranteed to resolve to the app's bundle identifier — so both sides address an explicit suite
/// name and land on the same predictable plist.
nonisolated enum OllamaCloudCredentialStore {
    private static let suiteName = "com.dannystewart.Burndown.providers"
    private static let apiKeyKey = "ollamaAPIKey"

    static var isConfigured: Bool {
        (try? load()) != nil
    }

    static func load() throws(UsageError) -> OllamaCloudCredentials {
        guard
            let apiKey = UserDefaults(suiteName: suiteName)?.string(forKey: apiKeyKey),
            !apiKey.isEmpty else
        {
            throw .notSignedIn
        }
        return OllamaCloudCredentials(apiKey: apiKey)
    }

    static func save(_ apiKey: String) {
        let apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            self.clear()
            return
        }
        let defaults = UserDefaults(suiteName: self.suiteName)
        defaults?.set(apiKey, forKey: self.apiKeyKey)
        // A browser session is no longer needed once the API key has been configured.
        defaults?.removeObject(forKey: "ollamaSessionCookie")
    }

    static func clear() {
        let defaults = UserDefaults(suiteName: self.suiteName)
        defaults?.removeObject(forKey: self.apiKeyKey)
        defaults?.removeObject(forKey: "ollamaSessionCookie")
    }
}

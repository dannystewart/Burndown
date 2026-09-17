import Foundation
import PolyKit

// MARK: - OpenCodeGoCredentials

/// The bearer token OpenCode stores for its Zen/Go usage API.
///
/// OpenCode writes this to `~/.local/share/opencode/auth.json` under the `opencode-go` key when the
/// user signs in. Burndown reads it; it never writes or refreshes the value.
nonisolated struct OpenCodeGoCredentials: Sendable {
    let apiKey: String
}

// MARK: - OpenCodeGoCredentialStore

/// Reads OpenCode's stored API key for its Go usage endpoint.
nonisolated enum OpenCodeGoCredentialStore {
    private struct AuthFile: Decodable {
        enum CodingKeys: String, CodingKey {
            case opencodeGo = "opencode-go"
        }

        struct Entry: Decodable {
            let key: String?
            let token: String?
        }

        let opencodeGo: Entry?
    }

    static var authFileURL: URL {
        URL.homeDirectory
            .appending(path: ".local/share/opencode/auth.json", directoryHint: .notDirectory)
    }

    static func load() throws(UsageError) -> OpenCodeGoCredentials {
        let url = self.authFileURL

        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw .notSignedIn
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .credentialsUnreadable("Can't read OpenCode auth.json")
        }

        let payload: AuthFile
        do {
            payload = try JSONDecoder().decode(AuthFile.self, from: data)
        } catch {
            throw .credentialsUnreadable("Unrecognized OpenCode auth.json format")
        }

        guard let entry = payload.opencodeGo, let apiKey = entry.key ?? entry.token, !apiKey.isEmpty else {
            throw .notSignedIn
        }

        return OpenCodeGoCredentials(apiKey: apiKey)
    }
}

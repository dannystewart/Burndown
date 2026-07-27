import Foundation
import PolyKit

// MARK: - CodexCredentials

/// Codex CLI's OAuth credentials, as stored in `~/.codex/auth.json`.
nonisolated struct CodexCredentials: Sendable {
    let accessToken: String
    let accountID: String
    let planType: String?
}

// MARK: - CodexCredentialStore

/// Reads (and only ever reads) the credentials the Codex CLI writes to disk.
nonisolated enum CodexCredentialStore {
    private struct Payload: Decodable {
        struct Tokens: Decodable {
            struct IDToken: Decodable {
                private enum CodingKeys: String, CodingKey {
                    case chatgptAccountID = "chatgpt_account_id"
                    case chatgptPlanType = "chatgpt_plan_type"
                }

                let chatgptAccountID: String?
                let chatgptPlanType: String?
            }

            private enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountID = "account_id"
                case idToken = "id_token"
            }

            let accessToken: String
            let accountID: String?
            let idToken: IDToken?
        }

        let tokens: Tokens?
    }

    static var authFileURL: URL {
        URL.homeDirectory.appending(path: ".codex/auth.json", directoryHint: .notDirectory)
    }

    static func load() throws(UsageError) -> CodexCredentials {
        let url = self.authFileURL

        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw .notSignedIn
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.warning("Couldn't read auth.json: \(error.localizedDescription)", group: .credentials)
            throw .credentialsUnreadable("Can't read auth.json")
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw .credentialsUnreadable("Unrecognized auth.json format")
        }

        guard let tokens = payload.tokens else { throw .notSignedIn }

        // The CLI sends `account_id`, but it's absent on some sign-in paths where only the ID token
        // carries the account.
        guard let accountID = tokens.accountID ?? tokens.idToken?.chatgptAccountID else {
            throw .credentialsUnreadable("No account ID in auth.json")
        }

        return CodexCredentials(
            accessToken: tokens.accessToken,
            accountID: accountID,
            planType: tokens.idToken?.chatgptPlanType,
        )
    }
}

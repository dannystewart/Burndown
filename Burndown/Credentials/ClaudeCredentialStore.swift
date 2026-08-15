import Foundation
import PolyKit

// MARK: - ClaudeCredentials

/// Claude Code's OAuth credentials, as stored in the login Keychain.
nonisolated struct ClaudeCredentials: Sendable {
    let accessToken: String
    let subscriptionType: String?
}

// MARK: - ClaudeCredentialStore

/// Reads (and only ever reads) the credentials Claude Code stores in the Keychain.
///
/// Burndown never writes to it and never refreshes it — see `UsageError.recoverySuggestion(for:)`.
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
        // Claude Code replaces this item when tokens rotate, discarding access granted directly to
        // Burndown. Apple's security tool uses the stable apple-tool Keychain partition instead.
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", self.service, "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw .credentialsUnreadable("Couldn't read the login Keychain")
        }

        guard process.terminationStatus == 0 else {
            if process.terminationStatus == 44 { throw .notSignedIn }
            logger.warning("Keychain lookup failed with exit code \(process.terminationStatus).")
            throw .credentialsUnreadable("Keychain access failed")
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()

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

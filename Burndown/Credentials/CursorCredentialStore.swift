import Foundation
import PolyKit

// MARK: - CursorCredentials

/// Cursor's access token, extracted from the IDE's local SQLite store.
///
/// Cursor stores this in `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
/// under the `cursorAuth/accessToken` key. Burndown reads it; it never refreshes — Burndown doesn't
/// own the credential lifecycle for any provider, and adding Cursor-specific refresh logic would be
/// the first such client. If the access token stops working, the user reopens Cursor.
nonisolated struct CursorCredentials: Sendable {
    let accessToken: String
    /// The Stripe membership tier ("pro", "ultra"), used only as a plan label in the popover. The
    /// usage endpoint doesn't name the plan, and the same database row already has it.
    let membershipType: String?
}

// MARK: - CursorCredentialStore

/// Reads Cursor's stored access token from its IDE state database.
///
/// macOS-only. The state database is a SQLite file, so a `sqlite3` shell call extracts the values.
/// Silently returns `notSignedIn` on any read failure — including missing database, missing CLI, or
/// non-macOS platforms — so a non-Cursor user pays no startup cost.
nonisolated enum CursorCredentialStore {
    /// Cursor's state database. Lives in the user's Application Support directory.
    static let stateDatabaseURL: URL = .homeDirectory
        .appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb", directoryHint: .notDirectory)

    private static let accessTokenKey = "cursorAuth/accessToken"
    private static let membershipTypeKey = "cursorAuth/stripeMembershipType"

    static func load() throws(UsageError) -> CursorCredentials {
        let url = self.stateDatabaseURL
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw .notSignedIn
        }

        // Any failure to read — missing `sqlite3` on PATH, malformed value, non-macOS — is a
        // not-signed-in condition. The menu bar is supposed to keep working when one provider is
        // absent.
        let values = self.readValues(forKeys: [Self.accessTokenKey, Self.membershipTypeKey], from: url)
        guard let token = values[Self.accessTokenKey], !token.isEmpty else {
            throw .notSignedIn
        }

        return CursorCredentials(
            accessToken: token,
            membershipType: values[Self.membershipTypeKey]?.capitalized,
        )
    }

    /// Runs a one-shot `sqlite3` read of `ItemTable` for the given keys.
    ///
    /// Returns whatever subset of the keys resolved to a non-empty string, and an empty dictionary
    /// on any failure (sqlite missing, malformed rows). The state database is large enough that
    /// it's worth reading every key Burndown needs in a single query. Keys are escaped against
    /// single quotes only — they are well-known constants, not user input.
    private static func readValues(forKeys keys: [String], from url: URL) -> [String: String] {
        let list = keys
            .map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ", ")
        let query = "SELECT key, value FROM ItemTable WHERE key IN (\(list));"

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["sqlite3", "-json", url.path(percentEncoded: false), query]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return [:]
        }

        // Read before waiting: a large result would otherwise fill the pipe buffer and deadlock.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return [:] }

        // sqlite3 -json emits a JSON array of objects: `[{ "key": "...", "value": "..." }]`.
        struct Row: Decodable {
            let key: String
            let value: String?
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }

        return rows.reduce(into: [:]) { result, row in
            guard
                let trimmed = row.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                !trimmed.isEmpty else { return }
            result[row.key] = trimmed
        }
    }
}

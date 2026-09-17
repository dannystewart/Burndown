import Foundation

/// Reads OpenCode Go (Zen) subscription quota from the public usage endpoint.
///
/// The endpoint accepts the stable bearer token OpenCode writes to its own `auth.json`. It reports
/// three windows by name — `rolling`, `weekly`, and `monthly` — rather than positionally, so each
/// window's duration is fixed here; the payload carries only a reset instant, not a window length.
nonisolated enum OpenCodeGoUsageClient {
    /// The windows arrive wrapped in a `usage` object rather than at the top level.
    private struct Response: Decodable {
        struct Usage: Decodable {
            let rolling: Window?
            let weekly: Window?
            let monthly: Window?
        }

        struct Window: Decodable {
            let percent: Double?
            let resetsAt: Date?
        }

        let usage: Usage?
    }

    private static let endpoint: URL = .init(string: "https://opencode.ai/zen/go/v1/usage")!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try OpenCodeGoCredentialStore.load()

        var request = URLRequest(url: self.endpoint)
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("openchamber-usage", forHTTPHeaderField: "x-opencode-session")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await UsageHTTP.get(request, as: Response.self, provider: .opencodeGo)

        guard let usage = response.usage else {
            throw UsageError.malformedResponse("No usage in OpenCode Go response")
        }

        let windows: [QuotaWindow] = [
            Self.window(usage.rolling, kind: .session, duration: 5 * 3600),
            Self.window(usage.weekly, kind: .weekly, duration: 7 * 86400),
            Self.window(usage.monthly, kind: .monthly, duration: 30 * 86400),
        ].compactMap(\.self)

        return UsageSnapshot(
            provider: .opencodeGo,
            capturedAt: .now,
            windows: windows,
            plan: nil,
        )
    }

    private static func window(_ entry: Response.Window?, kind: QuotaWindowKind, duration: TimeInterval) -> QuotaWindow? {
        guard let entry, let percent = entry.percent, let resetsAt = entry.resetsAt else { return nil }
        return QuotaWindow(
            kind: kind,
            usedPercent: percent.clamped(to: 0 ... 100),
            resetsAt: resetsAt,
            duration: duration,
        )
    }
}

import Foundation

/// Reads Claude subscription quota from the OAuth usage endpoint Claude Code itself uses.
nonisolated enum ClaudeUsageClient {
    private struct Response: Decodable {
        struct Window: Decodable {
            private enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }

            let utilization: Double
            let resetsAt: Date

            func window(kind: QuotaWindowKind, duration: TimeInterval) -> QuotaWindow {
                QuotaWindow(
                    kind: kind,
                    usedPercent: self.utilization.clamped(to: 0 ... 100),
                    resetsAt: self.resetsAt,
                    duration: duration,
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }

        let fiveHour: Window?
        let sevenDay: Window?
    }

    private static let endpoint: URL = .init(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try ClaudeCredentialStore.load()

        var request = URLRequest(url: self.endpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let response = try await UsageHTTP.get(request, as: Response.self, provider: .claude)

        // Anthropic names its windows explicitly, so the durations are known rather than reported.
        let windows: [QuotaWindow] = [
            response.fiveHour.map { $0.window(kind: .session, duration: 5 * 3600) },
            response.sevenDay.map { $0.window(kind: .weekly, duration: 7 * 86400) },
        ].compactMap(\.self)

        return UsageSnapshot(
            provider: .claude,
            capturedAt: .now,
            windows: windows,
            plan: credentials.subscriptionType,
        )
    }
}

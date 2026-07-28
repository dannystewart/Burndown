import Foundation

/// Reads Claude subscription quota from the OAuth usage endpoint Claude Code itself uses.
nonisolated enum ClaudeUsageClient {
    private struct Response: Decodable {
        struct Window: Decodable {
            private enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }

            /// Optional so a null field costs one window rather than the whole response.
            ///
            /// Declaring the parent as `Window?` isn't enough: optional decoding only tolerates an
            /// explicit `null` for the entire object, so a null *inside* it still throws and takes
            /// every other window down with it. Anthropic does return null resets elsewhere in this
            /// payload (the scoped weekly limit), so the shape is clearly permitted.
            let utilization: Double?
            let resetsAt: Date?

            func window(kind: QuotaWindowKind, duration: TimeInterval) -> QuotaWindow? {
                guard let utilization = self.utilization, let resetsAt = self.resetsAt else {
                    return nil
                }
                return QuotaWindow(
                    kind: kind,
                    usedPercent: utilization.clamped(to: 0 ... 100),
                    resetsAt: resetsAt,
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
            response.fiveHour.flatMap { $0.window(kind: .session, duration: 5 * 3600) },
            response.sevenDay.flatMap { $0.window(kind: .weekly, duration: 7 * 86400) },
        ].compactMap(\.self)

        return UsageSnapshot(
            provider: .claude,
            capturedAt: .now,
            windows: windows,
            plan: credentials.subscriptionType,
        )
    }
}

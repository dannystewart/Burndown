import Foundation

/// Reads Codex subscription quota from the ChatGPT backend endpoint the Codex CLI uses.
nonisolated enum CodexUsageClient {
    private struct Response: Decodable {
        struct RateLimit: Decodable {
            private enum CodingKeys: String, CodingKey {
                case primaryWindow = "primary_window"
                case secondaryWindow = "secondary_window"
            }

            let primaryWindow: Window?
            let secondaryWindow: Window?
        }

        struct Window: Decodable {
            private enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAfterSeconds = "reset_after_seconds"
                case resetAt = "reset_at"
            }

            /// Optional for the same reason as every other field here: a single null anywhere in
            /// the object fails the whole response, not just this window.
            let usedPercent: Double?
            let limitWindowSeconds: Double?
            let resetAfterSeconds: Double?
            /// Absolute reset time as a Unix timestamp, when provided.
            let resetAt: Double?

            func window() -> QuotaWindow? {
                guard let usedPercent, let duration = limitWindowSeconds, duration > 0 else {
                    return nil
                }

                // Prefer the absolute reset time; fall back to the relative countdown.
                let resolvedReset: Date? = self.resetAt.map { Date(timeIntervalSince1970: $0) }
                    ?? self.resetAfterSeconds.map { Date.now.addingTimeInterval($0) }
                guard let resetsAt = resolvedReset else { return nil }

                return QuotaWindow(
                    kind: QuotaWindowKind(duration: duration),
                    usedPercent: usedPercent.clamped(to: 0 ... 100),
                    resetsAt: resetsAt,
                    duration: duration,
                )
            }
        }

        private enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
            case planType = "plan_type"
        }

        let rateLimit: RateLimit?
        let planType: String?
    }

    private static let endpoint: URL = .init(string: "https://chatgpt.com/backend-api/codex/usage")!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try CodexCredentialStore.load()

        var request = URLRequest(url: self.endpoint)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountID, forHTTPHeaderField: "chatgpt-account-id")

        let response = try await UsageHTTP.get(request, as: Response.self, provider: .codex)

        // Codex reports windows positionally, and which window lands in which slot varies by plan:
        // a Pro account may report only a weekly window in the "primary" slot. Classify by the
        // reported length and keep the first of each kind.
        var windows = [QuotaWindow]()
        for reported in [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow] {
            guard let window = reported?.window() else { continue }
            guard !windows.contains(where: { $0.kind == window.kind }) else { continue }
            windows.append(window)
        }

        return UsageSnapshot(
            provider: .codex,
            capturedAt: .now,
            windows: windows,
            plan: response.planType ?? credentials.planType,
        )
    }
}

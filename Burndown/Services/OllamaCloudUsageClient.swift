import Foundation

/// Reads included monthly credits or legacy quota windows from Ollama's balance API.
///
/// Purchased credits have no shared monthly allowance or reset, so they must not be folded into
/// the subscription window. See https://docs.ollama.com/api/balance.
nonisolated enum OllamaCloudUsageClient {
    private struct Response: Decodable {
        struct Included: Decodable {
            struct Period: Decodable {
                let from: Date
                let until: Date
            }

            struct LegacyWindow: Decodable {
                enum CodingKeys: String, CodingKey {
                    case remainingPercent = "remaining_percent"
                    case resetsAt = "resets_at"
                }

                let remainingPercent: Double
                let resetsAt: Date
            }

            enum CodingKeys: String, CodingKey {
                case balanceUSD = "balance_usd"
                case allowanceUSD = "allowance_usd"
                case period
                case session
                case weekly
            }

            let balanceUSD: Double?
            let allowanceUSD: Double?
            let period: Period?
            let session: LegacyWindow?
            let weekly: LegacyWindow?
        }

        let included: Included
    }

    private static let endpoint: URL = .init(string: "https://ollama.com/api/balance")!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try OllamaCloudCredentialStore.load()
        var request = URLRequest(url: self.endpoint)
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response = try await UsageHTTP.get(request, as: Response.self, provider: .ollamaCloud)
        let included = response.included
        var windows = [QuotaWindow]()

        if let balance = included.balanceUSD, let allowance = included.allowanceUSD, let period = included.period {
            let duration = period.until.timeIntervalSince(period.from)
            guard balance.isFinite, allowance.isFinite, allowance > 0, duration > 0 else {
                throw .malformedResponse("Unexpected response format")
            }
            windows.append(QuotaWindow(
                kind: QuotaWindowKind(duration: duration),
                usedPercent: ((1 - balance / allowance) * 100).clamped(to: 0 ... 100),
                resetsAt: period.until,
                duration: duration,
            ))
        }

        for (entry, duration) in [
            (included.session, TimeInterval(5 * 3600)),
            (included.weekly, TimeInterval(7 * 86400)),
        ] {
            guard let entry else { continue }
            guard entry.remainingPercent.isFinite, (0 ... 100).contains(entry.remainingPercent) else {
                throw .malformedResponse("Unexpected response format")
            }
            windows.append(QuotaWindow(
                kind: QuotaWindowKind(duration: duration),
                usedPercent: 100 - entry.remainingPercent,
                resetsAt: entry.resetsAt,
                duration: duration,
            ))
        }

        guard !windows.isEmpty else {
            throw .malformedResponse("Unexpected response format")
        }
        // The balance API does not identify the subscription tier.
        return UsageSnapshot(provider: .ollamaCloud, capturedAt: .now, windows: windows, plan: nil)
    }
}

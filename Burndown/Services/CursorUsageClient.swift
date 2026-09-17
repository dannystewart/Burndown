import Foundation

/// Reads Cursor's subscription quota from its dashboard RPC endpoint.
///
/// Cursor serves `aiserver.v1.DashboardService` over Connect-RPC: a POST with an empty JSON body
/// and a protocol-version header. The response describes one billing cycle, so Burndown reports a
/// single window whose kind comes from the cycle's real length — a monthly plan lands as `.monthly`.
nonisolated enum CursorUsageClient {
    /// Cursor sends the billing cycle bounds as epoch milliseconds inside a JSON *string*
    /// (`"1791579489000"`), which the shared ISO-8601 date strategy can't read. Bare numbers are
    /// accepted too, since nothing documents the string encoding as stable.
    private struct EpochMilliseconds: Decodable {
        let date: Date

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()

            let milliseconds: Double
            if let text = try? container.decode(String.self) {
                guard let parsed = Double(text) else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: decoder.codingPath, debugDescription: "Bad epoch: \(text)"),
                    )
                }
                milliseconds = parsed
            } else {
                milliseconds = try container.decode(Double.self)
            }

            self.date = Date(timeIntervalSince1970: milliseconds / 1000)
        }
    }

    private struct PlanUsage: Decodable {
        /// Spend already consumed this cycle, in cents.
        let totalSpend: Double?
        /// The included allowance for this cycle, in cents.
        let limit: Double?
        let remaining: Double?
        let totalPercentUsed: Double?
    }

    private struct UsageResponse: Decodable {
        let planUsage: PlanUsage?
        let billingCycleStart: EpochMilliseconds?
        let billingCycleEnd: EpochMilliseconds?
        let enabled: Bool?
    }

    private static let usageURL: URL = .init(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
    )!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try CursorCredentialStore.load()
        let response = try await connectPost(url: usageURL, token: credentials.accessToken, as: UsageResponse.self)

        // A signed-in account with no paid plan answers with `enabled: false` and no usage block.
        guard response.enabled != false, let planUsage = response.planUsage else {
            throw UsageError.malformedResponse("No active Cursor subscription")
        }

        guard let cycleEnd = response.billingCycleEnd?.date else {
            throw UsageError.malformedResponse("Missing Cursor billing cycle")
        }
        guard let percent = percentUsed(planUsage) else {
            throw UsageError.malformedResponse("Missing Cursor plan quota")
        }

        // The window is as long as the billing cycle, not as long as what's left of it. Measuring
        // from "now" would shrink the window as the cycle ran down and reclassify a monthly plan as
        // weekly in its final days, changing both the forecast branch and the chart's axis.
        let duration = response.billingCycleStart.map { cycleEnd.timeIntervalSince($0.date) }
            ?? cycleEnd.timeIntervalSinceNow
        guard duration > 0 else {
            throw UsageError.malformedResponse("Cursor billing cycle already ended")
        }

        return UsageSnapshot(
            provider: .cursor,
            capturedAt: .now,
            windows: [
                QuotaWindow(
                    kind: QuotaWindowKind(duration: duration),
                    usedPercent: percent,
                    resetsAt: cycleEnd,
                    duration: duration,
                ),
            ],
            plan: credentials.membershipType,
        )
    }

    /// Share of the cycle's included allowance already spent.
    ///
    /// Derived from spend rather than from the response's own `totalPercentUsed`, which tracks a
    /// narrower auto-model figure: for an account 6% through its allowance, Cursor's dashboard reads
    /// "you've used 6% of your included usage" while `totalPercentUsed` reports 0.72. Spend over the
    /// limit is the number the user sees in Cursor, so it's the one the menu bar should agree with.
    private static func percentUsed(_ usage: PlanUsage) -> Double? {
        if let limit = usage.limit, limit > 0 {
            let spent = usage.totalSpend ?? usage.remaining.map { limit - $0 }
            if let spent { return (spent / limit * 100).clamped(to: 0 ... 100) }
        }
        return usage.totalPercentUsed?.clamped(to: 0 ... 100)
    }

    /// Connect-RPC POST with an empty JSON body and the required protocol version header.
    private static func connectPost<Response: Decodable>(
        url: URL,
        token: String,
        as _: Response.Type,
    ) async throws(UsageError) -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        return try await UsageHTTP.get(request, as: Response.self, provider: .cursor)
    }
}

import Foundation
import PolyKit

/// Reads Ollama Cloud quota from the logged-in settings page at `ollama.com/settings`.
///
/// Ollama exposes no quota API; the only machine-readable source is the server-rendered settings
/// page, reached with the browser cookies the user pastes into Burndown (`aid` and
/// `__Secure-session`, supplied as one header value). The page serves two shapes: percent-based
/// plans show "Session usage" (five hours) and "Weekly usage" (seven days) meters, while cost-based
/// plans show "Monthly usage: $X of $Y used" for included credits. Each meter is followed by a
/// `data-time` attribute carrying its reset instant.
///
/// This scrapes presentation markup — a redirect or a redesign reads as an error rather than data,
/// and no windows parsed means no snapshot, never an authoritative zero.
nonisolated enum OllamaCloudUsageClient {
    private static let endpoint: URL = .init(string: "https://ollama.com/settings")!

    static func fetch() async throws(UsageError) -> UsageSnapshot {
        let credentials = try OllamaCloudCredentialStore.load()

        var request = URLRequest(url: self.endpoint)
        request.setValue(credentials.cookie, forHTTPHeaderField: "Cookie")
        request.setValue("Burndown usage tracker", forHTTPHeaderField: "User-Agent")

        let response = try await UsageHTTP.get(request, provider: .ollamaCloud)
        let html = response.text

        // An expired cookie doesn't fail the transport: ollama.com redirects the browser to its
        // sign-in flow and that page returns 200 successfully. Landing away from /settings is
        // therefore an authentication failure, not data.
        if response.finalURL.host != self.endpoint.host || response.finalURL.path != self.endpoint.path {
            logger.warning("Ollama Cloud redirected the settings request; session is expired.")
            throw .credentialsExpired
        }

        var windows = [QuotaWindow]()
        if let session = self.meter(in: html, label: "Session", duration: 5 * 3600) {
            windows.append(session)
        }
        if let weekly = self.meter(in: html, label: "Weekly", duration: 7 * 86400) {
            windows.append(weekly)
        }
        if let monthly = self.creditWindow(in: html) {
            windows.append(monthly)
        }

        guard !windows.isEmpty else {
            logger.error("Couldn't find any usage meters in the Ollama settings page.")
            throw .malformedResponse("Unexpected response format")
        }

        let plan = self.firstMatch(#"Cloud usage[\s\S]{0,400}?>\s*(free|pro|max|ultra)\s*<"#, in: html)?.groups[0]
        return UsageSnapshot(provider: .ollamaCloud, capturedAt: .now, windows: windows, plan: plan)
    }

    /// Builds one percent meter's window, pairing the label's percentage with the reset timestamp
    /// that follows it on the page. Label and reset aren't in the same markup element, so the
    /// pairing is positional: the first `data-time` after the meter's block belongs to it.
    private static func meter(in html: String, label: String, duration: TimeInterval) -> QuotaWindow? {
        guard
            let match = self.firstMatch(
                #"\#(label) usage[^0-9]{0,400}?([0-9]+(?:\.[0-9]+)?)\s*%"#,
                in: html,
            ),
            let percent = Double(match.groups[0]),
            let reset = self.reset(after: match.upperBound, in: html) else { return nil }

        return QuotaWindow(
            kind: QuotaWindowKind(duration: duration),
            usedPercent: percent.clamped(to: 0 ... 100),
            resetsAt: reset,
            duration: duration,
        )
    }

    /// Converts the cost-based plan's included-credit dollars into a percent the rest of Burndown
    /// already understands.
    private static func creditWindow(in html: String) -> QuotaWindow? {
        guard
            let match = self.firstMatch(
                #"Monthly usage[\s\S]{0,400}?\$([0-9][0-9,.]*)\s+of\s+\$([0-9][0-9,.]*)"#,
                in: html,
            ),
            let used = Double(match.groups[0].replacingOccurrences(of: ",", with: "")),
            let total = Double(match.groups[1].replacingOccurrences(of: ",", with: "")),
            total > 0,
            let reset = self.reset(after: match.upperBound, in: html) else { return nil }

        return QuotaWindow(
            kind: QuotaWindowKind(duration: 30 * 86400),
            usedPercent: (used / total * 100).clamped(to: 0 ... 100),
            resetsAt: reset,
            duration: 30 * 86400,
        )
    }

    /// The first `data-time` timestamp search-positioned after a meter's block. Searching from the
    /// end of each percent match never catches a neighboring section's reset: the session meter's
    /// own timestamp precedes the weekly meter entirely.
    private static func reset(after searchStart: String.Index, in html: String) -> Date? {
        guard let attribute = html.range(of: #"data-time="([^"]+)""#, options: [.regularExpression], range: searchStart ..< html.endIndex) else {
            return nil
        }
        let valueStart = html.index(html.index(attribute.lowerBound, offsetBy: #"data-time="#.count), offsetBy: 1)
        let valueEnd = html.index(before: attribute.upperBound)
        return try? Date(String(html[valueStart ..< valueEnd]), strategy: Date.ISO8601FormatStyle())
    }

    /// The first match's capture groups, without the whole-match text, plus where the match ended
    /// so position-dependent parses (the reset timestamps) can anchor on it.
    private static func firstMatch(_ pattern: String, in html: String) -> (groups: [String], upperBound: String.Index)? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)) else { return nil }
        let groups = (1 ..< match.numberOfRanges).map { index in
            Range(match.range(at: index), in: html).map { String(html[$0]) } ?? ""
        }
        return (groups, Range(match.range, in: html)?.upperBound ?? html.endIndex)
    }
}

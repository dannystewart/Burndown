import Foundation
import PolyKit

/// Shared request plumbing for the provider usage endpoints.
nonisolated enum UsageHTTP {
    /// The body and final URL of a text response.
    nonisolated struct TextResponse: Sendable {
        let text: String
        /// Where the request actually landed. Providers that authenticate with browser cookies get
        /// silently redirected to a sign-in page when the session expires, and the final URL is the
        /// only reliable signal of that.
        let finalURL: URL
    }

    /// These are small, frequent polls, and a cached response would quietly show stale numbers.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseTimestamp(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(text)"),
                )
            }
            return date
        }
        return decoder
    }()

    private static let excerptLimit = 600

    /// Performs a request and decodes it, translating transport and status codes into `UsageError`.
    static func get<Response: Decodable>(
        _ request: URLRequest,
        as _: Response.Type,
        provider: Provider,
    ) async throws(UsageError) -> Response {
        let (data, _) = try await self.send(request, provider: provider)

        do {
            return try self.decoder.decode(Response.self, from: data)
        } catch {
            logger.error(
                """
                Couldn't decode \(provider.displayName) usage: \(error)
                Body: \(Self.excerpt(of: data))
                """,
            )
            throw .malformedResponse("Unexpected response format")
        }
    }

    /// Performs a request expecting a textual response, e.g. a page to scrape rather than JSON.
    static func get(
        _ request: URLRequest,
        provider: Provider,
    ) async throws(UsageError) -> TextResponse {
        let (data, http) = try await self.send(request, provider: provider)
        guard let text = String(data: data, encoding: .utf8) else {
            throw .malformedResponse("Unexpected response format")
        }
        return TextResponse(text: text, finalURL: http.url ?? request.url ?? URL(fileURLWithPath: "/"))
    }

    private static func send(
        _ request: URLRequest,
        provider: Provider,
    ) async throws(UsageError) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet {
            throw .network("Offline")
        } catch {
            throw .network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw .malformedResponse("Unexpected response")
        }

        switch http.statusCode {
        case 200 ..< 300:
            break

        case 401, 403:
            logger.warning("\(provider.displayName) rejected the stored token.")
            throw .credentialsExpired

        case 429:
            logger.warning("\(provider.displayName) is throttling usage requests.")
            throw .rateLimited

        default:
            throw .network("HTTP \(http.statusCode)")
        }

        return (data, http)
    }

    /// A short, printable prefix of a response body, for diagnosing decode failures.
    ///
    /// The `DecodingError` alone can't distinguish a missing field from a body that was never JSON
    /// (an edge or proxy error page returned with a 200), and these failures are transient enough
    /// that they can't reliably be reproduced after the fact. Neither usage endpoint returns
    /// credentials in its body, so the excerpt is safe to logger.
    private static func excerpt(of data: Data) -> String {
        guard !data.isEmpty else { return "<empty>" }
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, not UTF-8>"
        }

        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > self.excerptLimit
            ? "\(collapsed.prefix(self.excerptLimit))… (\(data.count) bytes)"
            : collapsed
    }

    /// Parses an ISO-8601 timestamp, tolerating more precision than Foundation accepts.
    ///
    /// Anthropic returns microseconds (`16:30:00.041293+00:00`), which the fractional-seconds
    /// option rejects outright, so the fraction is dropped on the second attempt. Sub-second
    /// precision is meaningless for a quota reset.
    ///
    /// The formatter is built per call rather than stored because `ISO8601DateFormatter` isn't
    /// `Sendable` and this runs inside the decoder's `@Sendable` closure.
    private static func parseTimestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }

        formatter.formatOptions = [.withInternetDateTime]
        if
            let dot = text.firstIndex(of: "."),
            let fractionEnd = text[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        {
            return formatter.date(from: text.replacingCharacters(in: dot ..< fractionEnd, with: ""))
        }
        return formatter.date(from: text)
    }
}

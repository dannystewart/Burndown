import Foundation

/// A closure type that fetches a provider's current quota state.
///
/// The recorder looks up the closure through `UsageProviderRegistry.shared` so adding a new
/// provider is a single registration site. Each existing client's `static fetch()` matches this
/// signature, so no client code changes shape.
typealias UsageProviderFetcher = @Sendable () async throws(UsageError) -> UsageSnapshot

// MARK: - UsageProviderRegistry

/// Maps a `Provider` enum case to its fetcher.
///
/// The static registry replaces the single dispatch switch that used to live in `UsageRecorder`.
/// New providers register a fetcher here; the recorder loop iterates `Provider.allCases` and looks
/// the fetcher up by enum case.
final class UsageProviderRegistry: @unchecked Sendable {
    static let shared: UsageProviderRegistry = .init()

    private var fetchers: [Provider: UsageProviderFetcher] = [
        .claude: ClaudeUsageClient.fetch,
        .codex: CodexUsageClient.fetch,
        .cursor: CursorUsageClient.fetch,
        .opencodeGo: OpenCodeGoUsageClient.fetch,
    ]

    func fetcher(for provider: Provider) -> UsageProviderFetcher? {
        self.fetchers[provider]
    }

    func register(_ fetcher: @escaping UsageProviderFetcher, for provider: Provider) {
        self.fetchers[provider] = fetcher
    }
}

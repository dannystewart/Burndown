import Foundation
import PolyKit
@preconcurrency import XPC

// MARK: - AgentConstants

nonisolated enum AgentConstants {
    static let launchArgument = "--agent"
    static let launchAgentPlist = "com.dannystewart.Burndown.agent.plist"
    static let machService = "com.dannystewart.Burndown.agent"
    static let signingIdentifier = "com.dannystewart.Burndown"
}

// MARK: - AgentOperation

nonisolated enum AgentOperation: String, Codable, Sendable {
    case state
    case refresh
    case refreshForPopover
}

// MARK: - AgentRequest

nonisolated struct AgentRequest: Codable, Sendable {
    let operation: AgentOperation
}

// MARK: - AgentDashboard

nonisolated struct AgentDashboard: Codable, Sendable {
    static let empty: AgentDashboard = .init(
        states: Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, .loading) }),
        samples: [],
        refreshingProviders: [],
        lastAttempts: [:],
        generatedAt: .now,
    )

    let states: [Provider: ProviderState]
    let samples: [UsageSample]
    let refreshingProviders: Set<Provider>
    let lastAttempts: [Provider: Date]
    let generatedAt: Date
}

// MARK: - AgentClient

/// Maintains the menu app's authenticated connection to the recorder process.
actor AgentClient {
    private var session: XPCSession? = nil

    func request(_ operation: AgentOperation) async throws -> AgentDashboard {
        let session: XPCSession
        do {
            session = try self.activeSession()
        } catch {
            self.session = nil
            throw error
        }

        do {
            let response: AgentDashboard = try await withCheckedThrowingContinuation { continuation in
                do {
                    try session.send(AgentRequest(operation: operation)) {
                        (result: Result<AgentDashboard, any Error>) in
                        continuation.resume(with: result)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            return response
        } catch {
            session.cancel(reason: "Request failed")
            self.session = nil
            throw error
        }
    }

    private func activeSession() throws -> XPCSession {
        if let session = self.session { return session }

        let session = try XPCSession(
            machService: AgentConstants.machService,
            cancellationHandler: { error in
                logger.warning("Recorder connection ended: \(error)")
            },
        )
        self.session = session
        return session
    }
}

import Dispatch
import Foundation
import PolyKit
@preconcurrency import XPC

// MARK: - AgentRuntime

/// Boots the non-UI process that launchd starts from the Burndown executable.
nonisolated enum AgentRuntime {
    private static let replyQueue: DispatchQueue = .init(label: "com.dannystewart.Burndown.agent.replies")

    static func run() -> Never {
        let recorder = UsageRecorder()
        Task {
            await recorder.start()
        }

        do {
            let listener = try XPCListener(
                service: AgentConstants.machService,
                requirement: .isFromSameTeam(
                    andMatchesSigningIdentifier: AgentConstants.signingIdentifier,
                ),
            ) { request in
                request.accept { _ in
                    AgentPeer(recorder: recorder, replyQueue: self.replyQueue)
                }
            }
            logger.info("Background recorder is accepting connections.")
            withExtendedLifetime(listener) {
                dispatchMain()
            }
        } catch {
            logger.error("Couldn't start the recorder listener: \(error.localizedDescription)")
            exit(EXIT_FAILURE)
        }
    }
}

// MARK: - AgentPeer

/// Handles one authenticated menu-app connection. Work crosses to the recorder actor before the
/// response is sent, so provider refreshes and persistence remain serialized regardless of how many
/// clients connect.
private nonisolated struct AgentPeer: XPCPeerHandler {
    let recorder: UsageRecorder
    let replyQueue: DispatchQueue

    func handleIncomingRequest(_ message: XPCReceivedMessage) -> (any Encodable)? {
        let operation: AgentOperation
        do {
            operation = try message.decode(as: AgentRequest.self).operation
        } catch {
            logger.warning("Rejected an unreadable recorder request: \(error.localizedDescription)")
            return nil
        }

        return message.handoffReply(to: self.replyQueue) {
            Task {
                let dashboard = await self.recorder.handle(operation)
                message.reply(dashboard)
            }
        }
    }

    func handleCancellation(error: XPCRichError) {
        logger.debug("Recorder client disconnected: \(error)")
    }
}

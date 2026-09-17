import Foundation
import PolyKit
import ServiceManagement

// MARK: - RecorderServiceStatus

nonisolated enum RecorderServiceStatus: Sendable, Equatable {
    case checking
    case enabled
    case requiresApproval
    case unavailable(String)

    var description: String {
        switch self {
        case .checking: "Checking…"
        case .enabled: "Running"
        case .requiresApproval: "Approval required"
        case let .unavailable(message): message
        }
    }

    var needsSystemSettings: Bool {
        if case .requiresApproval = self { true } else { false }
    }
}

// MARK: - BackgroundService

/// Registers the launchd-managed recorder and migrates away from launching the UI at login.
@MainActor
enum BackgroundService {
    static var status: RecorderServiceStatus {
        switch self.service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .unavailable("Not registered")
        case .notFound where self.hasBundledPlist: .unavailable("Not registered")
        case .notFound: .unavailable("Recorder is missing from this app build")
        @unknown default: .unavailable("Unknown recorder status")
        }
    }

    private static var service: SMAppService {
        .agent(plistName: AgentConstants.launchAgentPlist)
    }

    private static var bundledPlistURL: URL {
        Bundle.main
            .bundleURL
            .appending(path: "Contents/Library/LaunchAgents", directoryHint: .isDirectory)
            .appending(path: AgentConstants.launchAgentPlist, directoryHint: .notDirectory)
    }

    private static var hasBundledPlist: Bool {
        FileManager.default.fileExists(atPath: self.bundledPlistURL.path)
    }

    /// Registration is idempotent. Once the agent is eligible to run, the old main-app login item
    /// is removed so logging in never opens the menu bar UI.
    static func prepare() -> RecorderServiceStatus {
        guard self.hasBundledPlist else {
            logger.error("Background recorder plist is missing at \(self.bundledPlistURL.path)")
            return .unavailable("Recorder is missing from this app build")
        }

        if self.service.status == .notRegistered || self.service.status == .notFound {
            do {
                try self.service.register()
                logger.info("Registered the background recorder.")
            } catch {
                logger.error("Couldn't register the background recorder: \(error.localizedDescription)")
                return .unavailable(error.localizedDescription)
            }
        }

        let status = self.status
        if status == .enabled, SMAppService.mainApp.status != .notRegistered {
            do {
                try SMAppService.mainApp.unregister()
                logger.info("Removed the legacy UI login item.")
            } catch {
                logger.warning("Couldn't remove the legacy UI login item: \(error.localizedDescription)")
            }
        }
        return status
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

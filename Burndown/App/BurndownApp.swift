import AppKit
import PolyKit
import SwiftUI

// MARK: - BurndownEntryPoint

@main
nonisolated enum BurndownEntryPoint {
    static func main() {
        if ProcessInfo.processInfo.arguments.contains(AgentConstants.launchArgument) {
            AgentRuntime.run()
        } else {
            BurndownApp.main()
        }
    }
}

// MARK: - BurndownApp

struct BurndownApp: App {
    // swiftformat:disable:next unusedPrivateDeclarations
    @NSApplicationDelegateAdaptor(BurndownAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(
                monitor: self.appDelegate.monitor,
                onOpenSettings: self.appDelegate.openSettings,
            )
        } label: {
            MenuBarLabel(monitor: self.appDelegate.monitor, preferences: self.appDelegate.preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - BurndownAppDelegate

@MainActor
private final class BurndownAppDelegate: NSObject, NSApplicationDelegate {
    let monitor: UsageMonitor = .init()
    let preferences: Preferences = .shared

    private var settingsHost: PolySettingsHost?

    func applicationWillFinishLaunching(_ notification: Notification) {
        self.settingsHost = PolySettingsHost.install(
            applicationWillFinishLaunching: notification,
            configuration: .accessoryApp(
                aboutInfo: .init(),
                commandQBehavior: .quit,
            ),
        ) {
            SettingsView(preferences: self.preferences, monitor: self.monitor)
        }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func openSettings() {
        self.settingsHost?.open()
    }
}

// MARK: - Logger

nonisolated let logger: PolyLog = .init(capture: true)

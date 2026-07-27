import Foundation

/// Everything the user can change, persisted to `UserDefaults`.
///
/// This is deliberately a single observable object rather than scattered `@AppStorage` properties:
/// the menu bar label has to render from the same values the settings window writes, and a shared
/// object keeps that one source of truth instead of two views agreeing by coincidence.
@Observable
@MainActor
final class Preferences {
    private enum Key {
        static let menuBarLayout = "menuBarLayout"
        static let menuBarColorMode = "menuBarColorMode"
        static let singleLineFormat = "singleLineFormat"
        static let stackedFormat = "stackedFormat"
    }

    static let shared: Preferences = .init()

    private nonisolated static var defaults: UserDefaults { .standard }

    var menuBarLayout: MenuBarLayout {
        didSet { Self.defaults.set(self.menuBarLayout.rawValue, forKey: Key.menuBarLayout) }
    }

    var menuBarColorMode: MenuBarColorMode {
        didSet { Self.defaults.set(self.menuBarColorMode.rawValue, forKey: Key.menuBarColorMode) }
    }

    /// One line has only one window's worth of room, so it defaults to the bare number.
    var singleLineFormat: MenuBarFormat {
        didSet { Self.defaults.set(self.singleLineFormat.rawValue, forKey: Key.singleLineFormat) }
    }

    /// Two lines are the reason to ask for two lines, so they default to carrying more.
    var stackedFormat: MenuBarFormat {
        didSet { Self.defaults.set(self.stackedFormat.rawValue, forKey: Key.stackedFormat) }
    }

    /// The format in force for the layout currently on screen.
    var activeFormat: MenuBarFormat {
        switch self.menuBarLayout {
        case .single: self.singleLineFormat
        case .stacked: self.stackedFormat
        }
    }

    private init() {
        self.menuBarLayout = Self.read(Key.menuBarLayout) ?? .single
        self.menuBarColorMode = Self.read(Key.menuBarColorMode) ?? .whenLow
        self.singleLineFormat = Self.read(Key.singleLineFormat) ?? .percentage
        self.stackedFormat = Self.read(Key.stackedFormat) ?? .percentageAndRemaining
    }

    private nonisolated static func read<Value: RawRepresentable>(_ key: String) -> Value?
        where Value.RawValue == String
    {
        self.defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }
}

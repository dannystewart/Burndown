//
//  Preferences.swift
//  Burndown
//

import Foundation

/// How much of the menu bar Burndown is allowed to take up.
nonisolated enum MenuBarLayout: String, CaseIterable, Identifiable, Sendable {
    /// A single glyph and the tightest percentage.
    case single
    /// One compact row per provider, stacked within the menu bar's height.
    case stacked

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
            case .single: "Single line"
            case .stacked: "Two lines"
        }
    }
}

/// Everything the user can change, persisted to `UserDefaults`.
///
/// This is deliberately a single observable object rather than scattered `@AppStorage` properties:
/// the menu bar label has to render from the same values the settings window writes, and a shared
/// object keeps that one source of truth instead of two views agreeing by coincidence.
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    private enum Key {
        static let menuBarLayout = "menuBarLayout"
        static let menuBarUsesColor = "menuBarUsesColor"
    }

    var menuBarLayout: MenuBarLayout {
        didSet { Self.defaults.set(self.menuBarLayout.rawValue, forKey: Key.menuBarLayout) }
    }

    /// Color draws the eye, which is useful when a window is nearly spent and noise otherwise.
    var menuBarUsesColor: Bool {
        didSet { Self.defaults.set(self.menuBarUsesColor, forKey: Key.menuBarUsesColor) }
    }

    private nonisolated static var defaults: UserDefaults { .standard }

    private init() {
        let stored = Self.defaults.string(forKey: Key.menuBarLayout)
        self.menuBarLayout = stored.flatMap(MenuBarLayout.init(rawValue:)) ?? .single
        self.menuBarUsesColor = Self.defaults.bool(forKey: Key.menuBarUsesColor)
    }
}

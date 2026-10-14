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
        static let menuBarFormat = "menuBarFormat"
        static let preferredProvider = "preferredProvider"
        static let preferredSecondProvider = "preferredSecondProvider"
        static let hiddenProviders = "hiddenProviders"
        static let selectedWindows = "selectedWindows"
        static let providerOrder = "providerOrder"
    }

    static let shared: Preferences = .init()

    private nonisolated static var defaults: UserDefaults { .standard }

    var menuBarLayout: MenuBarLayout {
        didSet { Self.defaults.set(self.menuBarLayout.rawValue, forKey: Key.menuBarLayout) }
    }

    var menuBarColorMode: MenuBarColorMode {
        didSet { Self.defaults.set(self.menuBarColorMode.rawValue, forKey: Key.menuBarColorMode) }
    }

    /// The same format drives both layouts: a single row per provider, or a two-part stack under
    /// one icon when only one provider is shown.
    var menuBarFormat: MenuBarFormat {
        didSet { Self.defaults.set(self.menuBarFormat.rawValue, forKey: Key.menuBarFormat) }
    }

    var preferredProvider: MenuBarProviderSelection {
        didSet { Self.defaults.set(self.preferredProvider.rawValue, forKey: Key.preferredProvider) }
    }

    var preferredSecondProvider: MenuBarProviderSelection {
        didSet { Self.defaults.set(self.preferredSecondProvider.rawValue, forKey: Key.preferredSecondProvider) }
    }

    /// Providers hidden from every menu bar surface — the icon label and the dropdown alike.
    ///
    /// Hiding never stops monitoring or recording: the provider keeps accumulating history in the
    /// background so it comes back with nothing lost the moment it's shown again.
    var hiddenProviders: Set<Provider> {
        didSet {
            Self.defaults.set(self.hiddenProviders.map(\.rawValue), forKey: Key.hiddenProviders)
        }
    }

    /// Includes hidden and unsigned-in providers so their positions aren't lost when they return.
    private(set) var providerOrder: [Provider] {
        didSet { Self.defaults.set(self.providerOrder.map(\.rawValue), forKey: Key.providerOrder) }
    }

    /// Window identities survive resets, and remain saved even when a provider is hidden or absent.
    private var selectedWindows: [String: String] {
        didSet { Self.defaults.set(self.selectedWindows, forKey: Key.selectedWindows) }
    }

    private init() {
        self.menuBarLayout = Self.read(Key.menuBarLayout) ?? .singleProvider
        self.menuBarColorMode = Self.read(Key.menuBarColorMode) ?? .whenLow
        self.menuBarFormat = Self.read(Key.menuBarFormat) ?? .percentageAndRemaining
        self.preferredProvider = Self.read(Key.preferredProvider) ?? .lastActive
        self.preferredSecondProvider = Self.read(Key.preferredSecondProvider) ?? .lastActive
        self.hiddenProviders = Set(
            (Self.defaults.stringArray(forKey: Key.hiddenProviders) ?? []).compactMap(Provider.init(rawValue:)),
        )
        self.selectedWindows = Self.defaults.dictionary(forKey: Key.selectedWindows) as? [String: String] ?? [:]
        let savedOrder = (Self.defaults.stringArray(forKey: Key.providerOrder) ?? []).compactMap(Provider.init(rawValue:))
        var seen = Set<Provider>()
        self.providerOrder = (savedOrder + Provider.allCases).filter { seen.insert($0).inserted }
    }

    private nonisolated static func read<Value: RawRepresentable>(_ key: String) -> Value?
        where Value.RawValue == String
    {
        self.defaults.string(forKey: key).flatMap(Value.init(rawValue:))
    }

    func selectedWindowID(for provider: Provider) -> String? {
        self.selectedWindows[provider.rawValue]
    }

    func selectWindow(_ window: QuotaWindow, for provider: Provider) {
        self.selectedWindows[provider.rawValue] = window.id
    }

    func moveProviders(withIDs ids: [Provider.ID], before destinationID: Provider.ID?) {
        let movingIDs = Set(ids)
        let moved = self.providerOrder.filter { movingIDs.contains($0.id) }
        guard !moved.isEmpty, destinationID.map({ !movingIDs.contains($0) }) ?? true else { return }
        var order = self.providerOrder.filter { !movingIDs.contains($0.id) }
        let destination = order.firstIndex { $0.id == destinationID } ?? order.endIndex
        order.insert(contentsOf: moved, at: destination)
        self.providerOrder = order
    }
}

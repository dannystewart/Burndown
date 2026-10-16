import AppKit
import SwiftUI

// MARK: - MenuBarLabel

/// What sits in the menu bar.
///
/// The label is rendered to an `NSImage` rather than handed to SwiftUI as a live view. A menu bar
/// item gives its label a fixed height and no say in it, so a stacked layout laid out by SwiftUI
/// gets clipped or squashed depending on the display. Rendering it ourselves means we choose the
/// exact pixel height, and it gives us the one lever color needs: a template image takes on the
/// menu bar's own color, a non-template one keeps what we drew.
struct MenuBarLabel: View {
    /// Comfortably inside the menu bar's usable height on every display scale.
    private static let singleLineHeight: CGFloat = 15
    private static let stackedHeight: CGFloat = 20

    @Environment(\.colorScheme) private var colorScheme

    let monitor: UsageMonitor
    let preferences: Preferences

    private var rows: [MenuBarRow] {
        MenuBarRow.rows(
            from: self.monitor,
            layout: self.preferences.menuBarLayout,
            format: self.preferences.menuBarFormat,
            preferredProvider: self.preferences.preferredProvider,
            preferredSecondProvider: self.preferences.preferredSecondProvider,
        )
    }

    private var rendered: NSImage? {
        let rows = self.rows
        let colored = self.usesColor(for: rows)
        let stacked = Self.isStacked(rows)

        let drawn = rows.map { row in
            DrawnRow(id: row.id, symbol: row.symbol, parts: row.parts, color: self.color(for: row, colored: colored))
        }

        return Self.render(
            MenuBarContent(rows: drawn, height: stacked ? Self.stackedHeight : Self.singleLineHeight),
            asTemplate: !colored,
            colorScheme: self.colorScheme,
        )
    }

    var body: some View {
        if let image = self.rendered {
            Image(nsImage: image)
        } else {
            // Rendering can't fail in practice, but the menu bar item must never vanish.
            Image(systemName: "chart.line.downtrend.xyaxis")
        }
    }

    /// Anything beyond a single line needs the taller label and the smaller type.
    private static func isStacked(_ rows: [MenuBarRow]) -> Bool {
        rows.count > 1 || rows.contains { $0.parts.count > 1 }
    }

    /// Rasterises the label at the screen's own scale so it stays crisp on Retina and non-Retina.
    private static func render(_ content: some View, asTemplate: Bool, colorScheme: ColorScheme) -> NSImage? {
        // ImageRenderer is detached from the status item's environment. Pass the menu bar's actual
        // appearance through so semantic neutral colors don't get baked as black in dark mode.
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // A template image is used purely as a mask, which is exactly what makes it follow the menu
        // bar through light, dark, and tinted appearances.
        image.isTemplate = asTemplate
        return image
    }

    /// Whether the image can stay a template, and therefore keep following the menu bar's own
    /// color.
    ///
    /// Template-ness belongs to the whole image, not to individual glyphs, so a single warning row
    /// forces the entire label out of template mode. Other rows then have to be drawn in an
    /// explicit neutral color instead of inheriting one.
    private func usesColor(for rows: [MenuBarRow]) -> Bool {
        switch self.preferences.menuBarColorMode {
        case .always: true
        case .never: false
        case .whenLow: rows.contains(where: \.isWarning)
        }
    }

    private func color(for row: MenuBarRow, colored: Bool) -> Color {
        // A template image is used purely as a mask, so what it's filled with only has to be
        // opaque.
        guard colored else { return .black.opacity(row.isExhausted ? 0.45 : 1) }
        if row.isExhausted { return .secondary }
        // In "when low" the point is that color marks the exception; anything that isn't warning
        // should read as though it were still following the menu bar.
        if self.preferences.menuBarColorMode == .whenLow, !row.isWarning {
            return Color(nsColor: .labelColor)
        }
        return row.severity
    }
}

// MARK: - MenuBarRow

/// One line of the menu bar label, before any decision about color has been made.
nonisolated struct MenuBarRow: Identifiable, Sendable {
    private static var emptyRow: MenuBarRow {
        MenuBarRow(
            id: "empty",
            symbol: "chart.line.downtrend.xyaxis",
            parts: [""],
            severity: .primary,
            isWarning: false,
        )
    }

    let id: String
    let symbol: String
    /// The format's values, top to bottom. One part fills a single line.
    let parts: [String]
    /// What this row would be colored if color were switched on.
    let severity: Color
    let isWarning: Bool
    var isExhausted = false

    @MainActor
    static func rows(
        from monitor: UsageMonitor,
        layout: MenuBarLayout,
        format: MenuBarFormat,
        preferredProvider: MenuBarProviderSelection,
        preferredSecondProvider: MenuBarProviderSelection,
    ) -> [MenuBarRow] {
        switch layout {
        case .singleProvider:
            self.rows(from: monitor, format: format, selections: [preferredProvider])
        case .twoProviders:
            self.rows(from: monitor, format: format, selections: [preferredProvider, preferredSecondProvider])
        }
    }

    @MainActor
    private static func rows(
        from monitor: UsageMonitor,
        format: MenuBarFormat,
        selections: [MenuBarProviderSelection],
    ) -> [MenuBarRow] {
        var selectedProviders = Set<Provider>()
        let rows = selections.compactMap { selection -> MenuBarRow? in
            let provider: Provider? = switch selection {
            case .lastActive:
                monitor.recentlyActiveProviders.first { !selectedProviders.contains($0) }
            case let .provider(preferred):
                selectedProviders.contains(preferred) || !monitor.visibleProviders.contains(preferred) ? nil : preferred
            }

            guard let provider else { return nil }
            selectedProviders.insert(provider)
            guard let window = monitor.featuredWindow(for: provider) else { return nil }
            return Self.row(
                id: provider.rawValue,
                provider: provider,
                window: window,
                monitor: monitor,
                format: format,
            )
        }
        return rows.isEmpty ? [Self.emptyRow] : rows
    }

    @MainActor
    private static func row(
        id: String,
        provider: Provider,
        window: QuotaWindow,
        monitor: UsageMonitor,
        format: MenuBarFormat,
    ) -> MenuBarRow {
        let samples = monitor.series(for: provider, window: window)
        let now = Date.now
        let status = BurnAnalysis(window: window, samples: samples, now: now).status
        return MenuBarRow(
            id: id,
            symbol: provider.symbolName,
            parts: status == .exhausted
                ? [String(localized: "Resets in \(Format.duration(window.resetsAt.timeIntervalSince(now)))")]
                : format.parts(for: window, asOf: now),
            severity: status.severityColor,
            isWarning: status.isWarning,
            isExhausted: status == .exhausted,
        )
    }
}

// MARK: - DrawnRow

/// A row with its color already decided.
private struct DrawnRow: Identifiable {
    let id: String
    let symbol: String
    let parts: [String]
    let color: Color

    /// The parts joined for a single-line row: `12% · 5d 18h`.
    var singleLineText: String {
        self.parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - MenuBarContent

/// The drawn label, sized to fit the menu bar exactly.
private struct MenuBarContent: View {
    private static let singleLineFontSize: CGFloat = 12
    private static let stackedFontSize: CGFloat = 9

    let rows: [DrawnRow]
    let height: CGFloat

    private var lineCount: Int {
        self.rows.reduce(0) { $0 + max(1, $1.parts.count) }
    }

    private var isStacked: Bool { self.lineCount > 1 }

    /// Two lines have to share the height a single line gets all to itself.
    private var fontSize: CGFloat { self.isStacked ? Self.stackedFontSize : Self.singleLineFontSize }

    /// A lone provider with a two-part format stacks its values beside the icon, so a percentage
    /// and its reset time cost no more width than the wider of the two.
    private var sharedIconRow: DrawnRow? {
        guard self.rows.count == 1, let row = self.rows.first, row.parts.count > 1 else { return nil }
        return row
    }

    /// A grid rather than stacked `HStack`s so the two columns line up independently.
    ///
    /// Rows carry different providers and different remaining times, so their text is never the
    /// same width. Left-aligning the whole row leaves the right edges ragged; right-aligning it
    /// would just move the raggedness to the icons. Giving each column its own alignment pins the
    /// icons to the left and the text to the right, so both edges are flush.
    var body: some View {
        Group {
            if let row = self.sharedIconRow {
                HStack(spacing: 2.5) {
                    // A lone provider keeps the larger icon; only its text takes the shorter
                    // stacked type so two lines still fit the menu bar.
                    self.icon(for: row, fontSize: Self.singleLineFontSize)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(row.parts.enumerated()), id: \.offset) { _, part in
                            self.label(part, color: row.color)
                        }
                    }
                }
            } else {
                Grid(horizontalSpacing: 2.5, verticalSpacing: self.isStacked ? 1 : 0) {
                    ForEach(self.rows) { row in
                        GridRow {
                            self.icon(for: row)
                            if !row.singleLineText.isEmpty {
                                self.label(row.singleLineText, color: row.color)
                                    .gridColumnAlignment(.trailing)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: self.height, alignment: .center)
        .fixedSize()
    }

    private func icon(for row: DrawnRow, fontSize: CGFloat? = nil) -> some View {
        Image(systemName: row.symbol)
            .font(.system(size: (fontSize ?? self.fontSize) - 1, weight: .semibold))
            .foregroundStyle(row.color)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: self.fontSize, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color)
    }
}

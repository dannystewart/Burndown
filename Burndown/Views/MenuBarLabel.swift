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
            format: self.preferences.activeFormat,
        )
    }

    private var rendered: NSImage? {
        let rows = self.rows
        let colored = self.usesColor(for: rows)
        let stacked = rows.count > 1

        let drawn = rows.map { row in
            DrawnRow(id: row.id, symbol: row.symbol, text: row.text, color: self.color(for: row, colored: colored))
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

    /// Whether the image can stay a template, and therefore keep following the menu bar's own color.
    ///
    /// Template-ness belongs to the whole image, not to individual glyphs, so a single warning row
    /// forces the entire label out of template mode. Other rows then have to be drawn in an explicit
    /// neutral color instead of inheriting one.
    private func usesColor(for rows: [MenuBarRow]) -> Bool {
        switch self.preferences.menuBarColorMode {
        case .always: true
        case .never: false
        case .whenLow: rows.contains(where: \.isWarning)
        }
    }

    private func color(for row: MenuBarRow, colored: Bool) -> Color {
        // A template image is used purely as a mask, so what it's filled with only has to be opaque.
        guard colored else { return .black }
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
    let id: String
    let symbol: String
    let text: String
    /// What this row would be colored if color were switched on.
    let severity: Color
    let isWarning: Bool

    @MainActor
    static func rows(from monitor: UsageMonitor, layout: MenuBarLayout, format: MenuBarFormat) -> [MenuBarRow] {
        switch layout {
        case .single: self.single(from: monitor, format: format)
        case .stacked: self.perProvider(from: monitor, format: format)
        }
    }

    /// The soonest limit across everything visible, which is the number that would bite first.
    ///
    /// It carries its provider's own icon rather than a generic one: a bare percentage in the menu
    /// bar is ambiguous when two providers are being watched.
    @MainActor
    private static func single(from monitor: UsageMonitor, format: MenuBarFormat) -> [MenuBarRow] {
        guard let soonest = monitor.soonestLimit else {
            return [
                MenuBarRow(
                    id: "empty",
                    symbol: "chart.line.downtrend.xyaxis",
                    text: "",
                    severity: .primary,
                    isWarning: false,
                ),
            ]
        }
        return [
            Self.row(
                id: "soonest",
                provider: soonest.provider,
                window: soonest.window,
                monitor: monitor,
                format: format,
            ),
        ]
    }

    /// One row per provider that's actually present, each showing its own soonest limit.
    @MainActor
    private static func perProvider(from monitor: UsageMonitor, format: MenuBarFormat) -> [MenuBarRow] {
        let rows = monitor.visibleProviders.compactMap { provider -> MenuBarRow? in
            guard let window = monitor.soonestLimit(for: provider) else { return nil }
            return Self.row(
                id: provider.rawValue,
                provider: provider,
                window: window,
                monitor: monitor,
                format: format,
            )
        }
        // A machine with only one provider signed in gets a single line rather than a lopsided pair.
        return rows.isEmpty ? Self.single(from: monitor, format: format) : rows
    }

    @MainActor
    private static func row(
        id: String,
        provider: Provider,
        window: QuotaWindow,
        monitor: UsageMonitor,
        format: MenuBarFormat,
    ) -> MenuBarRow {
        let paceWarning = Self.paceWindow(for: provider, in: monitor)
            .map { window in
                let samples = monitor.store.series(for: provider, window: window)
                return BurnAnalysis(window: window, samples: samples).willRunOutBeforeReset
            } ?? false
        return MenuBarRow(
            id: id,
            symbol: provider.symbolName,
            text: format.text(for: window, asOf: .now),
            severity: paceWarning && window.remainingPercent >= QuotaWindow.criticalThreshold
                ? .orange
                : window.severityColor,
            isWarning: window.isLow || paceWarning,
        )
    }

    /// Pace warnings follow the shortest period the provider exposes: five-hour, then seven-day.
    @MainActor
    private static func paceWindow(for provider: Provider, in monitor: UsageMonitor) -> QuotaWindow? {
        let snapshot = monitor.state(for: provider).snapshot
        return snapshot?.window(.session) ?? snapshot?.window(.weekly)
    }
}

// MARK: - DrawnRow

/// A row with its color already decided.
private struct DrawnRow: Identifiable {
    let id: String
    let symbol: String
    let text: String
    let color: Color
}

// MARK: - MenuBarContent

/// The drawn label, sized to fit the menu bar exactly.
private struct MenuBarContent: View {
    let rows: [DrawnRow]
    let height: CGFloat

    private var isStacked: Bool { self.rows.count > 1 }

    /// Two lines have to share the height a single line gets all to itself.
    private var fontSize: CGFloat { self.isStacked ? 9 : 12 }

    /// A grid rather than stacked `HStack`s so the two columns line up independently.
    ///
    /// Rows carry different providers and different remaining times, so their text is never the
    /// same width. Left-aligning the whole row leaves the right edges ragged; right-aligning it
    /// would just move the raggedness to the icons. Giving each column its own alignment pins the
    /// icons to the left and the text to the right, so both edges are flush.
    var body: some View {
        Grid(horizontalSpacing: 2.5, verticalSpacing: self.isStacked ? 1 : 0) {
            ForEach(self.rows) { row in
                GridRow {
                    Image(systemName: row.symbol)
                        .font(.system(size: self.fontSize - 1, weight: .semibold))
                        .foregroundStyle(row.color)
                    if !row.text.isEmpty {
                        Text(row.text)
                            .font(.system(size: self.fontSize, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(row.color)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .frame(height: self.height, alignment: .center)
        .fixedSize()
    }
}

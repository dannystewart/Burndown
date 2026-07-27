//
//  MenuBarLabel.swift
//  Burndown
//

import AppKit
import SwiftUI

/// What sits in the menu bar.
///
/// The label is rendered to an `NSImage` rather than handed to SwiftUI as a live view. A menu bar
/// item gives its label a fixed height and no say in it, so a stacked layout laid out by SwiftUI
/// gets clipped or squashed depending on the display. Rendering it ourselves means we choose the
/// exact pixel height, and it gives us the one lever color needs: a template image takes on the
/// menu bar's own color, a non-template one keeps what we drew.
struct MenuBarLabel: View {
    let monitor: UsageMonitor
    let preferences: Preferences

    /// Comfortably inside the menu bar's usable height on every display scale.
    private static let singleLineHeight: CGFloat = 15
    private static let stackedHeight: CGFloat = 20

    var body: some View {
        if let image = self.rendered {
            Image(nsImage: image)
        } else {
            // Rendering can't fail in practice, but the menu bar item must never vanish.
            Image(systemName: "chart.line.downtrend.xyaxis")
        }
    }

    private var rows: [MenuBarRow] {
        switch self.preferences.menuBarLayout {
            case .single: MenuBarRow.single(from: self.monitor)
            case .stacked: MenuBarRow.perProvider(from: self.monitor)
        }
    }

    private var rendered: NSImage? {
        let colored = self.preferences.menuBarUsesColor
        let rows = self.rows
        let height = self.preferences.menuBarLayout == .stacked && rows.count > 1
            ? Self.stackedHeight
            : Self.singleLineHeight

        return Self.render(
            MenuBarContent(rows: rows, colored: colored, height: height),
            asTemplate: !colored,
        )
    }

    /// Rasterises the label at the screen's own scale so it stays crisp on Retina and non-Retina.
    private static func render(_ content: some View, asTemplate: Bool) -> NSImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        // A template image is used purely as a mask, which is exactly what makes it follow the menu
        // bar through light, dark, and tinted appearances.
        image.isTemplate = asTemplate
        return image
    }
}

/// One line of the menu bar label.
nonisolated struct MenuBarRow: Identifiable, Sendable {
    let id: String
    let symbol: String
    let text: String
    /// The color to use when color is switched on; ignored entirely in template mode.
    let color: Color

    /// The tightest window across everything visible, which is the number that would bite first.
    @MainActor
    static func single(from monitor: UsageMonitor) -> [MenuBarRow] {
        guard let tightest = monitor.tightestWindow else {
            return [MenuBarRow(id: "empty", symbol: "chart.line.downtrend.xyaxis", text: "", color: .primary)]
        }
        return [
            MenuBarRow(
                id: "tightest",
                symbol: "chart.line.downtrend.xyaxis",
                text: Format.percent(tightest.window.remainingPercent),
                color: tightest.window.severityColor,
            ),
        ]
    }

    /// One row per provider that's actually present, each showing its own tightest window.
    @MainActor
    static func perProvider(from monitor: UsageMonitor) -> [MenuBarRow] {
        let rows = monitor.visibleProviders.compactMap { provider -> MenuBarRow? in
            guard let window = monitor.tightestWindow(for: provider) else { return nil }
            return MenuBarRow(
                id: provider.rawValue,
                symbol: provider.symbolName,
                text: Format.percent(window.remainingPercent),
                color: window.severityColor,
            )
        }
        return rows.isEmpty ? Self.single(from: monitor) : rows
    }
}

/// The drawn label, sized to fit the menu bar exactly.
private struct MenuBarContent: View {
    let rows: [MenuBarRow]
    let colored: Bool
    let height: CGFloat

    private var isStacked: Bool { self.rows.count > 1 }

    /// Two lines have to share the height a single line gets all to itself.
    private var fontSize: CGFloat { self.isStacked ? 9 : 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: self.isStacked ? 1 : 0) {
            ForEach(self.rows) { row in
                HStack(spacing: 2.5) {
                    Image(systemName: row.symbol)
                        .font(.system(size: self.fontSize - 1, weight: .semibold))
                    if !row.text.isEmpty {
                        Text(row.text)
                            .font(.system(size: self.fontSize, weight: .medium))
                            .monospacedDigit()
                    }
                }
                // In template mode only the alpha survives, so a flat opaque fill is what's wanted;
                // in color mode this is where severity actually shows up.
                .foregroundStyle(self.colored ? row.color : .black)
            }
        }
        .frame(height: self.height, alignment: .center)
        .fixedSize()
    }
}

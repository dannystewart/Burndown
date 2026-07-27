//
//  MenuBarLabel.swift
//  Burndown
//

import SwiftUI

/// What sits in the menu bar: the window closest to running out.
struct MenuBarLabel: View {
    let monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "chart.line.downtrend.xyaxis")
            if let tightest = self.monitor.tightestWindow {
                Text(Format.percent(tightest.window.remainingPercent))
                    .monospacedDigit()
            }
        }
    }
}

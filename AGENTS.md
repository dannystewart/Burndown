# Burndown Agent Guide

## Project Overview

Burndown is a macOS menu bar app that tracks Claude, Codex, Cursor, and OpenCode Go subscription quota windows. It is a Swift 6 and SwiftUI project requiring macOS 27 and Xcode 27.

The providers expose only their current quota state. Burndown creates its own history by polling, persisting samples, and using those observations for charts and forecasts.

## Repository Map

- `Burndown/App/`: app entry point and shared preferences.
- `Burndown/Credentials/`: read-only access to credentials already stored by Claude Code, Codex, Cursor (its `state.vscdb`), and OpenCode.
- `Burndown/Model/`: provider, snapshot, quota-window, and error value types.
- `Burndown/Services/`: provider clients, polling, caching, and sample persistence.
- `Burndown/Analytics/`: burn-rate and exhaustion forecasting.
- `Burndown/Views/`: menu bar, popover, charts, cards, settings, and formatting.
- `BurndownTests/`: focused behavioral and regression tests.
- `README.md`: user-facing product, privacy, and credential documentation.

## Architecture and Invariants

- `UsageRecorder` owns provider polling and persistence inside the launchd-managed agent process. `UsageMonitor` only mirrors that state into the menu bar app over XPC; it never polls or writes, so closing the UI has no effect on history collection. Provider clients and model value types remain nonisolated and sendable where possible.
- Provider clients are dispatched through `UsageProviderRegistry`, not a switch. Adding a provider is a `Provider` case plus a registry entry; leave the poll loop alone.
- Provider APIs report snapshots, not history. Do not imply that historical data can be recovered when Burndown was not running.
- `SampleStore` records changed readings and periodic keyframes, retains eight days, and separates periods by reset time. Reset timestamps may jitter; comparisons intentionally tolerate 120 seconds.
- Quota window kind comes from actual duration. Do not assume Codex's primary and secondary response positions correspond to five-hour and weekly windows.
- Forecasts use consumption observed after the first real reading in a period. The first request may create a rolling window and consume quota simultaneously, so extrapolating that opening charge from the window start produces false exhaustion warnings. Synthetic zero reset anchors are chart history, not evidence of an observed burn rate. Early weekly observations are adjusted from an eight-hour active day toward the measured wall-clock rate as their span approaches 24 hours. High sub-day rates are also regularized toward an even seven-day pace until enough evidence accumulates, so a short coding burst is not treated as a workload that repeats all week.
- Credentials are read from the stores used by the provider CLIs. Never write, refresh, rotate, persist, or log access tokens. Burndown stores quota percentages and timestamps only.
- Transient provider failures may continue showing a recent snapshot. Credential failures are surfaced immediately. Preserve that distinction when changing refresh behavior.
- Keep user-facing behavior consistent between the popover, warning color, and menu-bar limit selection by routing all pace decisions through `BurnAnalysis`.

## Implementation Style

- Keep provider-specific response decoding inside its usage client and normalize into shared model types before data reaches the monitor or UI.
- Explain non-obvious provider behavior, persistence rules, and forecasting assumptions with concise comments. Do not comment straightforward code.
- Update `README.md` when user-facing setup, privacy, credential, storage, or platform requirements change. Update this file when architecture, verification, or agent workflow changes.

The forecast regression tests exist to prevent an opening request from being mistaken for sustained consumption while ensuring later observed consumption can still produce an exhaustion warning. Keep those behavioral contracts; do not pin the tests to a particular rate formula or UI presentation.

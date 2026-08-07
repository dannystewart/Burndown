# Burndown Agent Guide

## Project Overview

Burndown is a macOS menu bar app that tracks Claude and Codex subscription quota windows. It is a
Swift 6 and SwiftUI project requiring macOS 27 and Xcode 27.

The providers expose only their current quota state. Burndown creates its own history by polling,
persisting samples, and using those observations for charts and forecasts.

## Repository Map

- `Burndown/App/`: app entry point and shared preferences.
- `Burndown/Credentials/`: read-only access to credentials already stored by Claude Code and Codex.
- `Burndown/Model/`: provider, snapshot, quota-window, and error value types.
- `Burndown/Services/`: provider clients, polling, caching, and sample persistence.
- `Burndown/Analytics/`: burn-rate and exhaustion forecasting.
- `Burndown/Views/`: menu bar, popover, charts, cards, settings, and formatting.
- `BurndownTests/`: focused behavioral and regression tests.
- `README.md`: user-facing product, privacy, and credential documentation.

## Build And Test

Build without requiring local signing:

```sh
xcodebuild -project Burndown.xcodeproj -scheme Burndown -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Run tests:

```sh
xcodebuild test -project Burndown.xcodeproj -scheme Burndown -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Treat warnings as failures. Before finishing, also run `git diff --check` and validate project-file
edits with `plutil -lint Burndown.xcodeproj/project.pbxproj`.

## Architecture And Invariants

- `UsageMonitor` owns provider state and polling on the main actor. Provider clients and model value
  types remain nonisolated and sendable where possible.
- Provider APIs report snapshots, not history. Do not imply that historical data can be recovered
  when Burndown was not running.
- `SampleStore` records changed readings and periodic keyframes, retains eight days, and separates
  periods by reset time. Reset timestamps may jitter; comparisons intentionally tolerate 120 seconds.
- Quota window kind comes from actual duration. Do not assume Codex's primary and secondary response
  positions correspond to five-hour and weekly windows.
- Forecasts use consumption observed after the first real reading in a period. The first request may
  create a rolling window and consume quota simultaneously, so extrapolating that opening charge
  from the window start produces false exhaustion warnings. Synthetic zero reset anchors are chart
  history, not evidence of an observed burn rate.
- Credentials are read from the stores used by the provider CLIs. Never write, refresh, rotate,
  persist, or log access tokens. Burndown stores quota percentages and timestamps only.
- Transient provider failures may continue showing a recent snapshot. Credential failures are
  surfaced immediately. Preserve that distinction when changing refresh behavior.
- Keep user-facing behavior consistent between the popover, warning color, and menu-bar limit
  selection by routing all pace decisions through `BurnAnalysis`.

## Implementation Style

- Prefer the smallest correct change and preserve established SwiftUI and concurrency patterns.
- Keep provider-specific response decoding inside its usage client and normalize into shared model
  types before data reaches the monitor or UI.
- Explain non-obvious provider behavior, persistence rules, and forecasting assumptions with concise
  comments. Do not comment straightforward code.
- Update `README.md` when user-facing setup, privacy, credential, storage, or platform requirements
  change. Update this file when architecture, verification, or agent workflow changes.

## Testing Guidelines

- Tests should protect durable behavior without obstructing routine UI iteration. Good
  opportunities include user interactions, state transitions, data integrity, and documented
  regressions that cannot be verified directly from the implementation.
- Do not test pixel dimensions, layout formulas, spacing, visual ordering, animation timing,
  display copy, button or menu labels, or presentation thresholds. Do not duplicate constants or
  straightforward implementation logic in assertions.
- Do not create a test merely because production code changed or an adjacent type already has
  tests. State the meaningful failure it prevents before writing it. Prefer deleting a low-value
  test over maintaining or weakening it when implementation changes expose that it never protected
  a durable contract.

The forecast regression tests exist to prevent an opening request from being mistaken for sustained
consumption while ensuring later observed consumption can still produce an exhaustion warning. Keep
those behavioral contracts; do not pin the tests to a particular rate formula or UI presentation.

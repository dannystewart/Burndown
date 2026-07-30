# Burndown

A macOS menu bar app that tracks how much of your Claude and Codex subscription quota you have left.

Both providers expose your current usage but no history, so Burndown polls every few minutes, records what it sees, and draws the burndown chart neither provider gives you: how fast you're going through a window, and whether you're on pace to run out before it resets.

This is a personal project, not supported but shared (unlicensed) in case it's useful. Requires macOS 27, Xcode 27, and Swift 6.

## What It Shows

- **Menu bar:** used or remaining percentage for whichever window is closest to running out, or one row per provider. Configurable to show time remaining, reset time, or a combination, with color that either stays on, appears only when a window gets low, or stays off entirely.
- **Popover:** both providers' 5-hour and 7-day windows, burn rate, projected exhaustion, and a chart of the current window built from recorded history.

## Credentials and Privacy

Burndown reads the credentials the CLIs already store on your machine:

- **Claude:** the `Claude Code-credentials` entry in your login Keychain
- **Codex:** `~/.codex/auth.json`

It only ever reads them. It never writes, refreshes, or rotates either credential — both providers rotate refresh tokens, so refreshing from a second process would invalidate the CLI's own session. If a token expires, Burndown says so and you re-authenticate with the CLI as usual.

The access tokens go to the providers' own usage endpoints and nowhere else. There is no server, no telemetry, no analytics. What's stored locally, in `~/Library/Application Support/Burndown/`, is quota percentages and timestamps — never credentials:

- `samples.json` — usage history for the charts, kept for 8 days
- `snapshots.json` — the last reading from each provider, so a cold start has something to show

The app is not sandboxed, because reading `~/.codex/auth.json` and another app's Keychain item is exactly what the sandbox exists to prevent. If that trade isn't one you want to make, the code is here to read — `Burndown/Credentials/` is about 80 lines and is the whole of the credential handling.

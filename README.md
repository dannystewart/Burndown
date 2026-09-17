# Burndown

A macOS menu bar app that tracks how much of your Claude, Codex, Cursor, and OpenCode Go subscription quota you have left.

Every provider exposes your current usage but no history, so Burndown polls every few minutes, records what it sees, and draws the burndown chart none of them give you: how fast you're going through a window, and whether you're on pace to run out before it resets.

This is a personal project, not supported but shared (unlicensed) in case it's useful. Requires macOS 27, Xcode 27, and Swift 6.

## What It Shows

- **Menu bar:** used or remaining percentage for whichever window is closest to running out, or one row per provider. Configurable to show time remaining, reset time, or a combination, with color that either stays on, appears only when a window gets low, or stays off entirely.
- **Popover:** every provider's windows — five-hour, weekly, and monthly, depending on which a provider reports. The window closest to running out gets a full card with burn rate and projected exhaustion, and a chart of the current window built from recorded history. The provider's other windows get one line each: how much is left and when it comes back.

Charts are drawn for five-hour windows only. Across a week or a month the line is close to flat at this size, and the bar and the projection say the same thing in less space.

## Credentials and Privacy

Burndown reads the credentials the provider apps and CLIs already store on your machine:

- **Claude:** the `Claude Code-credentials` entry in your login Keychain, read through macOS's
  Apple-signed `security` tool so Claude's token rotations do not cause recurring permission prompts
- **Codex:** `~/.codex/auth.json`
- **Cursor:** the `cursorAuth/accessToken` row of Cursor's own state database, at
  `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`, read with `sqlite3`. Cursor
  ships no CLI, so this is where its session lives; the same read picks up the plan name
- **OpenCode Go:** the `opencode-go` key in `~/.local/share/opencode/auth.json`

A provider you haven't signed into is left out of the popover entirely rather than shown as an error, with a line in the footer noting its absence, so the window only lists what you actually use.

It only ever reads them. It never writes, refreshes, or rotates any credential. Claude and Codex both rotate refresh tokens, so refreshing from a second process would invalidate the CLI's own session — and Burndown applies that rule to every provider rather than owning the credential lifecycle for some and not others. If a token expires, Burndown says so and you re-authenticate with that provider as usual.

The access tokens go to the providers' own usage endpoints and nowhere else. There is no server, no telemetry, no analytics. What's stored locally, in `~/Library/Application Support/Burndown/`, is quota percentages and timestamps — never credentials:

- `usage-state.json` — the last reading from each provider, so a cold start has something to show, together with the usage history behind the charts, kept for 8 days

Versions before the recorder became a separate process split this across `snapshots.json` and `samples.json`. Both are still read once and migrated if they're present.

The app is not sandboxed, because reading `~/.codex/auth.json`, another app's Keychain item, and Cursor's state database is exactly what the sandbox exists to prevent. If that trade isn't one you want to make, the code is here to read — `Burndown/Credentials/` is about 350 lines and is the whole of the credential handling.

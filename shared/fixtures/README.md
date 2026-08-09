# Shared provider fixtures

Representative provider output used by the **Windows** test suite
(`windows/tests/**`). Several inputs are transcriptions of the examples already
asserted in the macOS Swift tests, so both ports are checked against the same
provider behavior.

The provider-output files under `codex/` and `claude/` were introduced for the
Windows port; the macOS build does not consume those files. The public contract
snapshots under `contract/v1/` are shared by the macOS AR-011 tests and are the
future Windows parity inputs.

Nothing here contains real account data — no tokens, no credentials, no user
paths. The percentages and reset times are illustrative.

```text
codex/    newline-delimited JSON-RPC lines from `codex app-server --stdio`
claude/   plain-text output of Claude Code's print-mode usage query
contract/ synthetic, provider-neutral public telemetry contract snapshots
```

| Fixture | Covers |
| --- | --- |
| `codex/five-hour-and-weekly.jsonl` | both windows, fractional percent rounding |
| `codex/weekly-only.jsonl` | account exposing only a weekly window |
| `codex/additional-duration-window.jsonl` | a non-standard duration window (3 days) |
| `codex/missing-fields.jsonl` | windows missing `usedPercent` / duration |
| `codex/missing-rate-limits.jsonl` | response without `rateLimits` |
| `codex/error-response.jsonl` | JSON-RPC error for the usage request |
| `codex/interleaved-protocol-messages.jsonl` | other ids and notifications around the answer |
| `codex/malformed.jsonl` | truncated and non-JSON lines |
| `codex/incompatible-flag-stderr.txt` | stderr of a CLI that rejects the safe-disable flags |
| `claude/print-usage-both-windows.txt` | session + weekly with reset times |
| `claude/print-usage-fractional-and-partial.txt` | `8.6%` rounding, weekly without a reset |
| `claude/print-usage-weekly-only.txt` | weekly fallback when no session window exists |
| `claude/print-usage-not-logged-in.txt` | signed-out verdict |
| `claude/print-usage-unreadable.txt` | unreadable verdict |
| `claude/print-usage-truncated.txt` | partially written output (weekly line incomplete) |
| `claude/screen-usage-panel.txt` | legacy interactive-panel shape, kept as a parser check |

## Public telemetry contract fixtures

The `contract/v1/` snapshots freeze the transport-independent v1 JSON shape for
future cross-platform projection and serialization parity. They contain only
synthetic timestamps, percentages, states, and allowlisted error codes.

| Fixture | Covers |
| --- | --- |
| `contract/v1/fresh-multiple-windows.json` | both providers fresh; all window kinds; multiple raw windows; nullable reset and duration |
| `contract/v1/stale-and-disabled.json` | stale retained windows with a safe error; disabled provider |
| `contract/v1/unavailable.json` | connected providers with no successful telemetry and safe errors |

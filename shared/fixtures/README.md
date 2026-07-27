# Shared provider fixtures

Representative provider output used by the **Windows** test suite
(`windows/tests/**`). Several inputs are transcriptions of the examples already
asserted in the macOS Swift tests, so both ports are checked against the same
provider behavior.

These files are new. The macOS build does not reference them: `Package.swift`,
the Swift sources and `tests/UsageBarCoreTests` are untouched by the Windows
port.

Nothing here contains real account data — no tokens, no credentials, no user
paths. The percentages and reset times are illustrative.

```text
codex/    newline-delimited JSON-RPC lines from `codex app-server --stdio`
claude/   plain-text output of Claude Code's print-mode usage query
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

# Changelog

All notable changes to UsageBar are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases before v1.5.2 are listed on the
[Releases](https://github.com/akwnnwastaken/UsageBar/releases) page.

## [Unreleased]

### Fixed
- Codex quota checks no longer crash (SIGABRT / exit 134) when a fetch is
  stopped: the process is now reaped before its termination status is read.
- A Codex fetch that hits its deadline is reported as `codex_timed_out` instead
  of `codex_command_failed` (the non-zero status came from UsageBar's own signal).
- Claude reset countdowns roll forward in the reset's own time zone, fixing
  off-by-one-day/hour errors when the Mac's time zone differs or the roll crosses
  a daylight-saving boundary.

## [1.6.0] - 2026-07-24

### Changed
- Claude usage is now read with `claude -p "/usage"` (plain-text print mode)
  instead of scraping the interactive `/usage` TUI. The reader no longer registers
  a session in Claude's history ("Recents"), consumes no model quota, and drops
  all of the terminal-scrape fragility (Enter/CR handling, the "login" banner
  false-positive, cursor-move space-collapse, and the pty height requirement).

### Added
- Selectable refresh interval (1, 2, or 5 minutes; default 5) in the menu.
- The menu refreshes when reopened with data older than 30 seconds (was 60).
- `--diagnose-claude-live` reports which windows carried a parsed reset time
  (`five-hour+reset,weekly+reset`), so a reset-parsing regression is visible.

### Fixed
- The menu-bar / menu percentage no longer flickers upward from an integer
  rounding boundary (e.g. 41 ↔ 42): a one-point rise is withheld until it
  persists across three readings. The recorded history stays raw.

### Removed
- The pty `/usage` scrape, the native `forkpty` launcher, and the `rate_limits`
  status-line reader (which never populated for an idle reader session).

## [1.5.3] - 2026-07-23

### Fixed
- Raised the reader's pseudo-terminal to 60 rows so the full `/usage` panel
  renders and the **weekly** "Resets" line is captured (at 24 rows it fell below
  the fold and the weekly reset was intermittent).

## [1.5.2] - 2026-07-23

### Fixed
- Submit `/usage` with a carriage return (`\r`); Claude Code 2.1.x no longer
  treats LF as Enter once its TUI is in raw mode.
- Do not treat the startup banner's "login" changelog text as a not-logged-in
  verdict; the state is decided only after the `/usage` attempts.
- Parse whole-hour reset times ("Resets 5pm", "Resets Jul 26 at 10pm") and
  re-insert separators lost to the panel's cursor-move spacing.

[Unreleased]: https://github.com/akwnnwastaken/UsageBar/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/akwnnwastaken/UsageBar/compare/v1.5.3...v1.6.0
[1.5.3]: https://github.com/akwnnwastaken/UsageBar/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.5.2

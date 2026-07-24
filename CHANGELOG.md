# Changelog

All notable changes to UsageBar are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases before v1.5.2 are listed on the
[Releases](https://github.com/akwnnwastaken/UsageBar/releases) page.

## [Unreleased]

## [1.9.0] - 2026-07-24

### Added
- App icon (`UsageBar.icns`), shown in Finder, Get Info, and app lists.

### Changed
- The 24-hour history chart now restarts at each reset: it is drawn from the
  most recent reset onward (a large upward jump back toward ~100%), so each quota
  period is a distinct arc instead of one continuous line with reset markers.
  Once Claude's five-hour window resets, the chart starts over from ~100%. The
  label, start/end values, and net change describe the current window; recorded
  history stays full and raw.

## [1.8.0] - 2026-07-24

### Added
- The menu shows a disabled version row (`Version X.Y.Z (build N)`) above Quit,
  so the running version is visible without opening Finder → Get Info.

### Changed
- The menu-bar value now withholds any remaining-percentage rise below the reset
  threshold until it persists across several readings, not just exact +1 rounding
  jumps. This hides the Claude "stale server snapshot" rebound (e.g. remaining
  33% then 38%) that occurs when a freshly spawned reader gets a cached usage
  snapshot lagging the live value. Resets (a large jump back toward ~100%) still
  display immediately, and recorded history stays raw.

## [1.7.0] - 2026-07-24

### Added
- Provider disconnect: each connected provider has a "Disconnect" menu item.
  Disconnecting drops that provider's live usage and status selection, turns off
  auto-rotate when fewer than two providers remain, and keeps the usage history
  (use "Clear history" to remove it).

### Fixed
- Codex quota checks no longer crash (SIGABRT / exit 134) when a fetch is
  stopped: the process is now reaped before its termination status is read.
- A Codex fetch that hits its deadline is reported as `codex_timed_out` instead
  of `codex_command_failed` (the non-zero status came from UsageBar's own signal).
- Claude reset countdowns roll forward in the reset's own time zone, fixing
  off-by-one-day/hour errors when the Mac's time zone differs or the roll crosses
  a daylight-saving boundary.

### Internal
- Extracted the usage models, history models, summary selection, and the whole
  `UsageParser` into `UsageBarCore` (behavior-preserving); the XCTest suite grew
  from 15 to 27 cases. Added a pinned `macos-14` CI job, an explicit `swift test`
  step, and workflow timeouts.

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

[Unreleased]: https://github.com/akwnnwastaken/UsageBar/compare/v1.9.0...HEAD
[1.9.0]: https://github.com/akwnnwastaken/UsageBar/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/akwnnwastaken/UsageBar/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/akwnnwastaken/UsageBar/compare/v1.6.0...v1.7.0
[1.6.0]: https://github.com/akwnnwastaken/UsageBar/compare/v1.5.3...v1.6.0
[1.5.3]: https://github.com/akwnnwastaken/UsageBar/compare/v1.5.2...v1.5.3
[1.5.2]: https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.5.2

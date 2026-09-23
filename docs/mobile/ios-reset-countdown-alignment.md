# Reset countdowns across the mobile surfaces

A small presentation checkpoint after Phase 8. **Not Phase 9.**

Phase 7 put a reset countdown on the Control Center controls and deliberately
left the app dashboard and the Home/Lock Screen widgets for a separate change,
so that a Control Center checkpoint stayed reviewable as one. This is that
follow-up, and it also fixes a correctness bug found while doing it.

Nothing about the schema, the transport, pairing, authentication, the caches or
the desktop changed. **Production integration remains unauthorized.**

---

## The bug this found

Control Center resolved the headline window properly — by looking up
`headlineWindowId` in the measurement's own `windows`. The provider Home Screen
widget did not:

```swift
if let measurement = value?.measurement,
   let primary = measurement.windows.first {          // ← wrong window
    Text(WindowPresentation.label(for: primary))
```

The first listed window is not the headline. Codex's headline is its **most
constrained** window, which can legitimately be a multi-day `duration` limit
listed after the weekly one. The widget would then print "Weekly" beside a
three-day number — and once this checkpoint added countdowns, it would also have
counted down to the wrong reset, confidently, on a Lock Screen.

That is why the physical proof below uses a synthetic snapshot whose Codex
headline is a 3-day window in **second** position: it is the only shape that
makes the bug visible. With an ordinary five-hour headline listed first, a
broken `windows.first` lookup accidentally produces the right answer and proves
nothing.

## One resolver

`HeadlinePresentation`, in `Shared/ProviderPresentation.swift`, is now the only
place any mobile surface answers "which window is the headline":

```swift
HeadlinePresentation.window(in: measurement)        // headlineWindowId lookup
HeadlinePresentation.label(in: measurement)         // "5 Hour", "Weekly · Opus"
HeadlinePresentation.compactLabel(in: measurement)  // "5H", "Weekly", "3D"
HeadlinePresentation.resetsAt(in: measurement)
HeadlinePresentation.compactReset(in: measurement, now:)   // "2h left"
```

It returns nil when the snapshot does not contain the named window. It never
falls back to a guess: a missing headline window means the label and countdown
are simply not shown, while the percentage — the desktop's own answer either
way — still is.

The dashboard, the widgets and Control Center all call it. Control Center's
private copy was deleted in favour of it, and its rendered output is unchanged.
A test asserts that exactly one file performs the lookup.

## One countdown formatter

`FreshnessPresentation.compactTimeRemaining(until:from:)`, unchanged from Phase
7. Floors rather than rounds, because overstating the time left is the harmful
direction — someone plans around a window that closes sooner than the screen
implied.

| Remaining | Shown |
| --- | --- |
| 30 s | `1m left` |
| 59 min | `59m left` |
| 1 h 59 m | `1h left` |
| 2 h 59 m | `2h left` |
| 47 h | `1d left` |
| 72 h | `3d left` |
| already passed | *nothing* |
| no reset time | *nothing* |

An expired countdown is not information, so it is omitted rather than rendered
as `0m left` or a negative number.

## Countdown is not freshness

These are two different facts and both matter:

- **freshness** comes only from the provider's `measuredAt` — never the
  snapshot's `generatedAt`
- **countdown** comes only from the **headline window's** `resetsAt`

A desktop asleep for two days can still hold a reading whose five-hour window
resets in an hour. The phone must say both, and a future reset must never make
an old measurement look fresh. On surfaces with room, the age is printed first
for exactly that reason.

## What each surface shows

### App dashboard

```
64% remaining
Updated 4 min ago · 1h left        ← age first, then the headline's countdown

5 Hour
Resets 3:45 PM                64%  ← detail rows keep the absolute instant
Weekly
Resets 12 Mar 2026 09:00      87%
```

The headline answers "should I slow down?"; the detail rows answer "when
exactly?". Printing the same fact twice in two formats would make the card
longer without making it clearer, so the rows were left alone.

The card is wrapped in `TimelineView(.periodic(by: 60))` so the countdown stays
honest while the dashboard is open. That tick is **presentation only** — it
re-evaluates the view with a newer `now` and does nothing else. No fetch, no
cache write, no widget reload, and `measuredAt` is untouched: a reading does not
get younger because the clock moved. A test asserts the view reaches no
networking, storage or reload API.

### Home Screen

| Widget | Shows |
| --- | --- |
| Provider, `systemSmall` | name · `64%` · **`3 Day · 1h left`** · `Updated 4 min ago` |
| Overview, `systemSmall` | one row per provider: `Codex   64% · 1h left` |
| Overview, `systemMedium` | per provider: headline `%`, then **`5 Hour · 2h left`**, then the detail window rows, then the age |

The window line names the *headline* window. Detail rows keep their own
percentages and are deliberately left uncluttered — the requirement was that the
headline's reset be visible, not every window's.

Where a row has to give something up, the percentage outranks the countdown:
the headline value carries `layoutPriority(1)` and the countdown is what
truncation costs.

### Lock Screen

| Family | Shows | Why |
| --- | --- | --- |
| `accessoryRectangular`, provider | `Claude` · `52%` · `2h left · 59m ago` | one cramped line for two facts, so **both** are shortened rather than one dropped |
| `accessoryRectangular`, overview | one line per provider: `Codex 64% · 1h left` | restructured from two side-by-side columns to two rows, because a column had no room for a third line |
| `accessoryInline` | `Codex 64% · 1h left` | percentage first, so truncation costs the countdown |
| `accessoryCircular` | initial · `64%` | **intentional exception** — no countdown; the family is too small to add one without crowding out the number |

The short age form (`just now`, `3m ago`, `2h ago`, `1d ago`) exists only
because that one line is genuinely tight. It still derives from `measuredAt`,
it is deterministic, it has its own tests, and it introduces **no stale
threshold** — it states an age and draws no conclusion from it.

### Control Center

Unchanged. Same stable kinds, symbols, `OpenIntent`, wording and behaviour; only
the internal resolver moved. Its existing tests still pass.

## Paused and cached states

A retained measurement can still carry a future reset, so neither state
suppresses the countdown:

- **Paused** — the reading is retained and its window keeps running. The
  countdown shows, the lifecycle status still says `Paused`, and the age still
  reveals how old the reading is.
- **Cached / offline** — a cached snapshot is a *validated* reading whose window
  is still running. The countdown shows; the stale indicator is what says the
  data is not current.

## Scheduling

No `BackgroundTasks`, no APNs, no silent push, no polling loop, and no shorter
widget refresh interval. WidgetKit's requested floor is unchanged at roughly 15
minutes and the system decides when a timeline actually runs.

**A widget countdown is therefore best-effort between timeline evaluations and
can be stale by minutes.** Only the foreground dashboard ticks. Nothing here
promises a second-by-second countdown anywhere, and nothing should.

## Privacy

Quota values and reset times stay `privacySensitive` on the system surfaces, so
iOS redacts them on a Lock Screen according to the user's own setting. The
presentation helpers accept schema dates and integers and nothing else — no
host, bearer, FQDN, Tailscale identity or provider credential can reach them,
because none is a parameter.

## Physical proof — synthetic data only

**No real Codex or Claude data was used or transmitted.** The Mobile Lab desktop
host was never started for this checkpoint; the existing synthetic transport
probe served a temporary, untracked schema-v1 snapshot from scratch storage,
which the probe validated at startup and which was deleted afterwards.

The fixture's Codex headline was a 3-day `duration` window in **second**
position, specifically to exercise the bug above. Manual host/key entry was used
rather than QR pairing, since the lab host was not running.

| Surface | Result |
| --- | --- |
| Dashboard headline: age **and** countdown | **PASS** |
| Dashboard detail rows keep the absolute reset | **PASS** |
| Codex headline resolved to `3 Day · 1h left`, not `Weekly · 4d left` | **PASS** |
| Home Screen provider `systemSmall` | **PASS** |
| Lock Screen provider `accessoryRectangular` — `2h left · 59m ago` | **PASS** |
| Lock Screen overview `accessoryRectangular` | **PASS** |
| `accessoryInline` | **not separately observed** — none placed on the device; its wording is covered by unit tests, not claimed as physical proof |
| `accessoryCircular` | unchanged by design |

Ages and countdowns were observed advancing in real time consistently with the
fixture's own timestamps, which is itself evidence that both are computed from
the snapshot rather than baked in.

Serve was configured temporarily for this proof and removed; Funnel was never
enabled; no grant, ACL or tag was touched. Production was not started, modified
or reinstalled.

## What did not change

Schema v1, `Package.swift`, `Sources/`, `shared/sync-schema/`, `windows/`,
`.github/`, `mobile-lab/`, `scripts/`, the desktop host, the transport, pairing,
authentication, the Keychain model, the cache model, WidgetKit scheduling,
Control Center kinds, and the App-Group-free architecture.

# UsageBar mobile sync contract — schema v1

Transport-neutral, privacy-minimized data contract shared by a future UsageBar
desktop sender and a future iPhone companion.

| | |
| --- | --- |
| Schema file | `usage-snapshot.schema.json` |
| `schemaVersion` | `1` |
| Dialect | JSON Schema **draft 2020-12** |
| Examples | `examples/minimal.json`, `examples/full.json` |
| Threat model | [`docs/mobile-sync-threat-model.md`](../../docs/mobile-sync-threat-model.md) |

**This is design only.** No sender, no receiver, no network code and no
transport exists. Nothing here selects a backend — see
[Transport Decision — Deferred](../../docs/mobile-sync-threat-model.md#transport-decision--deferred).

---

## 1. What the contract is derived from

Every rule below was read out of the inherited production baseline rather than
assumed. The relevant sources:

| Source | What it established |
| --- | --- |
| `Sources/UsageBarCore/Core.swift` | `UsageWindowKind` (5 categories), `UsageWindow`, `ProviderUsage`, `ProviderIssue`, `UsageSummaryCalculator` headline policy, `weeklyKind(qualifier:)` slug rules |
| `Sources/UsageBarCore/ProviderCollectionPolicy.swift` | connected / collection-enabled as two facts that are never conflated; `collect` / `retainCache` / `dropCache` |
| `Sources/UsageBarCore/ProviderStatusPolicy.swift` | `StatusIdleReason.noProviderConnected` vs `.allCollectionPaused`; paused providers keep their data |
| `Sources/UsageBarCore/ProviderDetailVisibility.swift` | detail visibility is presentation-only and never affects collection — so it is **not** in the contract |
| `Sources/UsageBarCore/UsageHistoryRecorder.swift` | `remainingPercent = 100 - usedPercent`; series keyed `provider|windowKey` |
| `Sources/UsageBar/main.swift` | `lastSuccessfulAt` set only on accepted reads; `.stale(from:)` preserves it; `displayUsages` noise filtering |
| `windows/src/UsageBar.Windows.Core/Providers/UsageWindow.cs`, `ProviderUsage.cs`, `Policies/UsageSummaryCalculator.cs` | Windows parity: identical categories, identical headline rule |

---

## 2. Top-level shape

```
schemaVersion   integer, const 1
generatedAt     RFC 3339 instant
providers       array (0–16) of provider
```

A snapshot with `providers: []` means **no provider is connected**. A snapshot
whose providers all have `collecting: false` means **every connected provider is
paused**. Those two states are distinguishable without any status string,
mirroring `StatusIdleReason`.

## 3. Provider

```
providerId      stable lowercase slug  ("codex", "claude-code")
connected       boolean
collecting      boolean
measurement     object, optional
```

`connected` and `collecting` are **two independent facts**, exactly as
`ProviderCollectionPolicy` models them. A paused provider is
`connected: true, collecting: false` and **keeps its measurement**. Collapsing
these into one flag would erase the readings a pause exists to preserve.

The schema enforces that `connected: false` implies `collecting: false` and no
`measurement`, mirroring the `dropCache` branch that discards a disconnected
provider's readings.

## 4. Measurement

```
measuredAt                 RFC 3339 instant
headlineRemainingPercent   integer 0–100
headlineWindowId           windowId reference
windows                    array (1–16) of window
```

`measurement` is absent when the desktop holds no accepted reading.

## 5. Window

```
windowId          canonical identity string
kind              fiveHour | weekly | weeklyScoped | duration | unknown
scope             required iff kind = weeklyScoped
durationMinutes   required iff kind = duration; conventional otherwise
position          required iff kind = unknown
remainingPercent  integer 0–100
resetsAt          RFC 3339 instant, optional
```

---

## 6. Freshness: `generatedAt` vs `measuredAt`

This is the contract's most important rule, and it exists because the product
already gets it right.

UsageBar keeps **one global** `lastUpdated` per refresh cycle, but sets
`lastSuccessfulAt` **per provider**, and only when that provider's read was
accepted. `ProviderUsage.stale(from:)` preserves the previous
`lastSuccessfulAt`, so a retained reading keeps the time it was actually taken.

A single snapshot timestamp would destroy that distinction:

> Codex refreshes successfully at 14:00. Claude fails at 14:05 and UsageBar
> retains Claude's last good value. A snapshot generated at 14:05 carrying only
> one timestamp would make Claude's 14:00 reading look five minutes old when it
> is really older, and would keep looking fresh no matter how long Claude
> keeps failing.

Therefore:

- **`generatedAt`** — when the *document* was built. Use it for replay and
  transport-level recency. **Never** for per-provider freshness.
- **`measuredAt`** — when *that provider's* reading was taken and accepted.
  Maps directly to `lastSuccessfulAt`. The only correct basis for freshness.

`examples/full.json` encodes exactly this case: `generatedAt` 14:05, Codex
`measuredAt` 14:05, Claude `measuredAt` 14:00.

No staleness threshold appears anywhere in the schema. "Stale after N minutes"
is client presentation policy and belongs to the consumer, not the wire.

---

## 7. Headline value

The desktop remains authoritative. `headlineRemainingPercent` is the value
UsageBar itself presents, already selected. The phone must **not** reimplement
provider parsing or headline selection.

Verified from `UsageSummaryCalculator` (macOS) and `UsageSummaryCalculator.cs`
(Windows), which agree:

| Provider | Selection rule, as implemented |
| --- | --- |
| **Claude Code** | the `fiveHour` window when present, otherwise the **ordinary all-models** `weekly` window. A `weeklyScoped` window is never chosen as the headline. |
| **Codex** (and any non-Claude provider) | the **most constrained** window — the one with the highest used percent, i.e. the lowest remaining — across *all* windows, including `duration` and `unknown` ones. |

Both then compute `remainingPercent = clamp(0…100, 100 − usedPercent)`.

Because Codex's rule scans every window, the headline can legitimately come from
a non-standard window. `examples/full.json` shows this: a 3-day
(`duration-4320`) window at 45% remaining is more constrained than the weekly
window at 87%, so it is the headline.

`headlineWindowId` names which window won, so the phone can label the number
("5-hour", "Weekly", "Weekly · Opus") without re-deriving the policy.

### Filtered, not raw

The transmitted values are the **display** values, after
`UsageDisplayNoiseFilter`. UsageBar deliberately holds back small spurious rises
caused by provider rounding and cached provider snapshots. Sending raw values
would make the phone disagree with the Mac sitting next to it. History keeps raw
values; history is not synced in v1.

---

## 8. Window identity and forward compatibility

`windowId` is the canonical identity, derived exactly as the product's
`UsageWindowKind.historyKey` already derives it:

| Kind | `windowId` | Qualifier field |
| --- | --- | --- |
| `fiveHour` | `five-hour` | — |
| `weekly` | `weekly` | — |
| `weeklyScoped` | `weekly-<scope>` | `scope` |
| `duration` | `duration-<minutes>` | `durationMinutes` |
| `unknown` | `unknown-<position>` | `position` |

Identities are **unique within a provider**. The product already enforces this
when parsing Claude's weekly rows (`!windows.contains(where: { $0.kind == kind })`),
so a duplicate identity is a malformed snapshot.

### Claude all-models weekly vs model-qualified weekly

This is the distinction §8 of the design brief requires, and it is carried
structurally, never by a display label:

- `Current week (all models)` → `kind: "weekly"`, `windowId: "weekly"`
- `Current week (Opus)` → `kind: "weeklyScoped"`, `scope: "opus"`, `windowId: "weekly-opus"`

`scope` is the same normalized slug the desktop already computes in
`weeklyKind(qualifier:)`: lowercased, non-alphanumeric runs collapsed to `-`, a
trailing `only` dropped, capped at 32 characters. It is **never** raw provider
text, so a provider cannot inject arbitrary content into the wire through a
parenthesised label. A qualifier that normalizes to nothing causes the desktop to
skip the row rather than mistake it for the all-models limit.

Localization stays on the phone: `weeklyScopeDisplayName` is desktop
presentation and is not transmitted.

### How an unknown future window is represented

`kind` is a closed set of five values, but two of them are open-ended escape
hatches, which is why a new provider window does **not** require a
`schemaVersion` bump:

- A future window whose **length is known** → `kind: "duration"` with its
  `durationMinutes`. This is what `UsageWindowKind.classified` already does for
  anything outside the 4–6 hour and 6–8 day bands. A real 3-day Codex window
  already exercises this path.
- A future window whose **length is unknown** → `kind: "unknown"` with its
  `position`.

A consumer that does not recognise a window still has `remainingPercent`,
`resetsAt` and a stable `windowId`, so it can display and track it generically.
The same reasoning applies to `providerId`, whose pattern is open: an
unrecognised provider renders generically rather than failing the snapshot.

---

## 9. Field-by-field rationale

Every field was interrogated against the design brief's six questions. Fields
that could not answer them are listed as rejected in §10.

### Top level

| Field | Why the phone needs it | Fact or metadata | Identifying? | Derivable instead? |
| --- | --- | --- | --- | --- |
| `schemaVersion` | Decide whether it can parse the payload at all | metadata | no | no |
| `generatedAt` | Replay/recency of the document; ordering two snapshots | metadata | no | no — transport timestamps are not trustworthy |
| `providers` | The payload | fact | no | no |

### Provider

| Field | Why the phone needs it | Fact or metadata | Identifying? | Derivable instead? |
| --- | --- | --- | --- | --- |
| `providerId` | Label the row; keep widget state stable across refreshes | fact | no — product identity, not account identity | no |
| `connected` | Distinguish "nothing set up" from "paused" | fact | no | no |
| `collecting` | Show a paused provider as paused rather than broken | fact | no | no |
| `measurement` | Absent means genuinely no reading | fact | no | no |

### Measurement

| Field | Why the phone needs it | Fact or metadata | Identifying? | Derivable instead? |
| --- | --- | --- | --- | --- |
| `measuredAt` | The only correct freshness basis (§6) | metadata | no | no |
| `headlineRemainingPercent` | The number on the widget | fact | no | **deliberately not** — recomputing means reimplementing provider policy |
| `headlineWindowId` | Label which window the number refers to | fact | no | only by duplicating the headline policy |
| `windows` | The detail list | fact | no | no |

### Window

| Field | Why the phone needs it | Fact or metadata | Identifying? | Derivable instead? |
| --- | --- | --- | --- | --- |
| `windowId` | Stable key for referencing and for widget state across refreshes | fact | no | yes, from `kind` + qualifier — see the note below |
| `kind` | Localize the window name without parsing a slug | fact | no | no |
| `scope` | Distinguish weekly-Opus from weekly-all-models | fact | no | no |
| `durationMinutes` | Render window length; identity for `duration` | fact | no | no |
| `position` | Only identity an `unknown` window has | fact | no | no |
| `remainingPercent` | The value shown | fact | no | no |
| `resetsAt` | Countdown / reset line | fact | no | no |

**The one accepted redundancy.** `windowId` *is* derivable from `kind` plus its
qualifier. It is carried anyway because it makes three separate things trivial —
referencing the headline window, checking identity uniqueness, and aligning with
the `provider|windowKey` series keys a future history feature would use — and
because it is already the product's own identity string, so nothing new is
invented. Consumers must reject a snapshot whose `windowId` disagrees with its
`kind`/qualifier; this is the price of the redundancy and is stated explicitly
rather than left implicit.

## 10. Fields deliberately rejected

| Rejected | Why |
| --- | --- |
| `usedPercent` | Exactly `100 - remainingPercent`. A second source of truth for one number. |
| Provider display name (`"Claude Code"`) | `providerId` is stable; the display name is a product label the phone can map itself. |
| Localized window labels (`"Haftalık"`, `"5 hours remaining"`) | Presentation. The phone localizes from `kind` + qualifier. |
| `lastUpdated` / global refresh time | Would reintroduce exactly the freshness bug §6 exists to prevent. |
| Staleness threshold, warning/critical thresholds | Client presentation policy, not wire data. Alert presets are a desktop preference. |
| `isStale` boolean | Derivable from `measuredAt` plus the consumer's own policy; baking it in would freeze a threshold into the wire. |
| Detail-visibility state | Desktop presentation preference; explicitly never affects collection. |
| `sourceInstanceID` / device identity | Not needed by a single-desktop v1. Multi-device source selection is deferred; see §12. |
| Computer or host name | Personal metadata with no widget purpose. Prohibited outright. |
| Usage history samples | Out of scope for v1 — see §11. |
| Issue / error codes | Deferred — see §13. |

---

## 11. No history in v1

Schema v1 carries **no** usage history. The immediate goal is current usage on
widgets and controls, and history would enlarge the payload, widen the privacy
surface, and introduce persistence, retention and conflict semantics that no
transport has been chosen to support yet.

The desktop's own 24-hour history is untouched and stays local. A future schema
revision may add history separately **only** if explicitly authorized.

---

## 12. Prohibited data

The following must **never** appear in a snapshot, at any nesting level. This
list is normative.

**Credentials and secrets** — `accessToken`, `refreshToken`, `apiKey`, `token`,
`cookie`, `sessionId`, `authorization`, any pairing or transport secret.

**Raw provider material** — `rawOutput`, raw Codex JSON responses, raw Claude
screen or `--print` text, `stdout`, `stderr`, any unparsed provider payload,
any provider error string.

**Local machine detail** — `command`, `commandLine`, `environment`, env vars,
`homeDirectory`, `executablePath`, `path`, project paths, any filesystem path.

**Identity** — user name, account identifier, email address, computer or host
name, hardware serial, MAC address.

**Transport configuration** — server URL, host, port, route, Bonjour service
name, overlay-network address, APNs token, relay identifier. The payload must
stay meaningful under every candidate transport.

No fake-token fixtures exist in this repository: a file containing a realistic
looking secret is itself a hazard, so the prohibition is documented rather than
demonstrated.

### The strictness tradeoff

Every object in the schema sets `additionalProperties: false`. This is the
mechanism that makes the list above **structurally** enforced rather than merely
documented: a payload carrying `accessToken` anywhere fails validation, without
the schema needing to enumerate every forbidden name.

This deliberately conflicts with the usual "ignore unknown fields" guidance, and
the conflict is resolved in favour of strictness:

- **Within `schemaVersion: 1`, unknown properties are a hard failure.** The
  payload crosses a trust boundary; silently accepting unrecognised fields is
  how a credential rides along unnoticed. Privacy beats convenience here.
- **Across versions, evolution stays additive.** A later version may add
  optional fields. A consumer meets them by validating against that version's
  schema, not by loosening v1. A v1-only consumer that receives
  `schemaVersion: 2` must refuse it rather than guess.

The cost is real: a v1 consumer cannot forward-read a v2 payload. That is the
intended behaviour for a security boundary — fail closed, then upgrade
deliberately.

---

## 13. Issue codes: deferred

Schema v1 carries **no** error or issue field. A consumer distinguishes states
using `connected`, `collecting`, the presence or absence of `measurement`, and
`measuredAt`.

This is a deliberate narrowing. The product's `ProviderIssue` enum does expose a
stable `diagnosticCode`, but it is unsuitable for the wire as-is:

- Two cases carry **associated raw strings** — `.codexLaunchFailed(String)` and
  `.outputTooLarge(String)` — which is exactly the raw-error-text leak the
  contract forbids.
- Several codes describe **desktop-local executable trust and launch
  conditions** (`codex_untrusted_executable`, `codex_not_found`,
  `claude_untrusted_executable`) that are meaningless to a phone and disclose
  how the user's machine is configured.
- A paused provider **retains** its last error but the desktop does not render
  it as an active failure (`rendersActiveError = collectionEnabled && hasError`).
  Transmitting a retained error without that rule would make the phone blame a
  provider for a state the user chose.

If a later revision needs mobile-visible issue state, it must use a small
allowlisted enum of safe semantic codes carrying no free text, mapped
deliberately from `ProviderIssue` rather than exported from it.

---

## 14. Compatibility rules

1. `schemaVersion` is a positive integer. This document defines version `1`.
2. An **incompatible semantic change** — removing a field, narrowing a range,
   changing a field's meaning — requires incrementing `schemaVersion`.
3. **Additive optional fields** may be introduced in a later version. Consumers
   validating against that later schema may ignore fields they do not use.
4. **Unknown properties fail validation within a version** (§12).
5. **Missing required fields fail validation.**
6. **Percentages outside 0–100 fail validation.**
7. **Invalid timestamps fail validation.** Consumers must additionally parse and
   sanity-check instants rather than trusting the pattern alone.
8. **Duplicate `providerId` within `providers` fails validation.**
9. **Duplicate `windowId` within one provider's `windows` fails validation.**
10. `headlineWindowId` must match exactly one entry in that provider's `windows`.
11. The UsageBar **product version is never a compatibility mechanism** and does
    not appear in the payload. Wire schema and product release evolve
    independently.

Rules 8, 9 and 10 are cross-element constraints that JSON Schema cannot express;
they are consumer obligations and are called out here so no implementer assumes
schema validation alone is sufficient.

---

## 15. Validation performed in this checkpoint

Reported precisely, because overclaiming validation is itself a hazard.

**What ran** (no packages installed, local tooling only):

- `python3` — JSON parse of the schema and both examples
- `jq` — independent second-instance JSON parse
- a local, uncommitted checker script verifying: required fields present and
  correctly typed; every `remainingPercent` and `headlineRemainingPercent` in
  range 0–100; every timestamp matching RFC 3339 and parsing to a real instant;
  `windowId` agreeing with `kind` plus qualifier; `windowId` unique per provider;
  `providerId` unique; `headlineWindowId` resolving to a real window;
  `connected: false` implying no measurement; and no prohibited property name
  anywhere in the schema or examples

**What did NOT run:** full JSON Schema draft 2020-12 conformance validation.
No standards-compliant validator is installed on this machine (`jsonschema`,
`ajv` and `check-jsonschema` are all absent) and the design brief forbids
installing one for a design checkpoint. The `if`/`then`/`else` conditionals in
particular have **not** been exercised by a real validator.

A later phase that adds a validator should run conformance validation before any
sender or receiver is implemented.

---

## 16. Coverage against current product invariants

Each invariant below was read from the inherited baseline and checked to be
representable without semantic loss.

| Product invariant | Contract mechanism |
| --- | --- |
| Codex headline = most constrained window, any kind | `headlineRemainingPercent` + `headlineWindowId` |
| Claude headline = `fiveHour`, else ordinary `weekly` | same fields; desktop selects, phone never recomputes |
| Claude five-hour window | `kind: "fiveHour"` |
| Claude ordinary all-models weekly fallback | `kind: "weekly"` |
| Claude model-specific weekly (e.g. Opus) | `kind: "weeklyScoped"` + `scope` |
| Additional quota windows (e.g. a 3-day Codex window) | `kind: "duration"` + `durationMinutes` |
| Window whose duration is unknown | `kind: "unknown"` + `position` |
| Reset timestamps | `resetsAt`, optional |
| Provider connected state | `connected` |
| Provider collecting / paused state | `collecting`, independent of `connected` |
| Paused provider keeps its retained measurement | `measurement` permitted with `collecting: false` |
| Retained last successful measurement time | `measuredAt` (= `lastSuccessfulAt`) |
| Remaining percent as integer 0–100 | `remainingPercent`, integer, bounded |
| "No provider connected" vs "all paused" | empty `providers` vs no entry with `collecting: true` |

And the four things the phone demonstrably does **not** need — raw provider
output, desktop history, provider tokens, filesystem paths — appear nowhere in
the schema or examples.

### The one documented mismatch

`ProviderIssue` is **not** representable in schema v1, and this is deliberate
rather than an oversight. The consequence is stated plainly: a consumer can tell
that a provider is connected, whether it is collecting, whether a measurement
exists and how old it is — but **not why** a provider is currently failing.

A phone can therefore show "last measured 40 minutes ago" but cannot distinguish
"Claude is not logged in" from "the Codex CLI timed out". Whether that
distinction is worth the privacy and coupling cost is a decision for a later
revision, on the terms set out in §13 — a small allowlisted enum carrying no
free text. It is not smuggled in now.

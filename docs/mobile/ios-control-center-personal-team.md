# Control Center controls on a free Personal Team

UsageBar quota controls in the iPhone Control Center, built and proven on a
**free Apple Personal Team**, in the **existing** widget extension, with **no
new bundle identifier**, **no new extension target**, **no App Group** and no
paid Developer Program membership.

**Status:** Phase 7 complete. Gallery discovery, dynamic values, the tap action,
physical rendering at every Control Center size, offline retention and
credential revocation were all proven on a physical iPhone.

---

## What was uncertain, and how it was settled

Phase 6 established that a Personal Team can provision an app *and* a widget
extension sharing a keychain group. It did not establish that a
`ControlWidget` inside that extension would be offered by Control Center — free
provisioning restricts several capabilities, and nothing in Apple's
documentation says which side of that line controls fall on.

So Phase 7 ran the same empirical gate that made Phase 6 work: before any
UsageBar control logic existed, a **temporary control** with no network, no
credentials and no provider data was added to the existing extension, signed
with the existing Personal Team identity and installed on the device.

| Gate | Result |
| --- | --- |
| `ControlWidget` compiles against the installed iOS SDK | **PASS** |
| Existing extension builds and signs with the control included | **PASS** |
| New Apple portal capability required | **No** |
| New bundle identifier required | **No** |
| New signing certificate required | **No** — the existing one was reused |
| Control appears in the Control Center gallery on device | **PASS** |
| Control can be placed by the user | **PASS** |

Only then was the probe replaced with the real implementation. A successful
build proves nothing here: the widget-gallery failure in Phase 6 built and
signed perfectly and still never appeared.

## Architecture

Controls live in the **existing** `UsageBarWidgets` extension
(`com.usagebar.mobilelab.widgets`), listed in the same `WidgetBundle` as the
three Home/Lock Screen widgets:

    Control Center
        │
        ▼
    ControlWidget  ──  StaticControlConfiguration(kind:provider:)
        │
        ▼
    UsageControlValueProvider.currentValue()
        │
        ▼
    UsageSurfaceResolver          ← shared with the widget timeline provider
        ├── shared Keychain       ← same group as the app
        ├── UsageSyncAPIClient    ← the one HTTPS client
        └── extension-private validated snapshot cache
        │
        ▼
    Tailscale Serve ── HTTPS ── desktop ── schema-v1 snapshot

and the tap:

    ControlWidgetButton(action: OpenUsageBarIntent())
        │
        ▼
    UsageBar Mobile Lab

### One extension, not two

A separate controls extension would have meant a new bundle identifier, a new
provisioning profile, and — the actual reason to avoid it — a **second copy of
the credential and transport rules**. One subtly divergent copy of "may this be
displayed?" is precisely the bug this architecture is shaped to prevent.

### One resolver, not two

`UsageSurfaceResolver` is the single place that decides what an extension
surface may show, and both the widget timeline provider and the control value
provider call it. Writing the credential-first rule twice is how a widget and a
control would eventually disagree, and the disagreement would be invisible until
a forgotten connection kept showing usage in Control Center.

Controls create **no** network client, **no** keychain accessor and **no** cache
of their own.

### Cache

Controls and widgets run in the same extension, therefore the same container,
and share its one validated snapshot cache
(`widget-snapshot-v1.json`). A second file would be two copies of the same bytes
with two chances to go stale. The **app's** cache stays separate — that
separation is the App-Group-free architecture and is unaffected.

### Revocation without an App Group

Unchanged from Phase 6 and equally mandatory for controls: the resolver checks
the shared keychain **first**. No credentials means not-configured whatever the
cache holds, and the stale cache is cleared on the way past. The app calls
`ControlCenter.shared.reloadAllControls()` alongside
`WidgetCenter.shared.reloadAllTimelines()` after a successful connection, a
successful refresh and Forget Connection, so revocation takes effect promptly
rather than at the system's next scheduled evaluation.

Both calls are requests, never guarantees. App correctness does not depend on
either.

## The action

`OpenUsageBarIntent` is an `OpenIntent` whose only effect is to open the
containing app. Apple requires such an intent to be a member of **both** the app
and the widget extension, which is why it lives in `Shared/`.

There is deliberately **no** intent in this project that could do anything else.
A control is one brush of a thumb away in Control Center; an action that could
reset a quota, contact a provider, pause collection or change Tailscale would be
a mistake waiting to happen. The absence is structural, and a test asserts that
the only app intent in the project is this one.

The intent carries no credential, no host and no snapshot — a control's action
is stored by the system and surfaced in Shortcuts.

## What Control Center actually renders

**This section records observed behaviour on a physical iPhone 16 Pro Max
running iOS 27.0. It is not inferred from the simulator, and it is not a promise
about other devices or OS versions.**

| Control Center size | Rendered |
| --- | --- |
| 1×1 (default on placement) | **Glyph only.** No title, no value, no status. |
| 1×2 | Glyph, plus **one line** of label text beneath it. |
| 2×2 | Glyph, plus **one line** of label text beneath it. |

Two findings shaped the display, and both contradict what the code alone would
suggest:

1. **The percentage is not visible at the smallest size.** At 1×1 iOS draws the
   symbol and nothing else. This is normal system behaviour, not a defect, and
   it is why the three controls use three different SF Symbols: once the text is
   gone, the glyph is the only thing distinguishing them.
2. **`controlWidgetStatus` was never drawn.** Apple's documented secondary
   status slot produced no visible text at any Control Center size tested. The
   controls still set it — it is the correct API, and other placements or OS
   versions may render it — but **nothing important depends on it**, and
   everything that must be readable is in the label.

Observed text, against `shared/sync-schema/parity/basic.json`:

| Control | 1×1 | 1×2 and 2×2 |
| --- | --- | --- |
| UsageBar Codex | glyph only | `Codex 5H 64%` |
| UsageBar Claude | glyph only | `Claude 5H 52%` |
| UsageBar Overview | glyph only | `Codex 64% · Claude 52%` |

**The Overview control fits both percentages** at 1×2 and 2×2 without
truncation, which was the open question of the phase.

### What the one line carries

Ordered most to least important, because a narrow control truncates from the
right:

    <provider> <window> <percent>% · <time left>
    Codex      Weekly   21%       · 2d left

- The **percentage** is `headlineRemainingPercent` straight from the snapshot.
  It is never recomputed from `windows`; the desktop has already applied its
  provider-specific headline policy, and a second opinion on the phone is how
  Control Center would come to disagree with the Mac beside it.
- The **window label** is there because a bare "64%" is a figure without a fact.
  A Codex headline can be its five-hour limit on one reading and a multi-day
  limit on another.
- The **countdown** is to the *headline window's* `resetsAt`, floored — 21% with
  three days to run and 21% with twenty minutes to run are different situations.

The Overview control omits window labels and the countdown: two providers
already fill the line, and a string that truncates has told the user less than a
shorter one that fits.

**Tradeoff, stated explicitly.** The one line has room for the countdown or the
reading's age, not both, and the owner chose the countdown. A control therefore
does **not** show that a reading is old, which on a direct overlay it can be
whenever the desktop is asleep. Age remains on the app dashboard and the
widgets, which have room for both. `measuredAt` is still the only freshness
source in the model, and `generatedAt` still cannot substitute for it.

## States

| State | Control shows |
| --- | --- |
| No connection configured | `Open UsageBar` — **never** a percentage |
| Configured, nothing cached yet | `Codex —%` |
| Fetch succeeded | `Codex 5H 64% · 2h left` |
| Fetch failed, cache present | the cached reading, same format |
| Fetch failed, no cache | `Codex —%` |

A failed fetch never blanks a good reading, and no network, auth or HTTP detail
ever reaches the screen. A response body from a host the user typed is untrusted
text.

## Privacy

`ControlWidgetTemplate.privacySensitive()` exists in the installed SDK and is
applied to all three controls: quota is personal account information and is
redacted with the rest of the device's sensitive content rather than staying
legible on a locked screen.

The control value type has no property for a host, a bearer, a MagicDNS name, a
Tailscale identity, an HTTP status or an error string, and it is deliberately
**not** `Codable` — a serialization path would invite a third cache holding a
presentation of usage that no validator checks.

`previewValue`, shown in the controls gallery before a control is authorized to
display anything, is entirely invented: it reads no keychain, no cache and no
network.

## Updates

Controls are not timelines. There is no timer, no `BackgroundTasks` work, no
polling loop, no silent push and no `ControlPushHandler`. The system asks for a
value when it wants one; the request is bounded by the shared client's timeout
and its 64 KiB ceiling.

## Physical proof

Device: iPhone 16 Pro Max, iOS 27.0, wired, paired, Developer Mode on. Snapshot
source: the **synthetic** `UsageBarSyncTransportProbe` over a temporary
Tailscale Serve endpoint. This is not live provider data.

| Proof | Result |
| --- | --- |
| Personal Team provisioning of the control | **PASS** |
| Control Center gallery discovery | **PASS** |
| All three controls placeable | **PASS** |
| Codex value against canonical fixture (64%) | **PASS** at 1×2 and 2×2 |
| Claude value against canonical fixture (52%) | **PASS** at 1×2 and 2×2 |
| Overview shows **both** percentages | **PASS** at 1×2 and 2×2 |
| Percentage visible at 1×1 | **No** — glyph only, by system design |
| Tap opens UsageBar Mobile Lab | **PASS** for all three |
| Provider state changed by a tap | **None** |
| Values re-evaluate after an app refresh | **PASS** (21% / 88% fixture) |
| Offline: desktop service stopped | **PASS** — cached values retained, no error text, no crash |
| Forget Connection revokes the display | **PASS** — all three fell back to `Open UsageBar` |

Control Center evaluation is system-controlled and its latency is not promised.

## Personal Team limitation

Provisioning profiles expire after **7 days**. A later device install needs
re-provisioning (`-allowProvisioningUpdates`). This is normal free-provisioning
behaviour, not a code defect, and it applies to the controls exactly as it does
to the app and the widgets.

## What this phase did not do

- No live desktop provider wiring. The snapshot remains synthetic.
- No App Group, no Tailscale SDK, no `NetworkExtension`, no VPN configuration.
- No new extension, bundle identifier, App ID, certificate or entitlement.
- No schema change. Schema v1 is untouched, as are `Sources/`, `windows/` and
  `Package.swift`.
- **Production integration remains unauthorized.**

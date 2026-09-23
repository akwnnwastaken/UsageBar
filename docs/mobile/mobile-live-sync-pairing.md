# Live desktop sync and secure QR pairing

The first checkpoint in which **real** UsageBar quota data reaches a phone.
Everything before Phase 8 moved synthetic schema-v1 fixtures.

**Status:** Phase 8 complete. Live wiring, pairing, identity binding, restart
persistence, server-side revocation and offline retention were all proven on the
owner's own Mac and iPhone, over their own tailnet.

**Scope:** Mobile Lab only. Production integration remains unauthorized.

---

## The shape of it

    UsageBar (macOS)
        displayUsages  ──►  UsageSyncSnapshotBuilder  ──►  validated schema-v1
                                                              │
                                                    UsageSyncLiveSnapshotStore
                                                              │
                                              127.0.0.1:18642 (loopback only)
                                                              │
                                                    Tailscale Serve (HTTPS 443)
                                                              │
                                                          iPhone app
                                                              ├─ Home / Lock widgets
                                                              └─ Control Center

## The desktop source is what the Mac is *showing*

Live snapshots are built from **`displayUsages`**, never from the raw `usages`
cache and never from usage history.

This is not a detail. `UsageDisplayNoiseFilter` deliberately holds a rise back
for a cycle, so a snapshot built from the raw cache would put a number on the
phone that the Mac beside it is not showing yet. A phone that disagrees with the
Mac is worse than a phone with no data.

The builder is also not a second filter, and not a second headline policy. It
maps field by field from a `ProviderUsage` the display filter has already
produced, and asks the product's own `UsageSummaryCalculator` which window is
the headline — so Claude keeps five-hour-then-ordinary-weekly and Codex keeps
most-constrained-window, including when that is a `duration` window.

What cannot cross, because there is no field for it: provider errors, raw CLI
output, history samples, executable paths, environment, credentials.

A retained stale reading keeps its original `measuredAt`. That timestamp is the
entire basis of the phone's freshness display and must not advance because a
later read failed.

### When it republishes

At every transition that can change wire-visible state, and at none that cannot:

- initial application state
- refresh completion — after the display filter advances, so the phone is served
  the numbers the menu is about to draw
- provider connect / disconnect
- collection pause / resume
- enabling Mobile Sync

Showing a provider's details or opening a menu section changes what the Mac
draws, not what schema v1 says, so neither republishes.

### Sync is subordinate to UsageBar

Every call into Mobile Sync is non-throwing to its caller. A snapshot that fails
to build leaves the previous one published and the refresh cycle never learns
about it. A listener that cannot bind is reported in the menu and nowhere else.
The menu bar, the menus, history and alerts keep working when Tailscale is down,
the Keychain refuses, or pairing is impossible.

### One store between two queues

`UsageSyncLiveSnapshotStore` is the only thing between the desktop's main queue
and the listener's connection queues. It validates *before* it stores, so an
invalid snapshot is never briefly observable, and a failed rebuild leaves the
previous good one in place. What crosses is an immutable value type — no AppKit
object, no provider, no preference reference.

## The desktop identity

Mobile Sync runs inside UsageBar itself, under `local.codex.usagebar`. There is
no second Mac application.

That identifier does the work: it is the **runtime gate**.
`MobileSyncCoordinator` refuses to start a listener, hold a credential or offer
pairing unless the running bundle identifier is exactly UsageBar's, and it is
the only permitted value — there is deliberately no second entry, so a build
that is not UsageBar cannot serve a phone from the same machine.

Containing the code is not permission to run it. A test runner or an unbundled
`swift run` build links this module and still never opens a listener; `nil` is
not permission either. Neither is the preference, which defaults to false, so a
first launch after upgrading opens nothing at all.

This feature reached UsageBar from a separate application, **UsageBar Mobile
Host 0.1.0**, which carried `com.usagebar.mobilelab.host`. Its preference key
and its Keychain service are *not* reused and nothing migrates from them, so a
phone paired with that host is not paired with UsageBar. Pair once more; the
iPhone app needs no rebuild.

## The listener

`UsageSyncLoopbackHTTPServer`, bound to `127.0.0.1:18642` and nothing else. The
bind address is fixed in code and cannot be configured outward.

Loopback-only is inseparable from the identity header: Serve's injected
`Tailscale-User-Login` is trustworthy **only** because Serve is the sole path to
the backend. A service on a routable interface could be called directly by
anyone on the LAN or tailnet, who would simply supply their own header value.

A fixed port rather than an ephemeral one, so an externally configured Serve
mapping survives restarts.

## Tailscale is read, never written

The host may run `tailscale status --json` to learn its own MagicDNS name. It
resolves an **absolute** executable from a fixed list — never a `PATH` lookup,
never a shell — passes an explicit argument vector, bounds the output, times
out, parses out two fields and drops the rest. Peers, addresses and keys never
leave the reader, and the FQDN is held only while a QR is on screen.

It does **not** configure Serve, Funnel, DNS, grants, ACLs, tags, auth keys or
OAuth clients. Phase 8's Serve mapping was configured externally by the
checkpoint and removed afterwards. Whether production UsageBar should manage
Serve is a Phase 9 question.

> One practical note, learned on hardware: the macOS Tailscale CLI talks to its
> GUI helper and fails under a stripped environment, printing a human sentence
> to *stdout* while still exiting 0. The reader therefore inherits the
> environment — safe, because the executable path is absolute and the argument
> vector explicit — and refuses any stdout that does not begin a JSON object.

## Pairing

### The QR carries nothing durable

    { "v": 1, "host": "<machine>.<tailnet>.ts.net", "pairingCode": "<256 bits>" }

Three fields, and the parser rejects a fourth. There is no property for a
long-lived bearer, a Tailscale login, an address, a tailnet identifier or a
device identifier.

A QR is photographable by anyone who can see the screen, so the rule is not
"keep the payload small" but **put nothing in it that is still worth having
tomorrow**. The pairing code buys exactly one credential issuance and expires in
two minutes.

Rendered with Core Image. No third-party QR library, no clipboard copy, and the
payload is never displayed as readable text beside the image.

### The session is deliberately fragile

- 256 bits from the system CSPRNG
- created only on an explicit **Pair iPhone** action
- expires after **120 seconds**
- **one** success — checked and consumed inside a single critical section, so
  two simultaneous requests cannot both be issued a credential
- **8** failed attempts closes it
- a new session invalidates the previous one
- closing or cancelling the window invalidates it
- never persisted, never logged; a relaunched process knows nothing of it

### The exchange

    POST /v1/pair
    Authorization: UsageBar-Pair <one-time code>

The code travels in a header under its own scheme — never in a URL, a query
string or a path, all of which are logged and kept in history. There is no body
at all. A dedicated scheme means a pairing code can never be mistaken for a
bearer by either side.

On success the desktop generates a fresh 256-bit bearer, returns it **once** in
a two-field JSON body, and keeps only digests. Every response carries
`Cache-Control: no-store`.

If the response is lost, the owner shows a new QR. A new pairing rotates — and
therefore revokes — whatever the previously paired phone held.

## Long-lived authentication

The Mac does **not** retain the raw bearer. There is no property that could hold
one. It persists, in a lab-only Keychain service
(`com.usagebar.mobilelab.host.mobile-sync`,
`WhenUnlockedThisDeviceOnly`):

    schemaVersion
    bearerDigest     SHA-256
    identityDigest   SHA-256 of the normalized Tailscale login
    createdAt

A Keychain dump, a backup or a stolen laptop therefore yields nothing
replayable against the endpoint.

### Both factors, or nothing

`GET /v1/snapshot` requires the presented bearer to match the stored digest
**and** the Serve-injected identity to match the stored identity digest. A
leaked bearer used from a different tailnet identity fails — which is what keeps
a tailnet compromise (T18) from being sufficient on its own.

Both comparisons are constant-time, and both are computed before the `&&` so the
work done does not depend on which factor failed.

A caller is told `401` whether the bearer was wrong, the identity was wrong, or
the pairing was revoked. Distinguishing them would tell someone holding a leaked
token that the token itself is still good and only the identity is not — exactly
the fact the binding exists to withhold. Refusal bodies are the status number
and nothing else, and authentication runs before routing so an unauthenticated
prober cannot learn which routes exist.

The raw Tailscale login is never persisted, never echoed and never logged. It is
an email address; the Mac keeps only the answer to "is this the same caller that
paired?".

## The phone

### Nothing is stored until it is proven

After a scan the app exchanges the code, holds the returned key **in memory**,
issues a normal `GET /v1/snapshot` with it, and requires HTTP 200 plus a strict
schema-v1 decode and validation. Only then do the host and the key reach the
shared Keychain. A credential that cannot actually fetch would otherwise leave
the app looking configured and permanently failing.

### The scanner

AVFoundation's own metadata detector, QR only, one scan per presentation. The
camera runs only while the scanner is on screen and stops when it leaves. No
frame is retained, written or uploaded. The camera usage description names
pairing specifically; no photo-library or microphone permission is requested.

A QR that is not a UsageBar payload is ignored rather than guessed at.

### Transport rules are the snapshot client's

System TLS, **no redirect following** (a redirect would re-issue the request —
carrying the live pairing code — at whatever host answered), no cookies, no URL
cache, finite timeouts, JSON required, 200 only, and a 4 KiB ceiling on the
pairing response. The app never sets a Tailscale identity header; Serve injects
one, and a client that set it would be asserting an identity rather than proving
it.

### A definitive 401 revokes locally

`authenticationRejected` is the only failure that is definitive. Every other —
timeout, 5xx, refused redirect, oversized body, malformed snapshot — means "ask
again later" and leaves the credential and the cache exactly where they are.

On a definitive rejection:

| Surface | Behaviour |
| --- | --- |
| Main app | clears the shared connection and its cache, returns to setup, asks widgets and controls to reload |
| Widget / control extension | clears the shared connection and the extension cache, reports not-configured |

So **Revoke Paired iPhone** on the Mac propagates: the next fetch gets 401, the
phone forgets, and the old quota disappears from every surface.

### Locked is not revoked

`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is unchanged — Phase 8 hardens
the *interpretation* of a locked Keychain rather than loosening the protection
class to avoid the problem.

A Keychain read now has three outcomes, and the third is the subtle one:

| Availability | Meaning | Surface behaviour |
| --- | --- | --- |
| `available` | normal | fetch, fall back to cache on failure |
| `missing` | nothing stored — revocation | clear cache, not-configured |
| `temporarilyUnavailable` | stored but unreadable, device locked | **keep** the connection, **keep** the cache, show the cached reading, make **no** network request |

Collapsing the last two into `nil` would make a locked phone indistinguishable
from a forgotten connection, and the widget would delete a perfectly good
snapshot every time the screen went off. Worse, attempting a fetch without an
accessible credential would be answered 401 — which the surface would then
correctly, and disastrously, treat as revocation. So no request is made without
a credential in hand.

This is **semantics, not timing**. WidgetKit decides when an extension runs, and
nothing here promises evaluation at any particular moment while locked.

## Background refresh: still none

No `BackgroundTasks`, no APNs, no silent push, no polling loop, no
`ControlPushHandler`. WidgetKit timelines and `ControlValueProvider` already ask
for values on the system's own schedule. Phase 8 hardens locked and offline
behaviour rather than adding another clock.

## No App Group

Unchanged from Phase 6/7: credentials are shared through one Keychain group, the
app keeps its own cache, the extension keeps its own, and widgets and controls
share the extension's because they are the same extension. No
`com.apple.security.application-groups`, and `group.com.usagebar.mobilelab` is
still not registered.

## Physical proof

Owner's own Mac and iPhone, own tailnet, real Codex and Claude data.

| Proof | Result |
| --- | --- |
| Lab host runs with its own empty preference domain | **PASS** |
| Mobile Sync starts disabled; no listener until enabled | **PASS** |
| Listener binds `127.0.0.1:18642` and nothing else | **PASS** |
| Unauthenticated / identity-only / wrong-bearer requests | **401**, bare body |
| Pairing without an active session | **401**, no credential issued |
| QR pairing end to end | **PASS** |
| Mac persists digests only, no raw bearer or identity | **PASS** |
| Stored identity digest equals SHA-256 of the live tailnet login | **PASS** |
| Pairing session consumed; later pair attempt refused | **PASS** |
| Live app dashboard matches the Mac | **LIVE VALUE MATCH — PASS** |
| Live Home and Lock Screen widgets match | **PASS** |
| Live Control Center controls match | **PASS** |
| Lab host restart without re-pairing | **PASS** |
| Revoke Paired iPhone → 401 → phone forgets | **PASS** |
| Widgets and controls stop showing quota after revocation | **PASS** |
| Re-pair issues a new bearer and works | **PASS** |
| Desktop service stopped → cached values retained, no error text | **PASS** |
| Forget Connection clears every surface | **PASS** |

**No exact live quota value, reset timestamp, hostname, address, identity or
digest from that run is recorded in this repository.**

## What Phase 8 did not do

- No production change of any kind. `/Applications/UsageBar.app` and its
  preferences were verified byte-identical before and after.
- No Tailscale grants, ACL, tag, auth-key or OAuth mutation.
- No schema change. Schema v1 is untouched, as are `shared/sync-schema/`,
  `windows/` and `.github/`.
- No App Group, no Tailscale SDK, no `NetworkExtension`, no VPN configuration.
- **Production integration remains unauthorized.**

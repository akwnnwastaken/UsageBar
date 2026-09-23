# iOS companion client

The first native iPhone surface for UsageBar Mobile Lab. It reads a schema-v1
snapshot from the desktop over a private tailnet and shows it.

**Status:** Phase 5 complete. The app builds, its 66 unit tests pass on the
simulator, and it has been **installed and proven on a physical iPhone** against
a live Tailscale Serve endpoint.

The snapshot it displays is **synthetic** — served by the Phase-4 transport probe
from a fixture, not by a running UsageBar. Wiring live Codex/Claude desktop
state is a separate, later checkpoint.

---

## Architecture

    synthetic fixture
        → UsageBarSyncTransportProbe (loopback-only HTTP, 127.0.0.1)
        → Tailscale Serve (TLS termination + identity injection)
        → HTTPS inside the tailnet
        → iPhone, URLSession
        → strict schema-v1 decode + validation
        → app-sandbox cache
        → SwiftUI dashboard

| Layer | Type |
| --- | --- |
| Host validation | `UsageSyncHost` |
| Credential + host storage | `KeychainConnectionStore` |
| Networking | `UsageSyncAPIClient` |
| Cache | `FileSnapshotCache` behind `SnapshotCaching` |
| State | `AppSnapshotStore` |
| Presentation | `ProviderPresentation`, `WindowPresentation`, `FreshnessPresentation` |
| UI | `ConnectionSetupView`, `DashboardView`, `ProviderCardView` |

## One schema implementation, not three

The app depends on the **`UsageBarSync`** library from this repository's Swift
package. It does not copy `UsageSyncSnapshot`, the validator or the serializer
into `ios/`.

That reuse is why `Package.swift` declares `.iOS("18.0")` alongside
`.macOS(.v13)`. `UsageBarCore` and `UsageBarSync` import only Foundation and
CoreGraphics (`CGFloat`, `CGPoint`, `CGRect`), all of which exist on iOS, so the
declaration added a platform without changing a line of macOS behaviour. The
desktop-only targets — `UsageBar` and `UsageBarSyncTransport` — are simply never
built for iOS, and the phone does not depend on either.

## Endpoint contract

    GET https://<magicdns-host>/v1/snapshot
    Authorization: Bearer <access key>
    Accept: application/json

The app accepts a **hostname**, never a URL, and builds the URL itself. A user
who could type a URL could type a scheme, a port, a path or credentials, and the
bearer token would follow wherever that pointed.

A host is rejected unless it is a lowercase DNS name of at least four labels
ending in `.ts.net`, with no scheme, credentials, port, path, query, fragment,
whitespace or control characters, and it must not be a raw IP address. The raw
`100.x` tailnet address is refused deliberately: it bypasses the MagicDNS name
the certificate is issued for.

**Transport configuration never enters `UsageSyncSnapshot`.** The host lives in
the keychain and the payload has no field that could hold one.

## No Tailscale SDK

The app embeds no Tailscale SDK or `tsnet`, invokes no Tailscale CLI, uses no
`NetworkExtension`, creates no VPN configuration and reads nothing from the
Tailscale app. The user's installed Tailscale iOS client supplies reachability;
from `URLSession`'s point of view this is an ordinary HTTPS request to an
ordinary hostname.

## The app never sets identity headers

`Tailscale-User-Login`, `Tailscale-User-Name` and `Tailscale-User-Profile-Pic`
are injected by **Tailscale Serve**, which is the only party in a position to
prove them. A client that set one would merely be *asserting* an identity, and
the desktop would be trusting a value the caller chose. A test asserts the app
emits no header beginning `tailscale-`.

This is also why the desktop service binds to loopback: Serve's headers are
trustworthy only while Serve is the sole ingress.

## Transport security

Standard system TLS validation. No ATS exception, no
`NSAllowsArbitraryLoads`, no certificate pinning, no custom root CA, no
self-signed acceptance, no TLS-bypass delegate, and no plaintext HTTP.

The `URLSession` configuration is ephemeral and remembers nothing: no URL cache,
no cookie storage, no credential storage, cache policy
`reloadIgnoringLocalAndRemoteCacheData`, and finite request and resource
timeouts. The bearer is attached to exactly one request.

**Redirects are refused outright.** Following one would re-issue the request —
with the `Authorization` header — at whatever host the response named. A single
302 from a mistyped host would hand the bearer to a stranger. Tested against
301, 302, 307 and 308, asserting no second request is made.

**Response bodies are capped at 64 KiB**, enforced on the declared
`Content-Length` before any body is accepted *and* incrementally during receipt,
because a server that lies about or omits its length would otherwise stream
unbounded data into memory. Exceeding the cap cancels the transfer and leaves
the previous cache untouched.

Only **HTTP 200** with a `application/json` content type may replace the cached
snapshot. Everything else is a failed refresh. No server response body, TLS
message or underlying error description ever reaches the screen — the user sees
one of two short generic sentences.

## Keychain

Both the access key **and** the host are stored in the iOS keychain with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

The host is kept there alongside the credential on purpose: a MagicDNS name
identifies a machine on a private tailnet and is frequently derived from its
owner, so it is personal metadata rather than a harmless address.
`ThisDeviceOnly` keeps both out of device backups and off other devices;
`WhenUnlocked` suffices because Phase 5 refreshes only in the foreground when
asked. Background refresh will require that decision revisited, not quietly
loosened.

Neither value is in source control, in `UserDefaults`, in a plist, in the cache,
in a URL or in any log. No Keychain Sharing entitlement is used.

## Cache

One validated schema-v1 snapshot, written atomically with complete file
protection into the app's own Application Support directory and excluded from
backup.

It contains **only** the snapshot. No bearer, no host, no Tailscale identity, no
response metadata, no error text — there is no field for them and the cache
layer never sees them. A test asserts the written bytes contain no such term and
that the top-level keys are exactly `schemaVersion`, `generatedAt`, `providers`.

On load the bytes are decoded **and validated again**: a file can be truncated by
a crash or edited on a jailbroken device, and a cache is as untrusted as a
network response once it has left the process that wrote it. Corrupt or
schema-invalid content is discarded and the app behaves like a first launch
rather than crashing.

`SnapshotCaching` is a deliberately narrow protocol so the widget checkpoint can
swap the sandbox cache for an App Group container without touching networking,
validation or presentation.

### No App Group yet

`group.com.usagebar.mobilelab` is **not** registered or created. It belongs to
the widget checkpoint.

## Offline behaviour

A failed refresh **never** clears a good snapshot. The last validated reading
stays on screen with a small banner saying the Mac could not be reached, and the
per-provider age keeps showing how old the reading is.

This is the accepted tradeoff of a direct overlay rather than a relay: if the Mac
is asleep, there is no fresh measurement to be had. It must read as "this is the
last reading", never as "there is no data".

## Freshness

Age comes from each provider's **`measurement.measuredAt`**, never from the
snapshot's `generatedAt`.

`generatedAt` is when the *document* was built, and it advances every time the
desktop serializes — including when a reading is retained, stale or paused.
Using it would make a week-old measurement look seconds fresh, which is exactly
what the contract was shaped to prevent. A test builds a snapshot generated
"now" from a measurement taken a day earlier and asserts the UI says
`Updated 1 day ago`.

Phase 5 states the age as a fact and draws no conclusion from it. **No stale
threshold is invented**: what counts as too old is an undecided client-policy
question, and a wrong threshold is worse than none.

## Presentation

All labels are derived on the phone from structured fields. The desktop sends
identifiers and numbers, never localized strings — a display name crossing the
wire would be presentation leaking into a data contract, and would have to be
versioned like data forever after.

| Wire | Shown |
| --- | --- |
| `codex` | Codex |
| `claude-code` | Claude |
| unknown provider id | title-cased from the slug |
| `fiveHour` | 5 Hour |
| `weekly` | Weekly |
| `weeklyScoped` + scope | Weekly · Opus |
| `duration` | largest exact unit, e.g. 3 Day |
| `unknown` | Additional Limit *n* |

`windowId` is never shown as UI text.

States: `connected && !collecting` → **Paused** (a user choice, not a fault, and
a retained measurement still displays); `connected && collecting` with no
measurement → **Waiting for usage data**; `!connected` → **Disconnected**.

## Refresh

User-initiated only: a toolbar button and pull-to-refresh. Concurrent refreshes
are suppressed. There is **no timer, no `BackgroundTasks`, no silent push and no
background polling** in Phase 5.

## Forget Connection

Removes the host, the access key and the cached snapshot together, and returns
to the setup screen. All three, always: a cached snapshot left behind after the
user disconnects would keep showing their usage to whoever next opens the app.

## No analytics

No analytics, telemetry, crash SDK, third-party logging or network-inspector
SDK. The app never logs the host, the access key, the `Authorization` header, a
response body or a Tailscale identity.

## Physical-device smoke method

**Performed, PASS.** The procedure below was executed against a connected
iPhone joined to the tailnet.

1. Verify Tailscale Serve is empty and Funnel inactive.
2. Generate a fresh ≥256-bit bearer into a mode-`0600` scratch file.
3. Start `UsageBarSyncTransportProbe` with
   `shared/sync-schema/parity/basic.json`; confirm via `lsof` that it is bound
   to `127.0.0.1` only, and that the tailnet address on that port is unreachable.
4. `tailscale serve --bg --https=443 http://localhost:<port>`; confirm exactly
   one proxy target and Funnel still inactive.
5. Pipe the FQDN and then the secret **directly to `pbcopy`** — never printed,
   never echoed — and have the owner paste each into the app.
6. Confirm the dashboard renders the fixture, then stop the probe and refresh
   again to prove the cache survives the desktop going away.
7. In the app, **Forget Connection**. On the Mac: clear the clipboard, remove the
   Serve config, verify the empty pre-state, stop the probe, delete the scratch
   secret.

HTTPS Certificates are a tailnet-level setting the owner enabled; cleanup does
**not** disable them.

### Result

Fetch returned 200; the body strictly decoded and validated; the dashboard showed
both provider cards with the fixture's exact headline and window percentages,
ages and reset times. Stopping the desktop service and refreshing kept the data
on screen behind an offline banner. Forget Connection removed the host, the
credential and the cache together. Afterwards the Serve configuration was removed
and the empty pre-state verified, Funnel stayed inactive, the probe was stopped
and the scratch secret deleted.

The dashboard opening is the identity-header proof. The desktop service requires
`Tailscale-User-Login`, this app never sends one, and a request without it is
answered 401 — so the header can only have been injected by Serve.

## No private values in this repository

No real FQDN, tailnet suffix, Tailscale IP, device name, user email, bearer
secret, Apple Team ID, device UDID or provisioning-profile identifier is
committed. Tests use deliberately fake values such as
`usagebar-test.example-tail.ts.net` and `tester@example.invalid`.

### Signing configuration

An Apple Team ID identifies a person's developer account and differs per machine
and per contributor, so it is treated as local configuration rather than source.

    Config/Signing.xcconfig        tracked; contains no Team ID
    Config/LocalSigning.xcconfig   untracked; holds DEVELOPMENT_TEAM

The tracked file is the project's base configuration and does nothing but
optionally include the local one:

    #include? "LocalSigning.xcconfig"

The include is optional on purpose. Without the local file the project still
opens, configures, builds for the simulator and runs its whole test suite; only
installing on physical hardware needs a team. The local file is excluded through
`.git/info/exclude` rather than the repository `.gitignore`, because it is one
developer's machine state and not a rule for everyone who clones the repo.

## Deferred

Final QR pairing, long-lived credential design and revocation UX, least-privilege
Tailscale Grants (designed in
[`mobile-transport-grants-plan.md`](mobile-transport-grants-plan.md), not
applied), App Group and widgets, Control Center, background refresh, and live
desktop provider wiring.

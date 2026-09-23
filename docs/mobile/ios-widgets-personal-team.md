# iOS widgets on a free Personal Team — no App Group

Home Screen and Lock Screen widgets for UsageBar Mobile Lab, built and proven on
a **free Apple Personal Team**, with **no App Group** and no paid Developer
Program membership.

**Status:** Phase 6 complete. Provisioning, runtime credential sharing, Home
Screen and Lock Screen rendering, offline retention and credential revocation
were all proven on a physical iPhone.

---

## The constraint that shaped the design

A free Personal Team **cannot create App Groups**. The obvious WidgetKit
architecture — app writes a snapshot into a shared container, widget reads it —
is therefore unavailable.

Rather than buy a membership to keep that shape, Phase 6 asked a narrower
question: what *can* a Personal Team share? The answer turned out to be
**Keychain Sharing**, and that is enough, because the app and the widget do not
actually need to share *data*. They need to share *authority*.

    Main app                          Widget extension
      │                                 │
      ├── shared Keychain ──────────────┤   host + bearer only
      │                                 │
      └── own private cache             └── own private cache

Each target fetches for itself over HTTPS and keeps its own validated snapshot.
Nothing but the credentials crosses between them.

### Feasibility, proven not assumed

Whether a free Personal Team would provision `keychain-access-groups` for an app
*and* an extension was not documented anywhere we could rely on, so it was
tested before any widget UI was written:

| Gate | Result |
| --- | --- |
| App + extension provisioning under Personal Team | **PASS** |
| Same `keychain-access-groups` entitlement on both, signed | **PASS** |
| `application-groups` absent from both | **PASS** |
| Runtime: widget reads credentials the app wrote | **PASS** |
| New signing certificate required | **No** — the existing one was reused |

The runtime proof is the strongest available one: on the device, the widget read
the shared connection the app had just saved, completed its own HTTPS fetch and
rendered the result. A synthetic marker item would have proven strictly less.

## Entitlements

Both targets declare exactly one shared group:

    <key>keychain-access-groups</key>
    <array>
      <string>$(AppIdentifierPrefix)com.usagebar.mobilelab.shared</string>
    </array>

`$(AppIdentifierPrefix)` expands at build time to the signing team prefix, so
**no literal Team ID appears in source**, and only targets signed by the same
team can join the group. Neither target declares
`com.apple.security.application-groups`; a test asserts that, and asserts the
project file contains no app-group identifier either.

## Widget set

One extension, `com.usagebar.mobilelab.widgets`, containing three kinds:

| Widget | Families |
| --- | --- |
| **UsageBar Overview** | `systemSmall`, `systemMedium`, `accessoryRectangular` |
| **UsageBar Codex** | `systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` |
| **UsageBar Claude** | same as Codex |

Family lists live in shared code rather than inline in the `Widget` types,
because an app extension cannot be `@testable`-imported — a list written inline
could never be asserted.

## One network implementation, not two

The widget does not carry a copy of the app's client. `Shared/` is compiled into
both targets, so there is exactly one implementation of host validation,
transport security, redirect refusal, the response size bound, status and
content-type policy, and schema-v1 decoding. A subtly different second client in
the extension is precisely the bug this avoids.

The widget inherits every Phase-5 rule: HTTPS only, no raw `100.x` address, no
redirects, 64 KiB cap, `application/json` required, strict decode and validate,
no Tailscale SDK, and **it never sets a Tailscale identity header** — Serve
injects those and is the only party able to prove them.

## Caches stay private

Without an App Group the app and widget are in separate containers; the cache
files are named differently too, so the separation does not depend on container
layout. Each cache holds a validated schema-v1 snapshot and nothing else — no
host, no bearer, no identity, no error text, no response metadata.

## Credential revocation without shared storage

This is the interesting consequence of having no App Group: **the app cannot
delete the widget's cache.** "Forget Connection" cannot reach into the
extension's sandbox.

So revocation is done by authority rather than by erasure. The widget checks the
shared keychain for credentials **before** it will display an authenticated
snapshot:

- credentials present → fetch, or fall back to its own cache
- credentials absent → **`notConfigured`**, regardless of what the cache holds,
  and the stale cache is cleared on the way past

Removing the keychain items therefore revokes display authorization at the next
timeline evaluation. The app also calls `WidgetCenter.reloadAllTimelines()` on
forget, so that evaluation happens promptly instead of at the next system
refresh. Proven on device: after Forget Connection the widget showed
"Open UsageBar".

## Scheduling is the system's, not ours

The provider asks for its next timeline no sooner than ~15 minutes out. That is
a floor and a hint: **WidgetKit decides when refreshes actually run**, and it
coalesces and defers them on its own budget. There is no timer, no
`BackgroundTasks` and no polling loop. The app requests a reload after a
successful connect or refresh, and after forget — but app correctness never
depends on WidgetCenter, which is why it sits behind a protocol.

## Lock Screen privacy

Quota levels are personal account information and a Lock Screen widget is
visible without unlocking, so dynamic values are marked `privacySensitive()` and
iOS redacts them according to the user's own setting. Placeholders use invented
values and never a stored reading. No connection or authentication state is
shown on the Lock Screen.

## Physical-device proof

| Check | Result |
| --- | --- |
| App + widget installed on iPhone | **PASS** |
| Home Screen `systemSmall` | **PASS** — Codex 64%, Claude 52% |
| Home Screen `systemMedium` | **PASS** — both providers plus window rows |
| Lock Screen accessory | **PASS** — provider and percentage |
| Widget offline retention | **PASS** — values kept after the desktop stopped |
| Credential revocation | **PASS** — "Open UsageBar" after Forget Connection |

Values matched `shared/sync-schema/parity/basic.json`. The snapshot was
**synthetic**, served by the Phase-4 transport probe. This is not live
Codex/Claude sync and no provider data has ever left a desktop.

Afterwards the temporary Serve configuration was removed and the empty
pre-state verified, Funnel stayed inactive, the probe was stopped, the scratch
bearer deleted and the clipboard cleared. HTTPS Certificates were **not**
disabled.

## Personal Team limitation to remember

**Personal Team provisioning profiles expire after 7 days.** Re-installing on
hardware after that needs re-provisioning. This is normal for free provisioning,
not a defect — but it means the app stops launching from a stale build about a
week after each install.

## Signing configuration

Unchanged from Phase 5: the owner's `DEVELOPMENT_TEAM` stays in an untracked
`Config/LocalSigning.xcconfig`, optionally included by the tracked
`Config/Signing.xcconfig`. **No Team ID, device identifier or provisioning UUID
is committed.**

## Sources

Apple developer documentation consulted 2026-09-22:

- Keychain Access Groups entitlement —
  `https://developer.apple.com/documentation/bundleresources/entitlements/keychain-access-groups`
- Configuring keychain sharing —
  `https://developer.apple.com/documentation/xcode/configuring-keychain-sharing`
- WidgetKit —
  `https://developer.apple.com/documentation/widgetkit`

## Deferred

Control Center controls, live desktop provider wiring, final QR pairing and
long-lived credential design, and least-privilege Tailscale Grants (designed in
[`mobile-transport-grants-plan.md`](mobile-transport-grants-plan.md), not
applied).

# Mobile transport decision — Tailscale private overlay

**Status:** SELECTED BY OWNER — 2026-09-22

This supersedes the *Transport Decision — Deferred* section of
[`mobile-sync-threat-model.md`](mobile-sync-threat-model.md), which recorded the
candidate analysis while the decision was open.

---

## Decision

UsageBar mobile sync will use **Tailscale as the private network substrate**.

Tailscale is the **connectivity layer**, not a backend. Nothing is stored or
processed on anyone else's server: the desktop remains the source of truth and
answers for itself over the tailnet.

## Initial architecture

    UsageBar Desktop
        │  local UsageBar sync service
        ▼
    Tailscale tailnet  (private overlay)
        ▼
    UsageBar iPhone
        ▼
    App Group cache
        ├── iPhone app
        ├── Home / Lock Screen widget
        └── Control Center

## What this locks

| | |
| --- | --- |
| **A** | Tailscale is the private connectivity layer. |
| **B** | The desktop remains the source of truth. |
| **C** | The future desktop sync service is reached **only** through the private tailnet. |
| **D** | UsageBar will **not** intentionally expose this service to the public internet. |
| **E** | **Tailscale Funnel is out of scope** and must not be used for UsageBar mobile sync unless the owner explicitly reverses this. |
| **F** | **No cloud mailbox or relay** is planned in the initial architecture. |
| **G** | Desktop-offline semantics are **accepted**: if the desktop is asleep, offline or unreachable, the phone cannot obtain a new measurement. |
| **H** | Tailscale failure must **never** impair normal desktop UsageBar behaviour. |

On **G**, the phone will eventually retain its last validated snapshot and
display its age from `measuredAt`. The contract already supports this: a cached
snapshot is self-dating, so a stale reading can never masquerade as a fresh one.

## Why this architecture is attractive

- no router port forwarding
- no public server to operate
- private device-to-device reachability
- works across different physical networks
- encrypted tailnet transport
- the desktop remains authoritative
- no cloud snapshot storage required — usage data never rests on third-party
  infrastructure, which removes an entire class of retention and operator risk

## Accepted tradeoff

**The desktop must be awake and reachable for fresh data.** This is the known
cost of not having a relay, and it was accepted deliberately rather than
discovered later. A widget refreshing while the Mac sleeps shows the last
validated snapshot, labelled with its age.

## Rejected / deferred alternatives

An **encrypted cloud relay or mailbox** (previously candidate C, including any
hosted-worker implementation) is **not part of the initial architecture**. It
remains documented only as a rejected alternative, not as a planned phase. It
would have survived a sleeping desktop, at the cost of operating external
infrastructure, mandatory key lifecycle management, and adding an operator to
the threat model. Revisiting it would require the owner to reopen this decision.

## Resolved in Phase 4

Selecting Tailscale resolved the transport **class**. Phase 4 answered the
questions below it, with a working prototype rather than on paper:

| Question | Answer |
| --- | --- |
| Serve vs a tailnet-bound listener | **Tailscale Serve**, proxying to a loopback-only backend |
| MagicDNS vs a `100.x` address | **MagicDNS**, reached over HTTPS; neither form enters the payload |
| Application protocol | HTTP/1.1 behind Serve's TLS termination |
| Service port | loopback port only; Serve terminates on 443 inside the tailnet |
| Listener framework | none — a minimal BSD-socket listener, no third-party dependency |
| Service discovery | none needed; the MagicDNS name is the address |
| Is Tailscale identity sufficient authentication? | **No.** Serve's `Tailscale-User-Login` is required *and* a bearer secret is required |

**Serve was chosen over a directly-bound listener** because a listener on a
tailnet interface must terminate its own TLS, present its own certificate and
authenticate callers entirely on its own. Serve terminates TLS with a
Tailscale-provisioned certificate and proves caller identity before the request
reaches UsageBar, which lets the backend stay on loopback where no one but Serve
can reach it. The loopback bind is what makes the identity header trustworthy;
the two decisions are one decision.

## Resolved in Phase 8 — Mobile Lab only

The pairing and authentication questions Phase 4 left open are now answered, and
proven on hardware. Full record in
[`mobile-live-sync-pairing.md`](mobile-live-sync-pairing.md).

- **Pairing mechanism** — a one-time 256-bit code delivered by QR from the lab
  host, exchanged once at `POST /v1/pair` under a dedicated `UsageBar-Pair`
  authorization scheme. Two-minute lifetime, single use, eight-attempt ceiling,
  in memory only. **The QR never carries a long-lived credential.**
- **Long-lived token storage** — a 256-bit bearer is returned to the phone once
  and stored in its shared Keychain. The Mac retains only a SHA-256 digest, so
  there is no replayable secret at rest on the desktop.
- **Identity binding** — that bearer is bound to the digest of the
  Serve-injected Tailscale identity present at pairing time. Both factors are
  required on every request and both are compared in constant time, so a leaked
  bearer used from another tailnet identity is refused.
- **Revocation** — the host can revoke, which deletes the digests; a definitive
  `401` then makes the phone, its widgets and its controls clear their own
  credential and cache. Re-pairing rotates and revokes the previous bearer.
- **Phone-side secret storage** — unchanged from Phase 5/6:
  `WhenUnlockedThisDeviceOnly`, one shared Keychain group, no App Group. Phase 8
  adds the distinction between a *missing* item and one that is merely
  unreadable while the device is locked; only the first is revocation.
- **Polling interval and background refresh** — deliberately **none added**.
  WidgetKit timelines and `ControlValueProvider` already request values on the
  system's own schedule, and Phase 8 hardened locked and offline behaviour
  rather than introducing another clock. No `BackgroundTasks`, no APNs.

### Still deferred

- Tailscale tag design and applied grants policy — designed in
  [`mobile-transport-grants-plan.md`](mobile-transport-grants-plan.md),
  **not applied**
- **production Serve lifecycle** — who configures Serve, and whether the
  shipping app should manage it at all. In Phase 8 the mapping was configured
  externally by the checkpoint and removed afterwards; the lab host reads
  Tailscale status and never writes it.
- **production packaging and integration** — a Phase 9 question, unauthorized
- WidgetKit refresh behaviour over the VPN, beyond the locked/offline semantics
  Phase 8 established

## Security requirements this creates

Recorded in full in
[`mobile-sync-threat-model.md`](mobile-sync-threat-model.md#tailscale-specific-threats-and-assumptions).
In short: **Tailscale is a network security boundary, not permission to
serialize more data.** The schema-v1 privacy boundary is unchanged, and being on
the same tailnet is not by itself authorization to reach a UsageBar service.

**None of these protections is implemented.** This document records a decision;
no Tailscale code, configuration, tailnet, tag, auth key or policy exists.

## Implementation status

| | |
| --- | --- |
| Transport class selected | **yes** |
| Tailscale installed and authenticated | **yes** — by the owner, manually |
| HTTPS Certificates enabled | **yes** — by the owner, manually, after a machine-name privacy review |
| Tailnet, tag, auth key, OAuth client or policy created | **no** |
| Serve configured | **temporarily**, for the Phase-4 and Phase-8 smokes; removed afterwards and verified empty each time |
| Funnel configured | **no**, and never |
| Loopback listener and HTTP service | **yes** — `Sources/UsageBarSyncTransport/` |
| Wired into a desktop app | **yes** — `Sources/UsageBarMobileSyncHost/` |
| Wired into the shipping UsageBar app | **yes, off by default** — the identity gate and the preference both have to say yes |
| Serve configured *by application code* | **no** — UsageBar reads Tailscale status and never writes it |

Phase 4 was a **prototype** that no application depended on. Phase 8 wired the
transport into a separate host bundle, and Phase 9 moved it into UsageBar
itself under `local.codex.usagebar`, which is now the runtime gate. Linking the
module is still not permission to run it: a process that is not UsageBar never
opens a listener, holds a credential or offers pairing, and the preference
behind it defaults to off, so a first launch after upgrading opens nothing.

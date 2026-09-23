# Tailscale grants plan — UsageBar mobile sync

**Status:** PLAN ONLY — nothing in this document has been applied.

No grant, ACL, tag, auth key or OAuth client has been created, edited or
deleted. Phase 4 deliberately implements the *service* and leaves tailnet policy
to a separate, owner-authorized checkpoint: policy changes affect every device
on the tailnet, not just UsageBar, so they do not belong in the same change as a
prototype.

This document exists to answer the question T19 in
[`mobile-sync-threat-model.md`](mobile-sync-threat-model.md) says Phase 4 cannot
be considered complete without: *what least-privilege access rule should reach
the UsageBar sync service, and why is default tailnet connectivity not it?*

---

## Why the default posture is not acceptable

Tailscale's out-of-the-box policy is broad: every device in a tailnet can reach
every other device. Under that default, any node added for an unrelated reason —
a test VM, a friend's laptop shared into the tailnet, a device added years later
— can reach the sync service the moment it exists.

The threat model records this as **T19 — Over-broad tailnet policy**, and its
requirement is explicit: the default must be *explicitly reviewed*, never relied
on implicitly. Being on the same tailnet is not authorization to read usage data.

**T18 — Tailnet account compromise** is the sharper case. An attacker who
controls the Tailscale account can add an authorized node *inside* the overlay.
Network position alone must therefore never be sufficient.

## What the prototype already does about it

The Phase-4 service does not treat reachability as authorization. Two
independent facts are required on every request:

1. **Tailscale proved a tailnet user is calling.** Serve injects
   `Tailscale-User-Login`; the service refuses any request without it.
2. **The caller holds this run's bearer secret.** Ephemeral, ≥256 bits,
   compared in constant time.

The second factor is what survives T18: a hostile node added to a compromised
tailnet satisfies (1) and still fails (2).

The service is also bound to **loopback only**. That is what makes (1)
meaningful — identity headers are trustworthy only while Serve is the sole path
to the backend. A service on a routable interface could be called directly by
anyone on the LAN or tailnet, who would simply supply their own header value.
This mirrors Tailscale's own guidance for identity-header authentication.

## Proposed grant, when the owner authorizes policy work

Intent, in words, since the exact expression should be written against the
policy file at the time it is applied:

- **Source:** only the owner's own user identity — not `autogroup:members`, not
  a broad tag, not `*`.
- **Destination:** only the machine running UsageBar, carrying a dedicated tag
  such as `tag:usagebar-sync`, and only the single TCP port Serve terminates on.
- **Everything else:** unchanged. The grant adds one narrow path; it must not
  widen any existing rule.

Points to settle in that checkpoint, not before:

- whether the desktop is tagged, and if so who owns the tag
- whether a phone is granted by user identity or by its own tag
- how the grant is reviewed after an unrelated device is added later (**policy
  drift** is T19's residual risk)
- revocation: rotating the bearer secret is immediate and local; removing tailnet
  access is a policy edit. Both paths must exist before a phone holds a
  long-lived credential.

## Explicitly out of scope

- **Tailscale Funnel.** Locked out by
  [`mobile-transport-decision.md`](mobile-transport-decision.md) (**E**).
  Funnel would expose the service to the public internet and, notably, does
  **not** carry identity headers — the first authentication factor would silently
  vanish.
- **Auth keys and OAuth clients.** None created. Not required by the prototype.
- **Renaming devices or editing DNS settings.** Owner-only actions.
- **HTTPS certificate enablement.** A tailnet-level setting the owner enabled
  manually, reviewed separately because an issued certificate publishes its
  FQDN to public Certificate Transparency logs permanently.

## Status table

| | |
| --- | --- |
| Grant designed | **yes — in this document** |
| Grant applied | **no** |
| Tag created | **no** |
| ACL / policy file edited | **no** |
| Auth key created | **no** |
| OAuth client created | **no** |
| Funnel configured | **no** |

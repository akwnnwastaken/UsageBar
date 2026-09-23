# Mobile sync threat model — Phase 1

Security design for the UsageBar mobile sync boundary, written **before** any
transport, backend, pairing or encryption exists.

> **Design only.** Nothing in this document is implemented. No mitigation
> described here has been built, tested or deployed. Every requirement is a
> constraint on future work, not a claim about present behaviour.

Companion document: [`shared/sync-schema/README.md`](../../shared/sync-schema/README.md).

---

## Transport Decision — RESOLVED

> **Transport class selected after Phase 1: a direct desktop service over a
> Tailscale private overlay.** Selected by the owner on 2026-09-22. The full
> decision record is [`mobile-transport-decision.md`](mobile-transport-decision.md).

Tailscale is the **connectivity layer**, not a backend: the desktop answers for
itself over the tailnet and no usage data rests on third-party infrastructure.

**The data contract did not change.** Schema v1 was designed to be transport
neutral, and selecting a transport confirmed that design rather than revising
it — no payload field was added, removed or reinterpreted.

### Candidate analysis (Phase 1, superseded)

The following comparison is **retained as historical design context**. It
records what was weighed before the decision and is no longer a live menu.
Candidate B was selected; A and C were not.

**No transport or backend architecture was selected in Phase 1.** The owner
deferred the decision at that time. The data contract was designed so that none
of the candidates below would require redesigning the usage payload.

#### Candidate A — direct local desktop server *(not selected)*

The phone connects directly to the running UsageBar desktop, potentially over
the LAN with local discovery.

- fewer infrastructure components; nothing operated by anyone else
- the desktop must be reachable at the moment the phone asks
- sleep, shutdown or leaving the network defeats retrieval
- requires network discovery and its own authentication
- widget refresh happens on the OS's schedule, which may not coincide with the
  desktop being awake and on the same network

#### Candidate B — direct private-network desktop server *(SELECTED — Tailscale)*

The phone reaches the running desktop through a private overlay network such as
Tailscale or an equivalent technology.

- avoids exposing a public port
- works away from the home LAN
- requires installing and maintaining a third-party or self-hosted overlay, and
  assumes an account or key infrastructure for it
- the desktop must still be awake and reachable
- adds a dependency whose own trust properties must be reviewed

#### Candidate C — encrypted relay / mailbox *(not selected; see the decision record)*

The desktop publishes an encrypted current snapshot; the phone retrieves it
later. The relay need not be able to read plaintext.

- the phone can retrieve the latest snapshot while the desktop is offline or
  asleep — the only candidate that survives a sleeping Mac
- requires operating external infrastructure
- encryption and key lifecycle become mandatory rather than optional
- introduces storage, retention and deletion obligations
- adds an operator to the threat model even when it cannot read plaintext

*(End of the superseded Phase-1 comparison.)*

The owner resolved this ahead of the originally planned gate. Candidate B was
chosen, accepting its stated tradeoff — **the desktop must be awake and
reachable for fresh data** — in exchange for keeping usage data off third-party
infrastructure entirely. Candidate C's advantage, surviving a sleeping desktop,
was judged not worth operating external infrastructure and a mandatory key
lifecycle.

Selecting a transport **class** leaves the details listed in the decision record
open; they belong to Phase 4.

---

## Assets

| Asset | Where it lives | Sensitivity |
| --- | --- | --- |
| Provider credentials (Codex / Claude auth) | desktop only, inside each provider's own CLI | **critical** — never enters the sync boundary under any design |
| Raw provider output | desktop process memory, transiently | high — may contain account detail, paths, arbitrary text |
| Sanitized quota data (the snapshot) | desktop → transport → phone | low-moderate — reveals working patterns and activity times |
| Pairing / authentication secrets | desktop and phone keystores | **critical** — grants read access to the snapshot stream |
| Source / device identifiers | not present in v1 | moderate if ever introduced — correlatable across time |
| Cached mobile snapshot | phone, shared App Group container | low-moderate — same as the snapshot, but persists at rest |

## Trust boundaries

1. **Provider → desktop UsageBar.** Untrusted text crosses here. Provider output
   is parsed, never echoed.
2. **Desktop parser → sanitized snapshot builder.** The privacy boundary. Only
   schema-approved fields may cross; this is where raw material is dropped.
3. **Desktop → transport.** The confidentiality and authenticity boundary.
4. **Transport → iPhone.** The validation boundary. Everything arriving is
   hostile until validated.
5. **iPhone app → App Group / widget extension.** A future at-rest boundary
   shared with extensions that run under different lifecycles.

---

## Threats and failure cases

Seventeen cases analysed. Each carries a Phase-1 requirement, anything that must
wait for the transport decision, and the risk that remains.

### T1 — Malicious network observer

- **Threat:** an on-path observer reads snapshots in transit.
- **Impact:** discloses quota levels, reset times and, over time, working hours
  and activity patterns. No credentials, since none are transmitted.
- **Phase-1 requirement:** the contract carries no credentials or raw output, so
  interception cannot yield secrets. All transport must be confidential;
  cleartext transport is forbidden under every candidate.
- **Deferred:** the specific protocol, cipher suite and certificate or key
  validation rules.
- **Residual risk:** traffic timing and payload size still leak coarse activity
  signals even when encrypted.

### T2 — Malicious or compromised relay operator (Candidate C only)

- **Threat:** whoever runs a relay reads or retains stored snapshots.
- **Impact:** long-term disclosure of usage patterns; retention outlives any
  single session.
- **Phase-1 requirement:** if a relay is ever chosen, it must be treated as
  untrusted infrastructure — end-to-end encrypted so the relay handles
  ciphertext only, with bounded retention.
- **Deferred:** encryption scheme, key exchange, retention period, deletion
  guarantees, operator accountability.
- **Residual risk:** even blind to plaintext, a relay observes upload cadence,
  payload size and client IP addresses.

### T3 — Unauthorized device on the same LAN

- **Threat:** another device on the network reaches a local desktop listener.
- **Impact:** unauthenticated read of the snapshot stream.
- **Phase-1 requirement:** every remote reader must be authenticated and paired.
  Unauthenticated read access is forbidden; so is unauthenticated write access.
  "Same network" is never sufficient authorization.
- **Deferred:** the pairing protocol and how a listener binds and advertises.
- **Residual risk:** a listener's existence is discoverable even when it refuses
  access, revealing that UsageBar runs on that host.

### T4 — Compromised pairing token

- **Threat:** a pairing secret leaks through a screenshot, backup, log or shared
  device.
- **Impact:** an attacker reads snapshots indefinitely, silently.
- **Phase-1 requirement:** pairing secrets must never appear in logs, diagnostic
  bundles, crash reports or Git. Revocation must eventually be possible — a
  design that cannot revoke a paired reader is not acceptable.
- **Deferred:** token format, lifetime, rotation, QR encoding, revocation UX.
- **Residual risk:** undetected compromise persists until the user notices and
  revokes; without a device list there is nothing to notice.

### T5 — Replayed old snapshot

- **Threat:** an attacker re-serves a previously valid snapshot.
- **Impact:** the phone shows stale quota as current — e.g. plenty remaining
  when the user is nearly exhausted.
- **Phase-1 requirement:** replay must be **detectable from the payload
  itself**. `generatedAt` orders documents and `measuredAt` dates each reading,
  so a consumer can reject a snapshot older than one it already holds and can
  age out readings regardless of what the transport claims.
- **Deferred:** cryptographic anti-replay (nonces, signed counters, freshness
  challenges) belongs to the transport.
- **Residual risk:** a first-contact replay has no prior snapshot to compare
  against; only `measuredAt` age bounds it.

### T6 — Tampered snapshot

- **Threat:** values are modified in transit.
- **Impact:** wrong numbers displayed; a doctored reset time could mislead the
  user into exhausting quota.
- **Phase-1 requirement:** strict schema validation bounds what tampering can
  express — percentages outside 0–100, malformed timestamps, unknown properties
  and duplicate identities all fail closed. Integrity itself must be guaranteed
  by the transport.
- **Deferred:** signature or AEAD scheme and key management.
- **Residual risk:** a tampered but schema-valid payload (e.g. 90 instead of 9)
  is indistinguishable without cryptographic integrity.

### T7 — Malformed or oversized snapshot

- **Threat:** hostile input aimed at the parser — deep nesting, huge arrays,
  enormous strings, decompression bombs.
- **Impact:** memory exhaustion or crash. A crash inside a widget extension is
  especially disruptive given its tight resource budget.
- **Phase-1 requirement:** **message size must be bounded** and the bound
  enforced *before* parsing. The schema bounds structure independently:
  `providers` ≤ 16, `windows` ≤ 16 per provider, every string length-capped,
  every integer range-capped, no recursive definitions — so a valid snapshot has
  a small, predictable maximum size. Schema validation must happen **before**
  any use of the data. Malformed data fails closed; the previous cached snapshot
  is kept rather than replaced with garbage.
- **Deferred:** the exact byte ceiling and the transport's own framing limits.
- **Residual risk:** the JSON parser itself remains attack surface before schema
  validation can run.

### T8 — Stolen or lost iPhone

- **Threat:** physical possession of the phone.
- **Impact:** access to the cached snapshot and to any stored pairing secret —
  which is the real prize, since it grants ongoing access.
- **Phase-1 requirement:** the cache holds only sanitized data, never
  credentials. Pairing secrets must live in the platform keystore, not in the
  App Group container or user defaults. Revocation must be possible from the
  desktop side without the phone's cooperation.
- **Deferred:** keystore selection, protection class, biometric gating, whether
  widget rendering can proceed while locked.
- **Residual risk:** data already rendered on a Lock Screen widget is visible
  without unlocking — an intentional product tradeoff to be decided knowingly.

### T9 — Stolen or lost desktop

- **Threat:** physical possession of the Mac or PC.
- **Impact:** far broader than sync — the provider credentials themselves are
  there.
- **Phase-1 requirement:** out of scope for the sync boundary, but sync must not
  *widen* it: no new plaintext secret store, no long-lived exported credential.
- **Deferred:** whether pairing state should be revocable from the phone side.
- **Residual risk:** full-disk encryption and OS account security remain the
  user's responsibility; sync design cannot compensate.

### T10 — Accidental debug logging

- **Threat:** a developer logs the payload, the pairing secret or a provider
  response while diagnosing sync.
- **Impact:** secrets reach system logs, crash reports or a support bundle —
  durable, copyable and easily shared.
- **Phase-1 requirement:** debug output must never contain payload secrets or
  pairing material. Secrets must not enter Git. Any future diagnostic surface
  must redact by construction rather than by reviewer discipline.
- **Deferred:** the redaction helper and its tests, alongside the first code that
  could log anything.
- **Residual risk:** a determined developer can always print a value; process
  discipline is the only real control.

### T11 — Accidental inclusion of raw provider output

- **Threat:** a future change passes a raw Codex response or Claude screen text
  into the snapshot, directly or inside a debug field.
- **Impact:** the exact privacy failure the contract exists to prevent —
  arbitrary provider text, possibly including account or path detail, crossing
  to the phone and persisting in its cache.
- **Phase-1 requirement:** `additionalProperties: false` at every object
  boundary means any unexpected field fails validation rather than riding along.
  The prohibited-data list is normative. The snapshot builder must construct
  fields explicitly and must never serialise an internal model wholesale.
- **Deferred:** a build-time or test-time check asserting the builder's output
  contains no prohibited property names.
- **Residual risk:** a field added *deliberately* and *named innocuously* would
  pass both schema and review. Field-by-field justification exists to make that
  visible.

### T12 — Stale desktop

- **Threat:** the desktop runs but a provider keeps failing, so a retained
  reading grows old while snapshots keep being generated.
- **Impact:** the phone shows confidently wrong numbers.
- **Phase-1 requirement:** this is precisely why `measuredAt` is per provider and
  never advances on a failed cycle. The phone derives freshness from
  `measuredAt`, never from `generatedAt`.
- **Deferred:** the staleness threshold and how the widget indicates it —
  deliberately client presentation policy, not wire data.
- **Residual risk:** a consumer that ignores `measuredAt` reintroduces the bug;
  the contract can only make the correct thing available, not compulsory.

### T13 — Clock skew

- **Threat:** desktop and phone clocks disagree, or a timestamp is far future or
  far past.
- **Impact:** freshness and replay logic misjudge; a future-dated snapshot could
  look permanently fresh or a valid one be discarded.
- **Phase-1 requirement:** consumers **must not trust transport-provided
  timestamps blindly**. Timestamps must be validated for format *and*
  reasonableness — a `measuredAt` meaningfully in the future, or a
  `measuredAt` later than `generatedAt`, is a defective snapshot.
- **Deferred:** the tolerance window and whether a trusted time source is used.
- **Residual risk:** without a trusted clock, skew can only be bounded, not
  eliminated.

### T14 — Server or relay outage (Candidate C only)

- **Threat:** the relay is unavailable.
- **Impact:** the phone cannot retrieve updates.
- **Phase-1 requirement:** **mobile sync is best-effort.** The phone must degrade
  to its cached snapshot, labelled by `measuredAt`, rather than showing an error
  state or blank widget. Crucially, **desktop sync failure must never impair
  normal desktop UsageBar behaviour** — the menu bar keeps working regardless.
- **Deferred:** retry, backoff and any offline queue.
- **Residual risk:** an extended outage silently yields an ever-staler widget;
  only the freshness indicator reveals it.

### T15 — Desktop asleep or offline

- **Threat:** the Mac sleeps; the phone refreshes a widget anyway.
- **Impact:** under a direct-server transport (A or B) no data is retrievable at
  all — this is the single sharpest differentiator between the candidates.
- **Phase-1 requirement:** the contract is unaffected — a cached snapshot stays
  meaningful and self-dating because `measuredAt` travels with it. The mobile
  cache must **never** become the provider authority; it is a display copy.
- **Deferred:** the entire question, by design. This is the central input to the
  Transport Decision Gate.
- **Residual risk:** whichever transport is chosen, some window exists where the
  phone shows data older than the user assumes.

### T16 — Downgrade to an older schema

- **Threat:** an attacker or a buggy sender supplies `schemaVersion: 1` to a
  consumer that expects stricter, later semantics; or a v1 consumer receives a
  v2 payload.
- **Impact:** validation relaxes to the weaker version's rules, potentially
  admitting a field a later version tightened.
- **Phase-1 requirement:** `schemaVersion` is a hard gate, not a hint. A
  consumer validates against the exact version it declares support for and
  **refuses** anything else — a v1 consumer must reject `schemaVersion: 2`
  rather than best-effort parse it. Unknown properties are a hard failure within
  a version, so a downgrade cannot smuggle extra fields.
- **Deferred:** whether the version should additionally be bound into the
  transport's authenticated data so it cannot be altered independently.
- **Residual risk:** without integrity protection, `schemaVersion` is itself
  tamperable; this is only fully solved at the transport layer.

### T17 — Future multi-device confusion

- **Threat:** two desktops both publish snapshots; the phone cannot tell them
  apart and shows a mixture, or alternates between them.
- **Impact:** silently wrong numbers, with no visible symptom.
- **Phase-1 requirement:** v1 is explicitly **single-source**. It carries no
  device identity, so multi-device is not accidentally half-supported — a
  consumer cannot mistakenly believe it can disambiguate.
- **Deferred:** if multi-device is ever wanted, an opaque `sourceInstanceID`
  must be **randomly generated**, never derived from hostname, username,
  hardware serial, MAC address or provider account, and must be safe to rotate.
  Its correlation risk must be reviewed before introduction.
- **Residual risk:** a user who pairs two desktops to one phone before that
  design exists gets undefined behaviour. The single-source assumption must be
  enforced at pairing time.

---

## Tailscale-specific threats and assumptions

Added after the owner selected a Tailscale private overlay. These sit alongside
T1–T17, which all still apply: **Tailscale is a network security boundary, not
permission to serialize more data.** The schema-v1 privacy boundary is
unchanged, provider credentials and raw output still never leave the desktop,
and none of the mitigations below is implemented.

### T18 — Tailnet account compromise

- **Threat:** an attacker who can add or control an authorized tailnet device
  attempts to reach the UsageBar sync service. Compromising the Tailscale
  account is enough to place a hostile node *inside* the trusted overlay.
- **Impact:** the network boundary is bypassed entirely. If reachability alone
  were treated as authorization, that node would read snapshots freely.
- **Phase-1/2 requirement:** the future grants/access policy **and** the
  application-level authorization decision must be reviewed explicitly, as one
  question rather than two. "Is Tailscale identity sufficient authentication, or
  does UsageBar add a second layer?" is deliberately still open, and it must be
  answered before Phase 4 is complete — not settled by accident.
- **Deferred:** the authentication mechanism, pairing, and revocation.
- **Residual risk:** an attacker holding the tailnet account may also be able to
  alter the policy that would otherwise restrain them.

### T19 — Over-broad tailnet policy

- **Threat:** a default or permissive tailnet ACL lets every device reach the
  future service. Tailscale's out-of-the-box posture is broad connectivity.
- **Impact:** more devices than intended — including ones added for unrelated
  reasons — can read usage data.
- **Phase-1/2 requirement:** a **least-privilege** access rule allowing only the
  necessary source device or user to reach only the UsageBar sync service.
  **Prefer Tailscale Grants** for new access-control policy rather than broad
  allow-all rules. The default broad connectivity must be **explicitly
  reviewed**, never relied on implicitly. Phase 4 cannot be considered complete
  without this.
- **Deferred:** tag design, grant expressions, machine naming.
- **Residual risk:** policy drift — a rule loosened later for an unrelated
  device silently widens access to UsageBar too.

### T20 — Tailscale unavailable or disconnected

- **Threat:** the overlay is down, logged out, key-expired, or the phone has it
  disabled.
- **Impact:** the phone cannot reach the desktop at all.
- **Phase-1/2 requirement:** the **last validated mobile cache survives** and
  continues to display, labelled with its age. **Desktop UsageBar is
  unaffected** — the menu bar, tray and history keep working, because sync
  failure must never impair normal desktop behaviour.
- **Deferred:** retry and backoff behaviour; how the UI signals disconnection.
- **Residual risk:** a user may not notice the overlay is down and may read an
  old number as current if the age indicator is too subtle.

### T21 — Desktop asleep or offline

- **Threat:** the Mac sleeps; the phone refreshes anyway.
- **Impact:** no fresh remote read is possible. This is the **accepted
  tradeoff** of choosing a direct overlay over a relay, not a defect.
- **Phase-1/2 requirement:** the mobile UI **must use `measuredAt` to expose age
  and staleness**. The contract already makes this possible: a cached snapshot
  is self-dating, so a retained reading cannot masquerade as fresh.
- **Deferred:** the staleness threshold and its presentation — client policy,
  deliberately not wire data.
- **Residual risk:** widget refresh windows and desktop sleep schedules may
  rarely coincide, so data can be routinely older than a user assumes.

### T22 — Tailnet names, addresses and ports as payload contamination

- **Threat:** transport metadata — a `100.x` address, a MagicDNS name, a machine
  name, a port, a tailnet identifier or a node key — is added to the snapshot
  because it is conveniently available at the send site.
- **Impact:** the payload stops being transport-neutral and starts carrying
  stable device identifiers. A MagicDNS machine name is frequently derived from
  the user's own name or their hardware — exactly the personal metadata the
  contract excludes — and it would persist in the phone's cache.
- **Phase-1/2 requirement:** **Tailscale IPs, hostnames, MagicDNS names and
  ports must never enter `UsageSyncSnapshot`.** They are transport metadata and
  belong to the transport layer. The typed Swift model enforces this
  structurally: it has no field that could hold one, and a test asserts the
  encoded key set contains no such property.
- **Deferred:** nothing. This one is in force now.
- **Residual risk:** a future schema revision could add such a field
  deliberately; the field-by-field justification in the schema README exists to
  make that visible in review.

### Standing assumption

The app must still validate every received snapshot as **untrusted structured
input**, exactly as T6 and T7 require. Arriving over a private overlay does not
make a payload trustworthy: it only narrows who can send one.

---

## Phase-8 threats — live data, pairing and long-lived authentication

Phase 8 is the first checkpoint in which real quota data crosses to a phone, and
the first with a credential that outlives a single run. These are the threats
that arrive with it.

### T23 — Pairing QR photographed or observed

A QR is readable by anyone who can see the Mac's screen, and a phone camera
across a room is enough.

**Mitigation.** The QR carries no durable credential. It holds a version, a
hostname and a **one-time** code that buys exactly one credential issuance; the
long-lived bearer is generated only during the exchange and never appears in the
payload. The session expires after two minutes, survives one success, and is
closed by eight failures, a new session, a closed window or a process restart.

**Residual risk.** Someone who photographs the code *and* is already on the
tailnet *and* redeems it within the window, before the owner's own phone does,
would be paired instead. The owner sees this immediately — their own scan fails
— and can revoke and re-pair. Narrowing it further would mean a pairing flow the
owner cannot complete at walking pace.

### T24 — Pairing-code replay

**Mitigation.** The check and the consume share one critical section, so two
simultaneous requests carrying the same valid code cannot both be issued a
credential. A consumed session is gone; a replay is refused like any other bad
code. Proven under a 64-way concurrent redemption test and on hardware.

### T25 — Brute force during the pairing window

**Mitigation.** 256 bits of CSPRNG entropy, an attempt ceiling of eight, a
two-minute lifetime and constant-time comparison. An online guessing attempt
gets one short burst, not an unlimited one, and the ceiling closes the window
rather than merely rejecting the attempt.

### T26 — Leaked long-lived bearer

**Mitigation.** The bearer alone is not sufficient. Every request must also
carry a Serve-injected Tailscale identity whose digest matches the one recorded
at pairing time, so a token used from a different tailnet identity fails. This
is what keeps **T18** — a hostile node inside a compromised tailnet — from being
enough on its own.

**Residual risk.** A bearer leaked *together with* control of the paired
identity is sufficient. That is the same compromise as owning the account, and
the answer is revocation.

### T27 — Credential at rest on the Mac

**Mitigation.** The Mac does not retain the raw bearer, and has no field that
could. It stores SHA-256 digests of the bearer and of the normalized identity in
a lab-only Keychain service with `WhenUnlockedThisDeviceOnly`. A Keychain dump,
a backup or a stolen laptop yields nothing replayable. The raw Tailscale login —
an email address — is never persisted, echoed or logged.

### T28 — Rotation and re-pairing

**Mitigation.** Pairing replaces the stored record, so a new pairing revokes the
previous phone's credential. Phase 8 proves this both ways: the old bearer stops
working the moment a new one is issued.

### T29 — Desktop restart

**Mitigation.** The digests persist and the listener restarts, so a paired phone
keeps working without re-pairing. The pairing *session* deliberately does not
survive a restart — it lives in memory only.

### T30 — Keychain temporarily unavailable while the device is locked

The failure this one guards against is self-inflicted: a widget evaluated while
the phone is locked reads the Keychain, gets nothing, concludes the user
disconnected, and deletes their data.

**Mitigation.** A read has three outcomes, not two. `missing` is revocation;
`temporarilyUnavailable` keeps the connection, keeps the cache, shows the last
validated reading, and makes **no** network request — because an unauthenticated
fetch would be answered 401, which the surface would then correctly treat as
revocation. The protection class is unchanged; only the interpretation is.

**Residual risk.** A genuinely deleted item that reports as unavailable would
delay revocation until the next readable evaluation. The server side is the
authoritative revocation path and is unaffected.

### T31 — Server-side revocation with a populated phone cache

**Mitigation.** A definitive `401` is the one failure that revokes locally. The
app and the extension each clear the shared connection and their own cache and
fall back to not-configured, so **Revoke Paired iPhone** removes the quota from
every surface at its next evaluation. Every other failure leaves both alone.

### T32 — Stale phone, widget or control cache

**Mitigation.** Unchanged and reinforced: freshness is `measuredAt` per
provider, never `generatedAt`; a retained stale desktop reading keeps its
original measurement time; a failed refresh never blanks a good reading and
never advances its age.

### T33 — Mobile Sync running when the user never asked for it

**Mitigation.** Two independent gates, both of which must say yes. The bundle
identifier must be exactly `local.codex.usagebar` — a single permitted value,
so a test runner, an unbundled build or any other application that links the
module never opens a listener, holds a credential or offers pairing. And the
`MobileSyncEnabled` preference must be true; absent reads as false, so a first
launch after upgrading opens no listener, runs no Tailscale command and creates
no credential.

The standalone **UsageBar Mobile Host 0.1.0** that this feature came from used a
different bundle identifier, a different preference key and a different Keychain
service. None of them is reused and nothing migrates, so a phone paired with
that host is not paired with UsageBar; the user pairs once more. Phase 9
verified the installed release build's executable hash and every pre-existing
preference unchanged across the entire live run.

### T34 — Accidental live-data logging

Real quota data now exists on a network path, so a stray log line is no longer
harmless.

**Mitigation.** Refusal bodies are a status number. No snapshot, hostname,
identity, digest or credential is logged on either side. The Tailscale reader
discards stderr and any stdout that is not JSON. No live value, timestamp,
hostname or digest from the physical run is recorded in this repository.

---

## Transport-independent security requirements

These hold under **every** candidate transport and are the standing constraints
on all later phases.

**Data boundary**

1. Provider credentials never leave the desktop.
2. Only the sanitized, schema-approved snapshot crosses the sync boundary.
3. Raw provider output never crosses it, in any field, including diagnostics.

**Access control**

4. Every remote reader is authenticated and paired.
5. Unauthenticated read access is forbidden.
6. Unauthenticated write access is forbidden.
7. Revocation must eventually be possible.

**Payload integrity**

8. Replay and stale snapshots must be detectable.
9. Malformed data fails closed; the last good cache is retained.
10. Message size is bounded, and the bound is enforced before parsing.
11. Schema validation happens before the data is used.
12. Timestamps are never trusted blindly; format and reasonableness are both
    validated.

**Resilience**

13. Desktop sync failure never impairs normal desktop UsageBar behaviour.
14. Mobile sync is best-effort.
15. The mobile cache never becomes the provider authority.

**Hygiene**

16. Pairing secrets never appear in logs or diagnostics.
17. Secrets never enter Git.
18. Debug output never contains payload secrets.

The exact authentication protocol is **not** decided here.

---

## Decision record

### Locked in Phase 1

- **Sanitized usage snapshot semantics** — providers, windows, headline value,
  and their meanings.
- **Prohibited data** — credentials, raw provider output, local machine detail,
  identity, transport configuration.
- **Timestamp semantics** — `generatedAt` for the document, `measuredAt` per
  provider reading; freshness derives from `measuredAt` only.
- **Provider and window representation** — `connected`/`collecting` as two
  independent facts; five window kinds with `duration` and `unknown` as
  forward-compatibility escape hatches; `scope` slug for model-qualified weekly
  limits.
- **Schema compatibility rules** — integer `schemaVersion`, strict unknown-field
  rejection within a version, additive evolution across versions, product
  version excluded from the wire.
- **Transport-independent security requirements** — the eighteen above.
- **No history in v1.**
- **No issue codes in v1.**
- **No device identity in v1.**

### Resolved after Phase 1

- **transport class — a direct desktop service over a Tailscale private
  overlay**, selected by the owner on 2026-09-22
  (see [`mobile-transport-decision.md`](mobile-transport-decision.md));
  Tailscale Funnel and any cloud relay are excluded by that decision

### Resolved in Phase 8 (Mobile Lab)

- **pairing protocol** — a one-time 256-bit code delivered by QR, exchanged at
  `POST /v1/pair` under its own `UsageBar-Pair` authorization scheme, single-use,
  two-minute lifetime, eight-attempt ceiling, never persisted
- **long-lived token storage** — a 256-bit bearer returned to the phone once and
  retained by the Mac only as a SHA-256 digest
- **identity binding** — the bearer is bound to the digest of the Serve-injected
  Tailscale identity that performed the pairing; both factors are required and
  both are compared in constant time
- **revocation** — server-side revoke deletes the digests; a definitive `401`
  makes the phone, its widgets and its controls forget locally
- **locked-Keychain semantics** — temporary unavailability is not revocation
- **background refresh** — none added; WidgetKit and `ControlValueProvider`
  scheduling remains system-controlled

### Deferred

- production Serve lifecycle and who configures it
- production packaging and integration
- optional application of the designed Tailscale grants
- MagicDNS vs a direct Tailscale address for any future non-Serve path
- Bonjour or any local discovery
- Cloudflare or any hosting provider
- database or KV storage choice
- APNs or any push mechanism
- QR format
- token format
- server retention policy
- device revocation UX
- multi-desktop source selection
- mobile-visible issue codes
- history synchronization

**Nothing in the deferred list may be implemented before the Transport Decision
Gate, and nothing in it is implied by this schema.**

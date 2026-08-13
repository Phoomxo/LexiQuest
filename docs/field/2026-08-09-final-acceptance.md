# LexiQuest final acceptance

**Recorded:** 2026-08-13

**Decision:** **NOT READY**

**Verification source:** `4e4b398e5dc19a29a4f81953e16b084bfe0400d3`

**Signed artifact source:** `4e4b398e5dc19a29a4f81953e16b084bfe0400d3`

**Signed artifact SHA-256:**
`D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A`

The current +14 APK is correctly signed and locally verified, but release
acceptance is fail-closed. Required physical-device, provider-console,
private-channel, cost, beta-operations, and owner-approval evidence is absent.
No post-package product-source mismatch exists; the unresolved external rows
alone remain sufficient to block acceptance. No release, upload, distribution,
or publication is authorized by this record.

## Acceptance matrix

Only `pass`, `fail`, `blocked-external`, and `not-applicable` are used.

| Gate | Status | Source SHA | Artifact SHA-256 | Command/evidence | Owner |
|---|---|---|---|---|---|
| Frozen signed package identity | pass | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Internal APK checkpoint plus independent `verify-field-package.ps1`: one pinned signer, package `com.lexiquest.app`, version `1.0.0+14`, build ID `4e4b398e5dc1`, and pinned model provenance | Engineering |
| Frozen source/artifact identity | pass | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | The APK, release manifest, and clean source share one commit; only declared final-metadata documents follow it | Engineering |
| Product completion gate | pass | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | `tool/cli/verify-product-completion.ps1` passed every phase on the frozen source, including three sequential production-shell journeys, emulators, debug APK, and model integrity | Engineering |
| Secret scan | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Gitleaks scanned 571 commits with no leaks | Engineering |
| Six-file dependency vulnerability gate | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Windows-safe explicit-lock `tool/cli/verify-osv-locks.ps1` passed with scoped documented policies | Engineering |
| Orphan production visibility | pass | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Runtime ledger and production invocation architecture gate show every `orphan` row has no production caller or visible entry | Engineering |
| Visible local feature invocation | pass | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Production feature contract and Task 9 production-shell journeys prove local invocation, persistence/restart, controls, and host-fake unavailable behavior | Engineering |
| Visible device/provider feature certification | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Object Scanner, Speech Practice, and AI Tutor remain visible `limited` capabilities without exact-artifact physical/provider certification; host fakes do not satisfy this gate | Field owner |
| Low-tier Android device | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | No record; ADB and Windows PnP exposed no Android interface, so the available device's tier could not be established | Field owner |
| Mid-tier Android device | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | No record; one physical device may never be reused as another tier | Field owner |
| High-tier Android device | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | No record; one physical device may never be reused as another tier | Field owner |
| App Check configuration and signed-release traffic | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Configuration, valid-traffic, and controlled-enforcement source exports are absent | Firebase owner |
| Hosted asset links and cloud kill switch | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Hosted verification and controlled drill source exports are absent | Cloud owner |
| Central 0-100 THB/month cost target | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Current measured project-total cost (or verified no-billing zero), exact 100 THB ceiling, 50/80/100 alerts, and content-addressed billing evidence are absent; alerts alone cannot pass | Billing owner |
| Private feedback and support channels | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Evidence shell contains pending references only | Beta owner |
| Research protocol | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Approved private protocol reference is absent | Research owner |
| Beta operations and rollback drill | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Mandatory cohort, consent, crash-free, sync, issue, provider-cost/download, owner-decision, and shared-identity rollback/kill-switch source exports are absent | Beta owner |
| Exact-hash owner smoke test and approval | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Approval flag, timestamp, and private evidence reference are absent | Repository owner |
| MaxPlus advisory review | blocked-external | `4e4b398e5dc19a29a4f81953e16b084bfe0400d3` | not-applicable | Unavailable after prior `invalidKey`; not retried. Local read-only review was used and Codex Security was not invoked | External analysis service |
| Publication or distribution | not-applicable | not-applicable | `D455CD3FB6EBEB122F4CE84297195774480B59DFF795B05AE66644D0B392343A` | Explicitly outside current authorization; no upload, push, publication, release, or distribution occurred | Repository owner |

## Decision rationale

The local gates establish that the source and internal package are suitable for
controlled evidence collection. They do not establish field certification.
The external rows above are mandatory. The
v2 verifier rejects free-form references, stale or out-of-order timestamps,
unsigned, untrusted, or unresolved content-addressed receipts, mutable claims
that differ from their signed payloads, emulator/debug collector markers,
missing beta/rollback records, and unknown or over-policy central cost. Local
integrity checks make accidental or unattributed synthetic substitution fail;
they do not prove that a dishonest authorized evidence issuer performed a real
physical test. Because mandatory rows are `fail` or `blocked-external`, the
only truthful final decision is **NOT READY**.

The next acceptable state transition is to reconnect and authorize the one
available Android device, collect only its measured tier, obtain the other two
distinct tiers, and collect the provider/cost/beta/rollback/owner records
against this exact package. Then rerun the fail-closed field verifier and issue
a new acceptance record. This document does not authorize distribution.

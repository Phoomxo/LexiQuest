# LexiQuest final acceptance

**Recorded:** 2026-08-13

**Decision:** **NOT READY**

**Verification source:** `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1`

**Signed artifact source:** `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1`

**Signed artifact SHA-256:**
`3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C`

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
| Frozen signed package identity | pass | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Internal APK checkpoint plus independent `verify-field-package.ps1`: one pinned signer, package `com.lexiquest.app`, version `1.0.0+14`, build ID `c55f7bb13705`, and pinned model provenance | Engineering |
| Frozen source/artifact identity | pass | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | The APK, release manifest, and clean source share one commit; only declared final-metadata documents follow it | Engineering |
| Product completion gate | pass | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | `tool/cli/verify-product-completion.ps1` passed every phase on the frozen source, including three sequential production-shell journeys, emulators, debug APK, and model integrity | Engineering |
| Secret scan | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Gitleaks scanned 571 commits with no leaks | Engineering |
| Six-file dependency vulnerability gate | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Windows-safe explicit-lock `tool/cli/verify-osv-locks.ps1` passed with scoped documented policies | Engineering |
| Orphan production visibility | pass | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Runtime ledger and production invocation architecture gate show every `orphan` row has no production caller or visible entry | Engineering |
| Visible local feature invocation | pass | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Production feature contract and Task 9 production-shell journeys prove local invocation, persistence/restart, controls, and host-fake unavailable behavior | Engineering |
| Visible device/provider feature certification | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Object Scanner, Speech Practice, and AI Tutor remain visible `limited` capabilities without exact-artifact physical/provider certification; host fakes do not satisfy this gate | Field owner |
| Low-tier Android device | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | No record; ADB and Windows PnP exposed no Android interface, so the available device's tier could not be established | Field owner |
| Mid-tier Android device | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | No record; one physical device may never be reused as another tier | Field owner |
| High-tier Android device | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | No record; one physical device may never be reused as another tier | Field owner |
| App Check configuration and signed-release traffic | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Configuration, valid-traffic, and controlled-enforcement source exports are absent | Firebase owner |
| Hosted asset links and cloud kill switch | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Hosted verification and controlled drill source exports are absent | Cloud owner |
| Central 0-100 THB/month cost target | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Current measured project-total cost (or verified no-billing zero), exact 100 THB ceiling, 50/80/100 alerts, and content-addressed billing evidence are absent; alerts alone cannot pass | Billing owner |
| Private feedback and support channels | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Evidence shell contains pending references only | Beta owner |
| Research protocol | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Approved private protocol reference is absent | Research owner |
| Beta operations and rollback drill | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Mandatory cohort, consent, crash-free, sync, issue, provider-cost/download, owner-decision, and shared-identity rollback/kill-switch source exports are absent | Beta owner |
| Exact-hash owner smoke test and approval | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Approval flag, timestamp, and private evidence reference are absent | Repository owner |
| MaxPlus advisory review | blocked-external | `c55f7bb13705256ecf39b9ce62ac524d0a1ad8f1` | not-applicable | Unavailable after prior `invalidKey`; not retried. Local read-only review was used and Codex Security was not invoked | External analysis service |
| Publication or distribution | not-applicable | not-applicable | `3C699B0237789E30DFB32429BE72415B8D0A4CA1CC5F0AD1C7FEAED2BB7B312C` | Explicitly outside current authorization; no upload, push, publication, release, or distribution occurred | Repository owner |

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

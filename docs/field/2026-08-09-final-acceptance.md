# LexiQuest final acceptance

**Recorded:** 2026-08-13

**Decision:** **NOT READY**

**Verification source:** `555b0b9343ce78cbf04692f048bf049d90fb559f`

**Signed artifact source:** `c199d501adb8b83d0a1b9e7bd529c9f123f168f9`

**Signed artifact SHA-256:**
`EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158`

The internal APK is correctly signed and locally verified, but release
acceptance is fail-closed. Required physical-device, provider-console,
private-channel, cost, beta-operations, and owner-approval evidence is absent.
The field verifier also rejects the post-package source mismatch before
evaluating external evidence. No release, upload, distribution, or publication
is authorized by this record.

## Acceptance matrix

Only `pass`, `fail`, `blocked-external`, and `not-applicable` are used.

| Gate | Status | Source SHA | Artifact SHA-256 | Command/evidence | Owner |
|---|---|---|---|---|---|
| Frozen signed package identity | pass | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Internal APK checkpoint plus independent `verify-field-package.ps1`: one pinned signer, package `com.lexiquest.app`, version `1.0.0+13`, build ID `c199d501adb8`, and pinned model provenance | Engineering |
| Frozen source/artifact identity | fail | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | The current branch contains post-package verifier and integration-harness changes outside the final-metadata allowlist. A new signed package from one frozen SHA is required | Engineering |
| Product completion gate | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | `tool/cli/verify-product-completion.ps1` passed every phase on this source, including three sequential production-shell journeys, emulators, debug APK, and model integrity. This source-only result is not attributed to the older signed APK | Engineering |
| Secret scan | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Gitleaks scanned 571 commits with no leaks | Engineering |
| Six-file dependency vulnerability gate | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Windows-safe explicit-lock `tool/cli/verify-osv-locks.ps1` passed with scoped documented policies | Engineering |
| Orphan production visibility | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Runtime ledger and production invocation architecture gate show every `orphan` row has no production caller or visible entry | Engineering |
| Visible local feature invocation | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Production feature contract and Task 9 production-shell journeys prove local invocation, persistence/restart, controls, and host-fake unavailable behavior | Engineering |
| Visible device/provider feature certification | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Object Scanner, Speech Practice, and AI Tutor remain visible `limited` capabilities without exact-artifact physical/provider certification; host fakes do not satisfy this gate | Field owner |
| Low-tier Android device | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | No exact-artifact physical-device record | Field owner |
| Mid-tier Android device | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | No exact-artifact physical-device record | Field owner |
| High-tier Android device | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | No exact-artifact physical-device record | Field owner |
| App Check configuration and signed-release traffic | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Configuration, valid-traffic, and controlled-enforcement references are absent | Firebase owner |
| Hosted asset links and cloud kill switch | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Hosted verification and controlled drill references are absent | Cloud owner |
| Central 0-100 THB/month cost target | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Current measured project-total cost (or verified no-billing zero), exact 100 THB ceiling, 50/80/100 alerts, and content-addressed billing evidence are absent; alerts alone cannot pass | Billing owner |
| Private feedback and support channels | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Evidence shell contains pending references only | Beta owner |
| Research protocol | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Approved private protocol reference is absent | Research owner |
| Beta operations and rollback drill | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Mandatory v2 cohort, consent, crash-free, sync, issue, provider-cost/download, owner-decision, rollback, and kill-switch records are absent; the verifier now rejects their omission | Beta owner |
| Exact-hash owner smoke test and approval | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Approval flag, timestamp, and private evidence reference are absent | Repository owner |
| MaxPlus advisory review | blocked-external | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Unavailable after prior `invalidKey`; not retried. Local read-only review was used and Codex Security was not invoked | External analysis service |
| Publication or distribution | not-applicable | not-applicable | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Explicitly outside current authorization; no upload, push, publication, release, or distribution occurred | Repository owner |

## Decision rationale

The local gates establish that the source and internal package are suitable for
controlled evidence collection. They do not establish field certification.
The failed frozen-identity row and the external rows above are mandatory. The
v2 verifier rejects free-form references, stale or out-of-order timestamps,
unsigned, untrusted, or unresolved content-addressed receipts, mutable claims
that differ from their signed payloads, emulator/debug collector markers,
missing beta/rollback records, and unknown or over-policy central cost. Local
integrity checks make accidental or unattributed synthetic substitution fail;
they do not prove that a dishonest authorized evidence issuer performed a real
physical test. Because mandatory rows are `fail` or `blocked-external`, the
only truthful final decision is **NOT READY**.

The next acceptable state transition starts with rebuilding and independently
verifying a signed package from one frozen source SHA; only declared final
metadata may follow it. Then collect the missing
records against that exact package, rerun the fail-closed field verifier, and
issue a new acceptance record. This document does not authorize distribution.

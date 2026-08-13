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
The field verifier therefore exits 1 and no release, upload, distribution, or
publication is authorized by this record.

## Acceptance matrix

Only `pass`, `fail`, `blocked-external`, and `not-applicable` are used.

| Gate | Status | Source SHA | Artifact SHA-256 | Command/evidence | Owner |
|---|---|---|---|---|---|
| Frozen signed package identity | pass | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Internal APK checkpoint plus independent `verify-field-package.ps1`: one pinned signer, package `com.lexiquest.app`, version `1.0.0+13`, build ID `c199d501adb8`, and pinned model provenance | Engineering |
| Later verification-source boundary | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | `git diff --name-status c199d50..555b0b9` contains only documentation, field-verifier/tests, and integration-test harness changes; the artifact continues to declare its actual source | Engineering |
| Product completion gate | pass | `555b0b9343ce78cbf04692f048bf049d90fb559f` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | `tool/cli/verify-product-completion.ps1` passed every phase, including three sequential production-shell journeys, emulators, debug APK, and model integrity | Engineering |
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
| Central 0-100 THB/month cost target | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Current Firebase/Auth/App Check/Firestore billing or no-billing evidence and 50/80/100 alerts are absent; cost remains unknown | Billing owner |
| Private feedback and support channels | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Evidence shell contains pending references only | Beta owner |
| Research protocol | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Approved private protocol reference is absent | Research owner |
| Beta operations and rollback drill | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Cohort, crash-free, sync/provider-cost, and rollback records are absent | Beta owner |
| Exact-hash owner smoke test and approval | blocked-external | `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Approval flag, timestamp, and private evidence reference are absent | Repository owner |
| MaxPlus advisory review | blocked-external | `555b0b9343ce78cbf04692f048bf049d90fb559f` | not-applicable | Unavailable after prior `invalidKey`; not retried. Local read-only review was used and Codex Security was not invoked | External analysis service |
| Publication or distribution | not-applicable | not-applicable | `EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158` | Explicitly outside current authorization; no upload, push, publication, release, or distribution occurred | Repository owner |

## Decision rationale

The local gates establish that the source and internal package are suitable for
controlled evidence collection. They do not establish field certification.
The external rows above are mandatory and cannot be satisfied by a local fake,
emulator, historical artifact, pending reference, or unknown cost. Because one
or more mandatory rows is `blocked-external`, the only truthful final decision
is **NOT READY**.

The next acceptable state transition is to collect the missing records against
the exact signed artifact, rerun the fail-closed field verifier, and issue a new
acceptance record. This document does not authorize distribution.

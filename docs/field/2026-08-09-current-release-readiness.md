# LexiQuest current release readiness

**Recorded:** 2026-08-13

**Verification source:** `555b0b9343ce78cbf04692f048bf049d90fb559f`

**Artifact source:** `c199d501adb8b83d0a1b9e7bd529c9f123f168f9`

**Artifact SHA-256:**
`EAE42C9193CCBABF0EEA8ECA5B0FB089FA5D2BD0F9E717D3ED62052184CD0158`

**Branch:** `codex/runtime-convergence`

**Decision:** NOT READY FOR FIELD DISTRIBUTION

The signed internal APK is real and independently verified. The local product
gate also passes on the later verification source. This does not replace the
missing physical-device, provider-console, private-channel, cost, beta, or
owner-approval evidence required for field release.

The commits after the artifact source contain only release-evidence tooling,
documentation, and integration-test harness changes. They do not relabel the
artifact as having been built from the later verification source.

## Phase state

| Phase | Status | Evidence or blocker |
|---|---|---|
| P0-P5 convergence | pass | Tasks 0-7 are committed; architecture, owner-scoped durability, learning/sync, feature invocation, AI/voice composition, and backend-local gates are recorded in the runtime ledger and task reports. |
| P6 internal APK | pass | Signed `com.lexiquest.app` version `1.0.0+13` package is bound to artifact source `c199d50`, one pinned certificate, the APK hash above, build ID `c199d501adb8`, and the pinned model hash. Independent package and release-model verification pass. |
| P7 physical-device checkpoint | blocked-external | No exact-artifact low/mid/high Android device records exist. |
| P8 hardening and cost | blocked-external | Local lifecycle, kill-switch, bounded-ledger, archive/delete, fallback, and dependency gates pass. Current Firebase/Auth/App Check/Firestore billing or no-billing evidence is absent, so the 0-100 THB/month target remains unknown. |
| P9 release readiness | blocked-external | App Check traffic/enforcement, asset links, cloud kill-switch drill, budget alerts, private feedback/support/research references, beta operations, rollback drill, and exact-hash owner approval are absent. |
| P10 final acceptance | blocked-external | The mandatory external evidence above is incomplete; the field verifier exits 1 after first verifying the signed package. |

## Frozen local gate observations

All observations below were recorded no later than
`2026-08-13T14:08:22.1961032Z`.

| Gate | Source | Result | Evidence |
|---|---|---|---|
| Product completion | `555b0b9343ce78cbf04692f048bf049d90fb559f` | pass | `tool/cli/verify-product-completion.ps1`; contract and release-packaging contracts, format, full analysis, product tests, three production-shell field journeys, Firebase Auth emulator, Firestore rules emulator, debug APK, model integrity, and diff hygiene all passed. |
| Signed package integrity | artifact source `c199d501adb8b83d0a1b9e7bd529c9f123f168f9` | pass | `tool/cli/verify-field-package.ps1` verified one signer, pinned certificate, package/version, APK hash, source/build/model provenance, and release model runtime. |
| Field evidence | same signed artifact | blocked-external | `tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json -ParticipantPackagePath build/field-release` exited 1 with the exact missing external records; it did not run the final regression phase. |
| Secret scan | `555b0b9343ce78cbf04692f048bf049d90fb559f` | pass | Explicit installed Gitleaks binary: `gitleaks git . --redact --no-banner`; 571 commits and about 102.70 MB scanned, no leaks found. |
| Dependency vulnerability inventory | `555b0b9343ce78cbf04692f048bf049d90fb559f` | pass | `tool/cli/verify-osv-locks.ps1` scanned six explicit lock/dependency files with their scoped policies. The known broken Windows recursive path mode was not repeated. |
| Git hygiene | `555b0b9343ce78cbf04692f048bf049d90fb559f` | pass | Clean porcelain before the frozen gates and `git diff --check` exit 0. |
| MaxPlus advisory | n/a | blocked-external | MaxPlus remained unavailable after the prior `invalidKey` failures and was not retried. Plan-authorized local read-only review was used; Codex Security was not invoked. |

## Exact external blockers

1. Three physical Android records (low, mid, and high) tied to this exact APK,
   certificate, model, version, and build ID, including the mandatory journeys,
   benchmark, and endurance observations.
2. App Check configuration, valid signed-release traffic, controlled
   enforcement, hosted asset links, and a cloud kill-switch drill.
3. Verified 50/80/100 budget alerts or owner-controlled no-billing/current
   billing evidence demonstrating the approved central-cost target.
4. Real private feedback, support, and research-protocol references.
5. Beta cohort, crash-free, sync/provider-cost, and rollback observations.
6. Owner smoke-test approval tied to the exact APK SHA-256.

No historical record, placeholder, host fake, emulator, or debug artifact is
substituted for these items. Until they pass, the release decision is NOT
READY.

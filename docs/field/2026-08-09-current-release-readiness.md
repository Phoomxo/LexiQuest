# LexiQuest Current Release Readiness

**Recorded:** 2026-08-09

**Application source:** `f1e7c8f75e39f71400bc9d68326e90f5ba841c52`

**Branch:** `integration/p0-baseline`

**Decision:** NOT READY FOR FIELD DISTRIBUTION

This record separates bounded local verification from evidence that can only
come from a signed artifact, physical devices, provider consoles, and the
owner. Historical APK/device records are not reused for this source.

## Phase state

| Phase | Current state | Evidence or blocker |
|---|---|---|
| P0 Baseline/Convergence | PARTIAL | Corrective slices are isolated and committed, but required baseline `7b8ac6c` is not an ancestor of this branch. |
| P1 Platform/Data | LOCAL PASS / PHASE PARTIAL | Local-first/data gate passed 81 tests; schema v12 owner isolation, migrations, upgrade, and erasure gates pass. No frozen release artifact exists. |
| P2 Sync/Learning | LOCAL PASS / PHASE PARTIAL | Sync/learning gate passed 110 tests and Firestore emulator policy gate passed 31 tests. Exact-APK device journeys remain pending. |
| P3 Device/Media | LOCAL PASS / PHASE PARTIAL | Device/media gate passed 57 tests; pinned model fixture SHA was verified and 3 affected LiteRT tests passed. Physical-device evidence is absent. |
| P4 AI/Voice | LOCAL PASS / PHASE PARTIAL | AI/BYOK gate passed 27 tests, remaining Voice gate passed 260 tests, and provider-neutral owner-scoped UI/accounting is production-reachable. Real-provider/device evidence is absent. |
| P5 Production Backend | LOCAL PASS / PHASE PARTIAL | Voice API 55, AI API 76, and Local LM 75 tests passed in frozen CPU-only dev environments. Supabase policy/deployment evidence is unavailable. |
| P6 Internal APK | BLOCKED | `android/key.properties` is absent; no current release APK, release manifest, signing-certificate digest, or APK SHA-256 exists. |
| P7 Device Checkpoint | BLOCKED | No low/mid/high physical-device matrix tied to a current signed APK hash. |
| P8 Beta/Field Journeys | PARTIAL | Reliability, persisted emergency controls, production AI routing, and local data rights are integrated and tested. Real provider/device journeys remain absent. |
| P9 Release Readiness | BLOCKED | App Check valid traffic/enforcement, Supabase policy evidence, private support/research references, budget evidence, exact-hash owner approval, and field evidence are absent. |
| P10 Final Acceptance | BLOCKED | P6-P9 do not reconcile to one frozen source commit and signed APK hash. |

## Current prerequisite inventory

- Release signing config: missing (`android/key.properties`).
- Field evidence: missing (`field/evidence/release-evidence.json`).
- Packaged manifest: missing (`build/field-release/release-manifest.json`).
- Release APK: missing; existing build output is debug-only and predates the
  current application source.
- Android tooling: `adb` available; SDK `apksigner.bat` available under Android
  SDK build-tools.
- Release contracts: field evidence 60/60, Android release signing 54/54, and
  product-completion contract PASS.

## Release verifier result

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1
```

Result: BLOCKED at the first prerequisite because the field evidence file is
missing. The gate was not weakened and no placeholder evidence was generated.
A formatting defect that originally hid the resolved missing path was corrected
with a failing-then-passing contract test. The corrected verifier observation
was recorded on clean repository SHA
`aec1a8c0979bc1b6462dea72e2071d080113e5a7`.

## Required external inputs before P10 can pass

1. Owner-controlled Android release signing configuration.
2. A clean packaged release APK and manifest tied to one frozen source SHA.
3. Physical low/mid/high device evidence for that exact APK SHA-256.
4. Valid App Check release traffic followed by controlled enforcement evidence.
5. Firebase/Supabase policy and hosted asset-link evidence.
6. Private feedback/support/research references and shared-infrastructure
   budget evidence within the approved 0-100 THB/month target.
7. Owner smoke-test approval referencing the exact APK SHA-256.

Until these inputs exist, the correct release decision remains BLOCKED rather
than converting placeholders or historical records into PASS.

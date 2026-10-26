# ADLC continuation board — 2026-10-24

## Intent

Continue the approved LexiQuest Android work without reopening routine product
decisions. Complete every local/synthetic engineering gate that can be proven
from this checkout, preserve the frozen 8-domain/44-capability catalog, and
leave production deployment, research enrollment/upload, and destructive live
data operations disabled.

## Grounded source

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- The checkout is intentionally dirty with integrated work from the active
  plan. Each card has one writer and a disjoint write set.
- R11 is synchronized to Figma Cloud under owner `petch954100@gmail.com`.
- Current integrated source passes 1703/1703 Flutter tests, full analyze,
  format, CLI contracts, Firebase Auth/Firestore emulator suites, signed
  release builds, and the final8 local Android device matrix.
- Vivo cold/warm App Link replay and native Google provider launch remain
  retained evidence from the earlier final/final4 snapshots; they were not
  rerun against final8.

## Task graph

| Card | Outcome | State | Writer/write set | Acceptance evidence |
| --- | --- | --- | --- | --- |
| `DEVICE-DIALOG-1` | Remove route-local controller disposal race found by Firebase Test Lab | Done | Root; category/login/settings dialogs + focused test | Vivo real-IME replay accepted; 1598/1598 suite; signed release rebuilt |
| `UI-PREF-1` | Persist System/Light/Dark independently from marketplace theme/wallpaper | Done | Adaptive UI agent; appearance preference/config/screen, `main.dart`, settings row, focused tests | Integrated 133-test run passed; scoped analyze clean; save failure does not apply; navigation/reward appearance retained; compact 200% text |
| `RESEARCH-R1` | Make research export fail closed until an explicit operation authorizer exists | Done | Research agent; new research authorizer, export use case/bootstrap and focused tests | Integrated 133-test run passed; consent alone cannot export; denial precedes reads/writes; personal export unaffected |
| `ACCOUNT-A3` | Preserve a committed account when the first verification-email dispatch fails | Done | Account/release agent; Firebase gateway, OTP copy, focused tests | Integrated 133-test run passed; committed session continues to owner binding; explicit resend remains available; pre-commit failures stay typed |
| `FOLD-1` | Conservative hinge-safe shell fallback | Done | Adaptive UI agent; composition root + adaptive tests only | Vertical/horizontal/no-feature/state tests 4/4; integrated startup/reward/appearance run 24/24; scoped analyze clean |
| `ACCOUNT-G1` | Add a tested Google sign-in path gated on real OAuth config | Done | Account agent; account contracts/use cases/gateways/bootstrap/login, dependency lock, focused tests | Owner isolation and fallback covered; refreshed production config contains Android/Web OAuth clients; provider enabled and production gate defaults on |
| `INTEGRATE-1` | Reconcile agent diffs and verify one consistent source snapshot | Done (local engineering) | Root only; checkpoint/evidence plus corrections in returned write sets | Flutter 1685/1685; backend 206; Auth 3/3; rules 33/33; analyze/format/diff clean; debug/release APK and AAB rebuilt; Vivo cold/warm App Link replay passed |
| `ACCOUNT-D1` | Crash-resumable, owner-isolated account deletion core | Done (default-off) | Account deletion domain/use case, SharedPreferences journal, Drift local gateway, focused tests | Rejects journal overwrite; exact-one-active-owner fail closed; deterministic retry receipt; no production composition |
| `ACCOUNT-D2` | Complete locally provable deletion UX/data/backend contracts | Done (default-off) | Account deletion UI/adapters, Gemini secure store, AI API service contract, focused tests | Exact Thai confirmation; local-only retry after cloud receipt; exact 26-scope owner-isolated snapshot; required secret purge with post-commit recovery; completed-journal identifier scrub; server-derived UID/auth_time; same-key receipt replay; endpoint disabled without production adapters |
| `FIREBASE-MOBILE-LINKS` | Configure Firebase Hosting mobile-link domain and Android App Link | Done | Firebase project config, manifest, parser, runbook, fixtures | Hosted assetlinks 200; exact package/cert; trusted wrapper/redirect rejection; Vivo cold/warm replay |
| `FTL-POSTFIX` | Re-run fixed artifact on low/high/fold/tablet | Current local matrix done; cloud quota blocked | Evidence only | `final8` low/high/tablet 3/3 pass on LDPlayer with Google visible/enabled, nonparticipant consent reaching Home, and zero severe logs; FTL matrix `matrix-dbgrwqqxijpsa` rejected with `TEST_QUOTA_EXCEEDED`; no available emulator exposes a real fold hinge |
| `FIGMA-R11-CLOUD` | Sync validated R11 authority into the owner's Figma file | Done | Figma writer | Cloud root `81:2`; 240 screens, 942 routes, 41 starts; final8 Google copy and both prototype routes verified; `/critique` 40/40 |
| `RESEARCH-R2` | Signed permit/assignment lifecycle and fail-closed export | Done (production default-off) | Research authorizer/export/bootstrap plus synthetic tests | Owner/operation/issuer/key/algorithm/assignment/protocol/instrument/revision/expiry/revocation pinned; nonparticipants produce zero research writes |
| `ACCOUNT-G1-CONSOLE` | Enable Google provider and refresh Android OAuth config | Done | Root; Firebase Console, generated config, runtime gate, CLI contract and Vivo evidence | Provider Enabled for `petch954100@gmail.com`; Android/Web OAuth clients verified; `final4` opens native Google Sign-In activity on Vivo |
| `RELEASE-EXTERNAL` | Play/App Check/production Firestore/UAT authorization | External wait | Owner-controlled console/evidence | Requires exact AAB/APK hash acceptance and explicit rollout authority; neither is recorded yet |

## Conflict and authority rules

- Flutter tests/builds, dependency resolution, and code generation remain
  serialized by root.
- `UI-PREF-1`, `RESEARCH-R1`, and `ACCOUNT-A3` have handed their write sets back
  to root after connected review and an integrated 133-test run.
- `FOLD-1` has handed `main.dart` back to root after root reran its integrated
  24-test matrix.
- ไม่มี implementation writer ค้างอยู่; ทุก agent คืน write set ให้ root แล้ว
  และ integration evidence อ้าง source snapshot เดียวกัน
- No card may add a 45th feature, create a parallel reward/learning authority,
  reserve schema v11, or enable production research from inferred contracts.
- Pair Matching remains outside this board under the explicit guardrail that it
  needs a separate user request after research engineering completion.

## Integration order

1. Local engineering baseline is attested in
   `2026-10-24-adlc-final-integration-checkpoint.md`; the current UI, device,
   release-artifact, and Figma evidence is superseded by
   `2026-10-24-adlc-final8-ui-critique-checkpoint.md`.
2. Google Sign-In is enabled in the verified `final8` artifacts.
3. Research enrollment/upload, production deletion, Play rollout, and App
   Check enforcement remain separate authority gates.

## Cycle 12 production-test readiness continuation — 2026-10-26

### Intent and fixed boundaries

Prepare one source-bound Android release candidate that can be installed for
real-device acceptance testing without claiming Play production readiness or
research authority. Production research enrollment/upload remains disabled.
No task may fabricate physical-device, human-UAT, Play, privacy-owner, or ethics
evidence.

Baseline for this continuation:

- Worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`
- Branch: `codex/cycle12-release`
- HEAD before implementation: `bd4ec9083a290ad256ebd80c9d292359796bf6aa`
- Fresh baseline: `flutter test --no-pub` passed 1758/1758 on 2026-10-26.
- Pre-existing untracked critique snapshot is preserved and is not release
  source.

### Task graph

| Card | Outcome | State | Exclusive write set | Acceptance |
| --- | --- | --- | --- | --- |
| `DEL-PROD` | Compose crash-resumable account deletion without enabling an unproven live endpoint | Done (engineering; production default-off) | account-deletion Flutter adapters/bootstrap, AI API Firebase deletion composition, focused tests | 74/74 Flutter account-deletion tests and 16/16 focused backend tests pass; recovery, owner/idempotency, export-before-delete, Auth-last deletion and kill-switch behavior independently reviewed; production export authority remains absent and fails closed |
| `REL-GATE` | Bind artifacts to source and strengthen portable public/field evidence gates | Done (local gate) | `tool/cli` release scripts/tests, evidence template, signing trust and participant allowlist manifests | 210/210 field-release and 63/63 signing tests pass; independent review accepted measured APK/AAB identity, fixed certificate/model trust, reparse containment and physical-device classification |
| `PUB-WEB` | Supply truthful privacy/deletion/support/store/rollback assets without inventing an owner contact | Done (local; deployment not authorized) | Firebase Hosting pages, store/runbook/privacy docs, public-page verifier, CI contract | Public-page 10/10, Hosting/loader 15/15, CI 65/65, Auth 3/3 and Firestore rules 33/33 pass; production contact policy intentionally fails closed until owner-approved endpoints exist |
| `CAT-44` | Make the frozen 8-domain/44-capability identity machine-verifiable without implying rollout | Done | machine-readable design catalog and architecture contract test | RED missing-manifest test observed; GREEN verifies revision 1.3.0, exactly eight domains, ordered unique `f01-f44`, no inferred runtime state |
| `INTEGRATE-RC` | Integrate the three cards on one snapshot and create a new signed candidate | Done (engineering candidate) | root only; plan/checkpoint/build/evidence integration | Signed `1.0.0+17` APK/AAB bind full commit `613ee5ef4cea7e795380af1c08ab815528147159`; Flutter 1774/1774, backend 92/92, Auth 3/3, rules 33/33, analyze, release/public gates and model runtime pass |
| `DEVICE-RC` | Exercise the new exact artifact on available Vivo/emulators | Done for available Vivo; external matrix pending | evidence only | Vivo V2041 measured `mid/phone`; in-place `+16` to `+17` upgrade retains install, installed APK hash/signer match, cold/warm MainActivity and severe-log scan pass; 200% portrait/landscape render checked, while manual TalkBack/UAT and distinct low/high/Fold/tablet remain external |
| `FIGMA-R12` | Make the current whole-app handoff unambiguous | Not verified (Starter quota) | Figma Cloud only | R11 Cloud `81:2` remains the verified authority and its representative prototype paths pass browser smoke; draft R12 `112:1819` is explicitly incomplete and is not treated as evidence |
| `EXTERNAL-ACCEPTANCE` | Close Play, additional physical devices, human UAT and controlled cloud rollout | External dependency | no repository writer | Exact AAB accepted by Play; Play signing SHA propagated; valid App Check traffic/enforcement/rollback; distinct low/high/Fold/tablet and human TalkBack/UAT evidence |
| `RESEARCH-PRODUCTION` | Permit real participant collection only under explicit authority | Disabled | no production writer | Ethics/protocol/instrument, trusted issuer/time, consent/withdrawal/export/delete and explicit rollout authority; otherwise fail closed |

### Integration policy

- Flutter tests/builds, dependency resolution and generators run only under the
  root writer and are serialized.
- Parallel cards use disjoint files. Root reviews every diff and reruns the
  focused checks before integration.
- Any production-code change after the `1.0.0+15` source requires a new
  versionCode. The existing `+15` artifacts remain historical evidence only.
- Public pages must not expose the project-login email as a support address
  without an explicitly configured channel.
- A locally complete candidate is not permission to publish, enroll research
  participants, or alter live App Check/Firestore state.

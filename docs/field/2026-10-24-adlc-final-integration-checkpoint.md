# ADLC final5 local integration checkpoint — 2026-10-24

## Disposition

**LOCAL ENGINEERING ATTESTED; PRODUCTION ACTIVATION REMAINS GATED.**

This checkpoint supersedes the status counts and external-wait statements in
the earlier `2026-10-24-adlc-local-integration-checkpoint.md`. Historical
checkpoints remain unchanged as evidence of their earlier source snapshots.
The later `2026-10-24-adlc-final8-ui-critique-checkpoint.md` supersedes this
checkpoint for current Flutter counts, UI/device evidence, and release-artifact
identity; this file remains the final5 integration baseline.

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- The intentionally dirty integrated worktree was preserved. No reset,
  destructive cleanup, deployment, enrollment, or production upload occurred.
- Deterministic source manifest: 679 files, including Flutter and backend
  sources, at
  `output/integration-2026-10-24-adlc-final5/source-manifest.json`, SHA256
  `3BE56F222138340A0AD0F093E06D922F4F06D49FC31D58A3F622EB67FC43197A`.

## Completed engineering

- R11 Figma Cloud sync: root `81:2`, 240 screens, 942 routes, 41 prototype
  starts, owner `petch954100@gmail.com`.
- Google Sign-In: Firebase provider enabled under the same owner, refreshed
  Android config contains the production Android and Web OAuth clients, the
  production feature gate defaults on, and the generated release resources
  contain `default_web_client_id`.
- Email actions: trusted Firebase Hosting wrapper and legacy form, strict
  scheme/host/path/userinfo/duplicate/redirect validation, Android App Link,
  and cold/warm routing.
- Research R2: signed permit lifecycle pins owner, operation, issuer/key,
  algorithm, assignment, protocol, instrument, revisions, expiry and
  revocation. Nonparticipants and missing permits create no research rows,
  events, outbox records, or uploads.
- Account deletion engineering: cloud receipt journaled before local deletion,
  crash-resume and exact receipt replay, deterministic replacement Guest,
  collision checks, pending-operation journal protection, fail-closed
  exact-one-active-owner isolation, complete 26-scope local snapshot, exact
  owner-scoped Gemini secret purge, a Thai typed-confirmation UI, and a tested
  Flutter HTTP contract. The AI API now exposes a server-authenticated,
  idempotent endpoint contract with a tombstone-first service. Review fixes
  also make network failures retryable, require exact 26-scope export equality,
  resume secure-secret purge after a committed database deletion, require the
  purge dependency, and scrub journal identifiers after confirmed local
  completion. Both client composition and the endpoint remain default-off
  until production adapters and recent provider reauthentication exist.
- Adaptive Android shell, learning flows, vocabulary/import, progress,
  marketplace, AI Tutor, voice/camera, settings, offline/sync, and the frozen
  8-domain/44-capability catalog remain integrated.

## Final5 source verification

| Gate | Result |
| --- | --- |
| Focused journal/owner/warm-link regressions | 23/23 pass |
| Focused Google/account/bootstrap/login regressions | 69/69 pass |
| Android release/OAuth configuration contract | 56/56 pass |
| Account deletion focused integration | 30/30 pass |
| Product completion Flutter selection | 703/703 pass |
| Full Flutter regression | 1697/1697 pass, 08:55 |
| Flutter analyze | No issues |
| Product gate Dart format check | 243 files, 0 changed |
| `git diff --check` | Pass; line-ending warnings only |
| Product completion CLI contract | Pass |
| Firebase Auth emulator | 3/3 pass |
| Firestore rules emulator | 33/33 pass |
| Voice API / AI API / LexiQuest-LM | 55 / 83 / 75 pass (213 total) |
| Debug APK / release APK / release AAB | Built successfully |
| `:app:validateSigningRelease` | BUILD SUCCESSFUL |
| Release APK signature | v2 verified, one signer |
| APK/AAB ZIP integrity | All entries readable |

No Codex Security workflow was invoked.

## Final5 artifacts

All artifacts were built from the reviewed final5 source with Google Sign-In
enabled by default and build ID `20261024-adlc-final5`.

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `build/app/outputs/flutter-apk/app-debug.apk` | 221323544 | `2C72A321A551E9B32A7CA075C1684D156118E7319654424D239A877089C24281` |
| `build/app/outputs/flutter-apk/app-release.apk` | 112189732 | `244EB4D956CA6C54478CA7C34EAB47669FA74153417BF8CD6887DBC5F972C09A` |
| `build/app/outputs/bundle/release/app-release.aab` | 100070450 | `775E07EB9F37CF7017BE271714B9FE91AFF911C90E06637F3BF9AB4624F76782` |

Release certificate SHA256:
`E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`.

## Device evidence

- Vivo V2041, Android 13: `final5` debug APK installed with `adb install -r`
  to preserve existing app data.
- Startup succeeded with `MainActivity` resumed and no matched fatal,
  AndroidRuntime, unhandled Flutter, RenderFlex, or database-lock error.
- The six-file Vivo evidence ledger is at
  `output/integration-2026-10-24-adlc-final5/vivo/`, manifest SHA256
  `F17EDE760F4E80C38235D84BE48139E2D0BAF0DCA4F7CEC4CBE4B7B575EAF508`.
- Earlier final-snapshot Firebase Hosting App Link passed on cold start for password
  reset and on warm start for email verification. Evidence is under
  `output/integration-2026-10-24-adlc-final/vivo/`.
- The `final4` debug build displayed the Google action on the Vivo login
  screen and launched the native Google Sign-In activity. The flow was backed
  out before selecting an account, so no real Firebase user or owner mutation
  was created. The 20-file evidence
  manifest SHA256 is
  `F5EF3A6A5F9D4D6B176C0DE382052A31BB58BCE3C1FC711D1A94E4D566302FEF`.
- The final5 signed release APK cannot replace the debug-signed Vivo package
  without uninstalling and deleting local app data, so the destructive
  replacement was intentionally not performed.
- The `final5` debug APK passed serialized LDPlayer low/high/tablet
  3/3: Login and Google were visible/enabled, Guest reached Home, the
  nonparticipant path selected “ยังไม่ยินยอม”, and the severe log scan found
  zero matches. The 57-entry evidence ledger is under
  `output/adaptive-ui-gap-audit-final5-20261024/`, SHA256
  `3690F92705D50ED6E4087AD8831316922AEEF21BABEAFCFCAF95C9E3CFC55093`.
- Firebase Test Lab matrix `matrix-dbgrwqqxijpsa` was rejected before execution
  with `TEST_QUOTA_EXCEEDED`; physical fold/posture remains unverified because
  the available LDPlayer/AVD inventory exposes no real hinge capability.

## External activation gates

1. Research production remains deny-all until trusted issuer/time authority,
   ethics/protocol/instrument approval and explicit rollout authorization are
   supplied.
2. Real account deletion remains disabled until the persistent operation store,
   verified owner-to-Firebase-UID binding, owner-isolated Firestore/Auth
   deleter, backend-attested fresh cloud export, provider-specific recent
   reauthentication, startup recovery composition and production receipt
   authority exist.
3. App Check enforcement, Play acceptance, production Firestore, stakeholder
   UAT and rollout require their separate external evidence and permission.

The build still reports the upstream future Built-in Kotlin migration warning.
The retained database write-lock contract still returns a timeout after five
seconds. Neither warning failed the final5 verification.

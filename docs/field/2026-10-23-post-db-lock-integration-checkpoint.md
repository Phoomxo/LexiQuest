# Post database-lock integration checkpoint — 2026-10-23

> Current-source verification and release hashes moved forward on 2026-10-24
> after the dialog-controller repair. See
> `docs/field/2026-10-24-firebase-test-lab-controller-lifecycle-checkpoint.md`.
> The retained-data database-lock evidence below remains valid for its recorded
> source and device run.

## Disposition

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Status: **LOCAL SOURCE + BUILD + LDPLAYER + SIGNED APK + POST-FIX PHYSICAL VIVO ACCEPTED**
- This checkpoint is engineering evidence for the current local source. It is
  not a production deployment, research activation, or proof
  that all 240 R11 specimens exist as production Flutter screens.

## Current source verification

- Source manifest: 514 files from `lib/`, `test/`, `tool/`, `pubspec.yaml`, and
  `pubspec.lock`.
- Source-manifest SHA256:
  `984EA2C400328F46E32DA4275A434F4B16AE49A0C1797B56E049B1ACA90B0101`.
- `flutter test --no-pub --reporter compact`: **1597/1597 passed**, exit 0,
  08:34. Log: `output/integration-2026-10-23-final/flutter-test-final.log`.
- `flutter analyze --no-pub lib test tool`: no issues, exit 0, 7.5s.
- `dart format --output=none --set-exit-if-changed lib test tool`: 458 files,
  0 changed.
- `git diff --check`: exit 0. Existing line-ending notices are warnings and no
  file was rewritten to hide them.

## Retained-database lock repair

- The earlier Vivo retained-data launch reproduced `SqliteException(5)` on
  `BEGIN IMMEDIATE` while WorkManager and the foreground bootstrap could open
  independent connections to the same SQLite file.
- `AppDatabase.production()` now keeps foreign keys enabled, installs
  `busy_timeout = 5000` before lock-requiring setup, and uses WAL.
- The regression opens connection B only after connection A holds a real file
  write transaction. B waits, then restores the same retained owner after A
  releases the lock; it also verifies `journal_mode=wal` and timeout 5000.
- Focused test passed on the final source. The independent review's ordering
  and open-under-lock findings were fixed before the final 1597-test run.
- Detailed checkpoint:
  `docs/field/2026-10-23-retained-db-lock-recovery-checkpoint.md`, SHA256
  `205775118FD14FD839F51BC66759DA1D474F9A2150E82F60BEF0F89D39096B64`.
- A writer lock longer than five seconds still returns a database error by
  policy instead of waiting without a bound.

## Debug build artifacts

Both build commands completed with exit 0. The only build warning is the
known future Flutter/Kotlin Built-in Kotlin migration for four plugins.

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `app-debug.apk` | 218,027,102 | `7983E4CDA9652755AC6A4E23C2C5AE0A36421F99FCCD276D5CE0E769720ED061` |
| `app-armeabi-v7a-debug.apk` | 93,783,166 | `3D986B4F12BF5FDBA01D98E869F4E1CB889F0D75D31A19DC3E5809B71F1DD1A5` |
| `app-arm64-v8a-debug.apk` | 119,361,210 | `884341EA43A8DB5A367A77F0564243B085BCE609DBA6B77D7A276ABF3BF6344E` |
| `app-x86_64-debug.apk` | 109,252,000 | `BFEE6C2AC9C349B8FDDD6912E53381BBBBEF802074A94D0EC507577B95F9B604` |

Manifest: `output/integration-2026-10-23-final/apk-manifest.json`.

## Signed release verification

- `flutter build apk --release --no-pub`: exit 0. The APK is 111,751,324
  bytes with SHA256
  `DF8769224CB33CD779B0D78DCC57D63A650E01E5CFDB614520118CA285DDCFD7`.
- Android `apksigner 37.0.0 verify --verbose --print-certs`: exit 0. The APK
  has one RSA-4096 signer and verifies with APK Signature Scheme v2. Its
  certificate SHA256 is
  `e1b00e17896bfb73fe0dc42429768b966465213d49a8a5165de06688cc8fdc1f`.
- The same certificate fingerprint is present in
  `hosting/public/.well-known/assetlinks.json` for `com.lexiquest.app`.
- `:app:validateSigningRelease`: Gradle build successful, exit 0. Release
  configuration fails closed when any key property is missing.
- `flutter build appbundle --release --no-pub`: exit 0. The AAB is 99,653,674
  bytes with SHA256
  `191EC3179988CC3317EF93208EB906108EE80AEA82F41A4D03A5966A8AE6410D`.
- Python ZIP integrity checks passed for all 511 APK entries and all 542 AAB
  entries.
- `jarsigner -verify -strict` on the AAB returned exit 4. The output says the
  JAR is verified, but rejects the expected self-signed Android upload
  certificate as an untrusted PKIX chain and also reports JarFile versus
  JarInputStream inconsistencies. Therefore the AAB is built and signed but
  is not certified as Play-accepted until Play Console validates this exact
  hash.
- The APK contains `arm64-v8a`, `armeabi-v7a`, and `x86_64`, targets API 36,
  and has package `com.lexiquest.app` version `1.0.0` (`versionCode` 1).
- Focused App Check/network/registry tests: **46/46 passed**, exit 0. Release
  defaults to Play Integrity because `LEXIQUEST_APP_CHECK_DEBUG` defaults to
  `!kReleaseMode`; live Play Integrity attestation was not executed.

## Research production gate

- Focused consent, EventEnvelopeV2/adaptor, owner isolation, export UI/data,
  experiment/analytics/exporter, and voice telemetry tests: **125/125 passed**,
  exit 0. Log SHA256:
  `688CBBAD3D1DBD9ADF7A666C5535317612C61C00EBA794C46FCFF7852B7B1FFD`.
- Firestore emulator rules: **33/33 passed**, exit 0. Log SHA256:
  `C2416D3FDFF85D74007279447071156B691B73F0A03CB25669EADEDEE0C28244`.
- Current code has owner-scoped, versioned consent and withdrawal, a frozen
  22-field EventEnvelopeV2, personal/research export checks, and unassigned
  experiment defaults.
- A bounded source/test search found no canonical `EvidenceContext`,
  `ResearchPermit`/`PermitVerifier`, protocol pin, instrument pin, or research
  upload boundary. The schema ledger remains at v10; v11 is unreserved.
- Disposition: **PRODUCTION RESEARCH HOLD**. Real enrollment and upload remain
  off until those gates, owner-scoped storage/migration, revocation/expiry,
  deletion/export coverage, trusted issuer, approved instruments, and ethics
  authority exist and pass their acceptance checks. Ordinary learning is not
  blocked by this hold.

## LDPlayer responsive matrix v3

- **9/9 passed** on the current x86_64 APK: 393x876, 360x800, 412x915,
  600x960, 800x1280, 1024x1366, 1280x800, 800x479, and 800x480.
- Every profile resumed MainActivity, rendered the Login marker, produced a
  screenshot at the configured resolution, and exposed 26–30 accessibility
  nodes with 6–7 clickable nodes.
- App logs contained zero `FATAL`, `Unhandled`, `RenderFlex`,
  `SqliteException`, or `database is locked` matches.
- Four transient LDPlayer transport failures were reconciled once with the
  task-owned instance and `ldconsole installapp`; the runner then repeated the
  complete gates. They are not counted as UI passes from an unexecuted run.
- All LexiQuest instances 1–9 were stopped. No emulator serial remained in the
  default ADB device list after cleanup.
- CSV: `output/ldplayer/matrix-results-v3.csv`, SHA256
  `7A263406C77F5D17ACEEEA168B135D55F41F9901C44E921E66B8F58C6627807E`.
- Evidence manifest: `output/ldplayer/v3/manifest.txt`, SHA256
  `E70DA8A964DECEBFEFAED7CD605A6F92CDB6E3ECE6349F16C6086DEF32B2B4BB`.
- Evidence hashes: `output/ldplayer/v3/evidence-sha256.txt`, SHA256
  `9B4BF4FF46B0B936FDD567C9A868F019523EABB0019A40992AE52D7446117DC6`.

## Design system and workflow status

- The current local R11 authority revalidated at source hash
  `746354255a39619732391ad2f0f6a67377a7b2337231006331fef0e538091e10`:
  240 specimens, 942 routes, 41 starts, 8 domains/44 capabilities, no dead,
  broken, duplicate-route, section-bound, or content-bound errors.
- The 40/40 score is a prototype/design-spec result. The 240 specimens map to
  22 canonical component families and are not 240 production Flutter screens.
- A strict scan of the historical Canva master HTML still reports P1 issues.
  That file is retained as historical evidence and is not the R11 authority;
  it was not rewritten to manufacture a pass.
- Production code implements the four-root adaptive shell and bounded working
  slices for local account/owner, vocabulary/import/source, Quiz/SRS/Reading/
  Flashcards/Voice result-repair, targeted Ask Lexi practice, progress,
  marketplace, sync/export/settings, offline model setup, and the device
  permission center.
- Production parity remains open for Google OAuth, trusted full-account
  deletion, durable source history/provenance, persistent theme/text/reduced-
  motion preferences, deeper list-detail/hinge behavior, several catalog game
  modes, and complete research permit/assignment/protocol/instrument/
  withdrawal/upload/export/delete gates.
- Figma Cloud still shows R10. R11 exists as validated local source/preview and
  plugin; the 2026-10-23 write did not succeed because of payload/quota limits.
  No subscription purchase or destructive account cleanup was performed.

## Physical Vivo boundary

- Before this repair, Vivo V2041 Android 13/API 33 reproduced the retained-data
  lock and provided the evidence that drove the SQLite policy change.
- Vivo V2041, Android 13/API 33, ARM64 reconnected as `device`. The ARM64
  post-fix APK installed with `--no-streaming -r -d`; no uninstall or `pm clear`
  ran. Package user id `10355` and data directory `/data/user/0/com.lexiquest.app`
  were retained. The restored Guest profile still showed XP 70, level 4,
  20 scored answers, and 5 unlocked achievements.
- A baseline cold launch completed and resumed MainActivity with zero fatal,
  unhandled, RenderFlex, SqliteException, or database-lock matches.
- With the app in background, forced WorkManager job 10 and the foreground hot
  resume ran together. The job returned `Running job [FORCED]`, then
  `jobFinished`; MainActivity remained top-resumed and the same error scan had
  zero matches. This closes the retained-data post-fix collision check on this
  Vivo for the tested workload. A writer holding the lock beyond five seconds
  still reaches the bounded timeout by policy.
- Permission Center opened without requesting new permissions and reported
  Camera and Microphone as allowed; Android package state agreed that both were
  granted.
- At 200% text, portrait exposed 30 semantic nodes/8 clickable nodes and
  landscape exposed 25/6. Both had zero invalid bounds and zero fatal,
  RenderFlex, or database-lock matches. Visual inspection found no app content
  overlap, although the Vivo system accessibility floating control can cover
  content near the left edge. Font scale and rotation were restored to the
  original `1.0`, auto-rotate `1`, user rotation `0`.
- TalkBack was enabled for one cold launch and appeared active in Android's
  accessibility dump. The screen exposed 38 semantic nodes, 12 clickable nodes,
  and 16 described nodes with zero scanned app errors. Accessibility services
  were restored to `null` and accessibility enabled to `0`.
- Vivo `uiautomator dump` logs a vendor-only denied read of
  `/sys/board_info/user_cpu_freq`, but still writes and pulls complete XML; this
  did not originate in LexiQuest and did not prevent any acceptance check.
- Evidence directory:
  `output/integration-2026-10-23-final/vivo-post-fix/`.
- Evidence manifest covers 41 files and has SHA256
  `5D7A769E9DA2AB7A35DD1DA6C853D1FF8BA3980FBE9923A40240B723B56E92AE`.
- No low-, high-, fold-, or tri-fold physical device is connected. The 9/9
  LDPlayer matrix remains emulator evidence and does not certify those physical
  classes.

## External and release-only holds

- Not certified: low/high/fold/tri-fold physical hardware, live Google OAuth,
  Play Console acceptance/live App Check attestation/Firestore production
  configuration, trusted account
  deletion backend, live provider/acoustic quality, research issuer/ethics/
  instruments/participant enrollment/upload, and stakeholder UAT.
- Research enrollment and upload remain default-off. Ordinary learning remains
  usable when research authority is unavailable.

# ADLC cycle 12 — clean signed release and MiroFish runtime evidence

Date: 2026-10-26 (Asia/Bangkok)

Branch: `codex/cycle12-release`

Disposition: local engineering evidence complete for this continuation; production rollout remains gated

## Outcome

The consolidated cycle-12 source was packaged from a clean commit as an
official local field-release candidate. The release tooling now builds and
binds both APK and AAB artifacts, verifies that both use the same signing
certificate, and requires owner approval to reference both hashes. The signed
APK was upgraded in place on the connected Vivo V2041 without changing the
original install time, then passed automated cold/warm launch and severe-log
checks.

MiroFish `v0.1.2` was also exercised as an external, synthetic-only test
runtime. No MiroFish or AGPL source was copied into LexiQuest, and no LLM/Zep
workflow or production data was invoked.

This checkpoint does not claim Play acceptance, App Check enforcement,
production Firestore rollout, complete physical-device coverage, stakeholder
UAT, or authority to enroll/upload real research participants.

## Source and commits

- Consolidated cycle-12 baseline: `7f2ed7b6` (`adlc-cycle12-engineering-20261026`).
- Synthetic MiroFish boundary: `574fcbfb`.
- AAB-bound release gate baseline: `bf9e8879`.
- Subsequent collector-only recovery commits: `e6c8929d`, `530d14bd`, and
  `393e651a`.
- Final Login recovery/identity polish and current artifact source:
  `3cd91c8c5f25c6ee578a7226a88b2e6ce62f3dff`.

## MiroFish runtime evidence

- External clone: `C:\Users\Phet\.agent-reach\tools\mirofish-v0.1.2`.
- Upstream identity: tag `v0.1.2`, commit
  `985f89f49acbb44ee14d9d680682c741a44eeebe`.
- Environment: Python 3.12.11 through `uv`; `uv sync --frozen` installed 132
  packages successfully. Docker server `29.6.2` was available, but no
  task-owned MiroFish container was required or retained.
- Flask test-client smoke returned HTTP 200 for:
  - `/health`
  - `/api/graph/project/list`
  - `/api/graph/tasks`
  - `/api/simulation/list`
  - `/api/report/list`
- Upstream `backend/scripts/test_profile_format.py` is not a trustworthy gate:
  it checks obsolete Twitter/Reddit field names, prints errors, and exits 0.
  Offline compatibility checks against the installed OASIS 0.2.5 loaders
  accepted one synthetic Twitter profile and one synthetic Reddit profile.
- Full graph/simulation/report workflows were not called because they require
  a real Zep key and may consume LLM credits. Placeholder credentials were not
  used against provider endpoints.

## Clean signed candidate

Version: `1.0.0+15`

Artifact source commit: `3cd91c8c5f25c6ee578a7226a88b2e6ce62f3dff`

| Artifact | SHA-256 | Verification |
| --- | --- | --- |
| `build/field-release/lexiquest-1.0.0+15.apk` | `88022344F49CCB243D95EBD4E54723FC6893F365017AA833A1C8DE722B482984` | 112,353,496 bytes; `apksigner` accepted; release model runtime passed |
| `build/field-release/lexiquest-1.0.0+15.aab` | `8377C7E24F3DB54B304B7389A06F9CF18C51AD77D9B20C894402E1F6C93D75F5` | 100,142,913 bytes; `jarsigner` returned `jar verified.` |

APK and AAB certificate SHA-256:
`E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`.

The packager and final verifier now enforce:

- APK and AAB existence and SHA-256 reconciliation;
- APK signature verification;
- AAB JAR signature verification;
- AAB certificate extraction with `keytool` and equality with the APK
  certificate;
- owner approval bound to both artifact hashes;
- invariant UTC evidence timestamps; and
- a clean collector/tooling source set before packaging.

Focused verification on the final tooling snapshot:

- field-release contract: **87/87 pass**;
- Android release-signing contract: **56/56 pass**;
- Login/account/accessibility regression: **51/51 pass**;
- product-completion suite: **731/731 pass**;
- Firebase Auth emulator: **3/3 pass**;
- Firestore rules emulator: **33/33 pass**;
- full analyzer, debug APK, and debug/release model-runtime gates: pass;
- PowerShell parser and JSON template parse: pass;
- independent review: Ready, Critical 0, Important 0.

The AAB uses the owner-controlled self-signed upload certificate and has no
timestamp. Local JAR verification accepts it; Play acceptance of this exact
hash remains external evidence.

## Vivo physical result

Device: Vivo V2041, Android 13/API 33, 1080×2408, density 440.

- Upgraded in place from versionCode 14 to 15; `firstInstallTime` remained
  `2026-10-26 08:57:19` and `lastUpdateTime` became
  `2026-10-26 12:07:32`.
- The installed `base.apk` SHA-256 is
  `88022344F49CCB243D95EBD4E54723FC6893F365017AA833A1C8DE722B482984`,
  exactly matching the locally signed APK. The in-place package-manager
  upgrade also retained the release-signature lineage.
- Cold launch: `MainActivity` top-resumed.
- Home/background/warm resume: the same `MainActivity` returned top-resumed.
- Post-launch log scan found zero matches for fatal Android/Flutter exceptions,
  RenderFlex overflow, database lock, app ANR, SIGABRT, or SIGSEGV.
- Screenshot:
  `build/field-release/vivo-cycle12-v15-cold.png`.
- Log:
  `build/field-release/vivo-cycle12-v15.log`.

The Vivo transport dropped large-file ADB sync acknowledgements and a raw
binary stream later showed no measurable progress at the ten-minute watchdog.
That task-owned process was stopped without changing the installed `+14` app.
The bounded alternative split the APK into 27 four-MiB-or-smaller chunks,
transferred each once, reassembled them on-device, and required the full
SHA-256 match before `pm install -r`. The direct ADB evidence above is retained
without manufacturing pending journey results. The generated chunk files are
not source or release artifacts; automated cleanup was denied by the execution
policy after exact target validation, so their cleanup remains housekeeping.

## `/critique` — signed Vivo Login

- Target: `lib/screens/login_screen.dart` rendered from the signed `+15` APK.
- Method: native design review only; web detector/overlay not applicable.
- Score: **40/40 — Excellent**, P0=0, P1=0.
- The previous generic identity and transient-recovery findings are closed:
  the screen now uses an LQ route mark, persistent inline provider feedback,
  live-region semantics, recovery-state clearing, responsive 16/20dp gutters,
  48dp controls, autofill, keyboard submit, and tested 200% text.
- Trend: **37/40 -> 40/40**.
- Snapshot:
  `.impeccable/critique/2026-10-26T05-09-55Z__lib-screens-login-screen-dart.md`.

## Remaining external release gates

- Physical low-tier, high-tier, fold/hinge, and tablet devices beyond the
  tested Vivo plus manual TalkBack spoken-order and stakeholder UAT.
- Play Console acceptance of the exact AAB hash and Play signing compatibility.
- App Check valid signed-release traffic and enforcement, production Firestore
  rollout approval, and owner/stakeholder approval.
- Figma Cloud final9/post-fix delta after service quota availability.
- Research ethics/protocol/instrument approval plus trusted issuer/time
  authority. Real enrollment and upload remain fail-closed/default-off.

The final field-release gate is expected to remain closed until those external
records exist. It was executed against the `+15` package and exited 1 at the
first missing-field-evidence check, before any rollout action. Its message
currently renders the path placeholder as literal `{0}`; that cosmetic defect
does not weaken the fail-closed result and was not used to force another
artifact build. Local engineering completion and production authorization are
separate states.

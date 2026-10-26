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
- Artifact source and AAB-bound release gate: `bf9e8879`.
- Subsequent collector-only recovery commits: `e6c8929d`, `530d14bd`, and
  `393e651a`; these do not alter the Flutter application bytes represented by
  the signed artifacts below.

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

Version: `1.0.0+14`  
Artifact source commit: `bf9e8879ee990ee28ff641656019531e80852f78`

| Artifact | SHA-256 | Verification |
| --- | --- | --- |
| `build/field-release/lexiquest-1.0.0+14.apk` | `10EE87F19F8086CAEFC6F63FBD04CE9BD40616763A69944BD67FCC85BF986FB7` | `apksigner` accepted; release model runtime passed |
| `build/field-release/lexiquest-1.0.0+14.aab` | `6F7EBE90FA0854A528C85D0F80B6B930B52EF3786B160DD23B1C65D70C5D19E1` | `jarsigner` returned `jar verified.` |

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
- PowerShell parser and JSON template parse: pass;
- independent review: Ready, Critical 0, Important 0.

The AAB uses the owner-controlled self-signed upload certificate and has no
timestamp. Local JAR verification accepts it; Play acceptance of this exact
hash remains external evidence.

## Vivo physical result

Device: Vivo V2041, Android 13/API 33, 1080×2408, density 440.

- Upgraded in place from versionCode 13 to 14 with `adb install
  --no-streaming -r`; `firstInstallTime` remained
  `2026-10-26 08:57:19` and `lastUpdateTime` became
  `2026-10-26 11:18:15`.
- Installed package certificate matches the release certificate above.
- Cold launch: `MainActivity` top-resumed.
- Home/background/warm resume: the same `MainActivity` returned top-resumed.
- Post-launch log scan found zero matches for fatal Android/Flutter exceptions,
  RenderFlex overflow, database lock, app ANR, SIGABRT, or SIGSEGV.
- Screenshot:
  `build/field-release/vivo-cycle12-v14-cold.png`.

The Vivo transport dropped its final ADB acknowledgement after install even
though package state had advanced. Two bounded collection attempts were used;
the operation was not retried again. The collector was repaired and reviewed
to accept this OEM case only when the transport returns, the installed
version equals the target, and version/last-update package state changed. A
fresh structured `+14` device-ledger JSON remains uncollected; the direct ADB
evidence above is retained in this checkpoint without manufacturing pending
journey results.

## `/critique` — signed Vivo Login

- Target: `lib/screens/login_screen.dart` rendered from the signed `+14` APK.
- Method: native design review only; web detector/overlay not applicable.
- Score: **37/40 — Excellent**, P0=0, P1=0.
- Strengths: one clear primary CTA, plain Thai copy, multiple account/guest
  paths, 48dp controls, autofill, keyboard submit, and tested 200% text.
- Non-blocking P3 polish: stronger LexiQuest-specific identity and persistent
  provider-recovery guidance.
- Snapshot:
  `.impeccable/critique/2026-10-26T04-22-07Z__lib-screens-login-screen-dart.md`.

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
records exist. Local engineering completion and production authorization are
separate states.

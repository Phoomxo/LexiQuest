# ADLC cycle 12 — signed candidate 1.0.0+17 checkpoint

Date: 2026-10-26 (Asia/Bangkok)

Branch: `codex/cycle12-release`

Disposition: engineering-complete field-test candidate; production and research
rollout remain fail closed

## Outcome

The Cycle 12 account-deletion, public-release, feature-catalog and release-gate
work is integrated and independently reviewed. A clean source commit produced
signed APK/AAB `1.0.0+17`. The exact APK was upgraded in place on the connected
Vivo V2041, and its installed hash, signer, version, cold/warm lifecycle and
basic responsive rendering were measured.

This package is ready for bounded owner/local field testing. It is not Play
approved and is not authorized for real research-participant collection or
upload.

## ADLC disposition

- **Intent/Ground/Plan:** the continuation board fixed the outcome, write sets,
  production boundaries and checks before implementation.
- **Execute:** `DEL-PROD`, `REL-GATE`, `PUB-WEB` and `CAT-44` are implemented.
- **Review:** independent account-deletion, release-gate and final-diff reviews
  report no remaining Critical/Important finding.
- **Attest:** full local suites and signed-artifact gates below pass on the
  recorded source snapshot.
- **Integrate:** `1.0.0+17` is the current source-bound field-test candidate.
- **Learn:** missing-field diagnostics now print the resolved evidence path;
  the fix was driven by a RED 209/1 run and closed at 210/210.

## Source and artifacts

- Release source commit/build ID:
  `613ee5ef4cea7e795380af1c08ab815528147159`
- Source tree: `711494b4bc2bee6b9db70337ee9cfad7029f3b46`
- Package: `com.lexiquest.app`, version name `1.0.0`, version code `17`
- Release manifest:
  `build/field-release/lexiquest-1.0.0+17/release-manifest.json`
  - SHA-256: `A6CFB02B9193D69D4BC60DF669B2F4745F4269615173D9962DAC233B407B019B`
- APK:
  `build/field-release/lexiquest-1.0.0+17/lexiquest-1.0.0+17.apk`
  - 112,566,488 bytes
  - SHA-256: `26725A599BBB061D986B90E73CB8C5E6BCD0C767B3DC4828390F6276222A516E`
- AAB:
  `build/field-release/lexiquest-1.0.0+17/lexiquest-1.0.0+17.aab`
  - 100,338,818 bytes
  - SHA-256: `254DBE065051DFC9B30F5F65ED34AC9DAD1509C7DDA816096CF95186242C3FF3`
- Upload certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Model SHA-256:
  `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B`

The packager verified APK/AAB identity, certificate equality, AAB signed-entry
coverage, full source-commit/version/model provenance and AAB release model
runtime before creating the package.

## Verification evidence

| Gate | Result |
| --- | --- |
| Full Flutter regression | **1774/1774 PASS** |
| Flutter analyzer | PASS, no issues |
| Flutter account-deletion focus | **74/74 PASS** |
| AI API account-deletion focus | **16/16 PASS** |
| AI API full suite | **92/92 PASS**; one upstream Python lifecycle warning |
| Firestore emulator policy | **33/33 PASS** |
| Firebase Auth emulator | **3/3 PASS** |
| Public-page contract | **10/10 PASS** |
| Hosting headers/contact loader | **15/15 PASS** |
| CI workflow contract | **65/65 PASS** |
| Field-release contract after diagnostic fix | **210/210 PASS** |
| Android signing contract | **63/63 PASS** |
| APK/AAB model runtime | PASS |
| Feature catalog | PASS — exactly 8 domains and ordered `f01-f44` |
| Hosted Android Asset Links for `+17` certificate | PASS |
| Staged diff check and Gitleaks | PASS; no staged secret |

## Vivo V2041 result

Measured device class: physical `mid/phone`, Android 13/API 33, 7,631 MB RAM,
smallest width 392.7 dp.

- In-place upgrade `+16` to `+17` passed; first-install time remained
  `2026-10-26 08:57:19` and version code is 17.
- Installed base APK SHA-256 equals the packaged APK SHA-256.
- Installed signer equals the pinned upload certificate.
- Cold and warm launch both top-resumed
  `com.lexiquest.app/.MainActivity`; severe Android/Flutter/RenderFlex/database
  lock/ANR/native-signal matches: 0.
- Login at 200% text remained readable and scrollable to all portrait actions.
  A forced landscape viewport rendered without overlap/crash; complete
  bottom-reachability remains a manual UAT item.
- Device settings were restored to font scale 1.0, auto-rotate enabled,
  rotation 0 and free user rotation.

Evidence:

| File | SHA-256 |
| --- | --- |
| `field/evidence/lexiquest-1.0.0+17/devices/mid-20261026T090716Z.device.json` | `3E5C846910E7F4A516F24367DE14D84A94DDB47B26A89EC7655C3096C078460E` |
| `field/evidence/lexiquest-1.0.0+17/records/mid-20261026T090716Z-install.json` | `D5E652A75020485E59D7FCE17842BEEBB8FF7A333430F360E9317B530811C51E` |
| `field/evidence/lexiquest-1.0.0+17/runtime/cold.png` | `BDAFBA3A029C353B2536B4157110A1540E9DE6835544EF0D293BC540A17FEF7B` |
| `field/evidence/lexiquest-1.0.0+17/runtime/app-logcat.txt` | `51FF1BED03BB7E3F807400DADA34F9BDADD8EF45DA36CC1C68B14FC376B8273F` |
| `field/evidence/lexiquest-1.0.0+17/runtime/cold-activity.txt` | `DA0D94642F2E071D5A8F7C0C206029640374101189A481FF643150168F8F4CAC` |
| `field/evidence/lexiquest-1.0.0+17/runtime/warm-activity.txt` | `DA0D94642F2E071D5A8F7C0C206029640374101189A481FF643150168F8F4CAC` |
| `field/evidence/lexiquest-1.0.0+17/runtime/font-200-portrait-bottom.png` | `B4DEA939EFE5765BC78C1B3C4D3251E2244B00506D6B57A08863CA19AEA5CC82` |
| `field/evidence/lexiquest-1.0.0+17/runtime/font-200-landscape.png` | `3902E1A518B398CA8C638AC47EEDF32494AB0FE51CD76BD6699BA48134A032FF` |

The collector deliberately leaves 13 unobserved journeys and all manual
acceptance fields pending. Synthetic App Link dispatch for this exact artifact
was not run because the execution layer rejected the command before dispatch;
the hosted certificate/domain contract passed, and older App Link evidence is
not promoted to `+17` evidence.

## Figma handoff

The authenticated project owner account was verified locally. R11 Cloud node
`81:2` remains the validated authority: 240 screens, 942 routes and 41 starts.
Browser prototype smoke passed account check, Home, Theme Marketplace, AI
Tutor, activity catalog, Vivo 393x876 and 200% accessibility paths. Draft R12
node `112:1819` remains explicitly incomplete; official R12 synchronization is
not claimed because the Starter-plan MCP quota was exhausted.

## Final gate and remaining external dependencies

The final verifier was executed and correctly stopped at the absent
`field/evidence/lexiquest-1.0.0+17/release-evidence.json`. It now reports the
resolved path rather than literal `{0}`. The record must not be created until
its required evidence is real:

- distinct physical low-tier, high-tier, Fold/hinge and tablet devices;
- manual TalkBack spoken-order and human/stakeholder end-to-end UAT;
- Play Console acceptance of the exact AAB and Play app-signing compatibility;
- App Check valid production traffic, enforcement/rollback evidence and
  production Firestore rollout approval;
- owner-approved public support/deletion endpoints;
- production account-deletion export receipt authority/KMS-backed adapter; and
- research ethics, protocol/instrument, trusted issuer/time and explicit
  participant rollout authority.

Production deletion, deployment, real research enrollment and research upload
therefore remain disabled. Ordinary local learning and bounded owner testing
remain available.

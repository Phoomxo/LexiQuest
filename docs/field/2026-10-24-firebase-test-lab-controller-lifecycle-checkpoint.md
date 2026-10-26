# Firebase Test Lab and dialog-controller lifecycle checkpoint — 2026-10-24

## Disposition

- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- Current engineering disposition: **POST-FIX VIVO ACCEPTED; CLOUD PHYSICAL
  CONFIRMATION PENDING QUOTA RESET**.
- This checkpoint does not authorize deployment, Play rollout, production
  research, or real participant enrollment/upload.

## Firebase Test Lab matrix

Google Cloud project `vocab-learning-app-219ef` ran two Robo matrices with the
approved primary account. The project is on Spark and has no billing account.

| Device class | Test Lab device | Resolution/orientation | Result |
| --- | --- | --- | --- |
| Low phone | OPPO A38, Android 14 | 720x1612 portrait | Test Lab reported success; visual review found the dialog lifecycle defect described below. |
| High phone | Pixel 9, Android 15 | 1080x2424 portrait | Completed 165 actions / 63 screens / 300.675 s. |
| Fold | Pixel 10 Pro Fold, Android 16 | 2076x2152 portrait | Completed 148 actions / 50 screens / 304.709 s. |
| Tablet | Pixel Tablet, Android 13 | 1600x2560 landscape | Completed 185 actions / 55 screens / 311.409 s. |
| Low phone retry | Infinix SMART 8, Android 13 | portrait | External harness failure: the OEM ComponentManager blocked `androidx.test.tools.crawler`; no LexiQuest crash was established. |

- Main matrix: `matrix-23h2bquszecnr` ([console](https://console.firebase.google.com/project/vocab-learning-app-219ef/testlab/histories/bh.e89cc0471d6a1e63/matrices/4853335811671835649)).
- OPPO matrix: `matrix-35s0yq3pagezo` ([console](https://console.firebase.google.com/project/vocab-learning-app-219ef/testlab/histories/bh.e89cc0471d6a1e63/matrices/5446820697434711510)).
- Downloaded evidence: `output/integration-2026-10-23-final/firebase-test-lab/`.
- Evidence manifest: 45 files, SHA256
  `CDADE98BE4FFFA76C2532C71A3C9C140322B2C4B9484F6088886A14CE57CAEAD`.

Test Lab's aggregate success did not prove that every rendered Flutter frame
was healthy. Manual review of OPPO screenshots 26–27 found a Flutter error
screen immediately after Robo dismissed the focused “เพิ่มหมวดหมู่” dialog.

## Root cause and repair

The defect reproduced on the connected Vivo V2041 with a real IME:

1. Open the add-category dialog.
2. Focus its text field so the keyboard is visible.
3. Dismiss the route by tapping the modal barrier.
4. The application reported `A TextEditingController was used after being
   disposed` while the route exit animation still retained the text field.

The later `_dependents.isEmpty` assertion captured in Test Lab was a secondary
framework cleanup assertion. Flutter issue
[#194273](https://github.com/flutter/flutter/issues/194273) documents this
class of secondary assertion after an earlier widget failure.

The smallest complete repair removes route-local manually disposed controllers
from three dialogs and captures their values through `onChanged` instead:

- `lib/screens/categories_page.dart`: add-category dialog.
- `lib/screens/login_screen.dart`: password-reset dialog.
- `lib/screens/setting_screen.dart`: change-password dialog.
- `test/screens/offline_vocabulary_journey_test.dart`: focused-field barrier
  dismissal coverage.

A bounded source scan found no remaining local `TextEditingController` created
around an awaited `showDialog` and manually disposed immediately afterwards.

## Post-fix physical evidence

The same add-category / IME / barrier-dismiss sequence was executed on Vivo
V2041, Android 13, 1080x2408 after installing the fixed debug build. It returned
to the category screen without a Flutter error in the debug stream.

- Screenshot SHA256:
  `8720D9D5CA969C343778C9D163A08141FB4DCF5E43E598E4DAC3114DE1278986`.
- UI XML SHA256:
  `98127CBD603F552890766D358386AE0AE13D392003E896B5861FF6D506A4784D`.
- Vivo evidence manifest: 43 files, SHA256
  `7304598AC8B9B57842A4A4392F170BC35F81C2DBC0C77B26590E45FC1856ABCE`.

During the first post-fix `flutter run`, the installed package had versionCode
2001 while the local source has versionCode 1. The Flutter command recovered
from the downgrade by uninstalling the old package before installing the debug
build. That erased the earlier retained app data. The current Vivo installation
therefore contains a fresh debug data set; it must not be cited as retained-data
evidence. The earlier retained-data database-lock evidence remains in the
2026-10-23 checkpoint.

## Current-source verification

- Focused widget tests: **36/36 passed**.
- Full Flutter suite: **1598/1598 passed**, exit 0, 08:24.
- `flutter analyze --no-pub lib test tool`: no issues, exit 0.
- `dart format --output=none --set-exit-if-changed lib test tool`: 458 files,
  0 changed.
- `git diff --check`: exit 0; existing LF-to-CRLF notices remain warnings.
- Deterministic source manifest: 540 files from `lib/`, `test/`, `tool/`,
  `pubspec.yaml`, and `pubspec.lock`; SHA256
  `311D4F5FB7016BA76123060268C7EF793DEF670527E84B86C05C42C83F6E020B`.

The widget test protects route dismissal and tree cleanup, but the exact defect
required real IME/route timing to reproduce. The Vivo reproduction and post-fix
rerun are the primary fix evidence.

## Rebuilt signed release

Both release artifacts were rebuilt after the repair:

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| `build/app/outputs/flutter-apk/app-release.apk` | 111,751,324 | `F85B12E30220BCA48592FD9BD7321935DA83B94BB77218E64CE9518A13549F57` |
| `build/app/outputs/bundle/release/app-release.aab` | 99,641,198 | `D7301231F530B538D17EC330467B954832A20CB4B0739B0961B859534076E1F8` |

- `:app:validateSigningRelease`: build successful.
- APK `apksigner 37.0.0`: exit 0, one RSA-4096 signer, v2 verified.
- Certificate SHA256:
  `e1b00e17896bfb73fe0dc42429768b966465213d49a8a5165de06688cc8fdc1f`,
  matching `hosting/public/.well-known/assetlinks.json`.
- ZIP integrity: all 511 APK entries and all 542 AAB entries passed.
- AAB `jarsigner -verify -strict`: exit 4. It reports `jar verified`, then
  rejects the self-signed upload certificate as an untrusted PKIX chain and
  reports JarFile/JarInputStream inconsistencies. Play Console acceptance of
  this exact AAB hash remains a release-only gate.
- Release evidence JSON:
  `output/integration-2026-10-23-final/signed-release-post-controller-fix.json`,
  SHA256
  `21AA9A9BDD198A84EC98E0B56F0DBB2D75F1474328F6922D71E24C898DE6BB7B`.

The build still emits the known future Built-in Kotlin migration warning for
`firebase_app_check`, `flutter_tts`, `speech_to_text`, and
`workmanager_android`; it does not fail the current build.

## Remaining gates

- Firebase Test Lab physical quota is exhausted at 5/5 for the current Spark
  day. The fixed APK has not been rerun on OPPO/high/fold/tablet in the cloud.
  Rerun the post-fix physical matrix after the daily quota resets.
- Figma Cloud remains at R10; the validated R11 authority remains local because
  the Starter write hit payload/quota limits.
- Production research remains HOLD/default-off until the canonical permit,
  assignment, protocol/instrument pins, trusted issuer, withdrawal, upload,
  export, and deletion gates exist and pass.
- Play Console acceptance, live Google OAuth/App Check, production Firestore,
  provider/acoustic quality, stakeholder UAT, and real research authority are
  external release gates.

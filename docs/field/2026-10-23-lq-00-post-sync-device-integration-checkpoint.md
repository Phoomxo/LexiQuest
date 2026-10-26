# LQ-00 post-sync + device integration checkpoint

## Disposition

- วันที่: 2026-10-23
- Branch: `feature/associative-reading-loop`
- HEAD baseline: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`
- สถานะ: **ACCEPTED LOCAL INTEGRATION + ONE PHYSICAL DEVICE + LDPLAYER MATRIX**
- ขอบเขตนี้รับรอง engineering evidence ในเครื่องเท่านั้น ไม่ใช่ production release, real research enrollment/upload, signed distribution หรือ UAT

## Frozen source and artifacts

- Source manifest: 534 files จาก `lib/`, `test/`, `tool/`, `pubspec.yaml`, `pubspec.lock`
- Source-manifest SHA256: `95463EEDA4E8BA8B24582AC9B206E8CBE92C13795914F3609EB30252B9A26873`
- Universal debug APK: 249,948,944 bytes, SHA256 `A582A74A1A9E4DF818111D6364622A713EF805A78DB0E3AB23A9532DF91A55CB`
- LDPlayer x86_64 debug APK: 109,196,700 bytes, SHA256 `C9BD3376FC19574C34B386D31F72D41754CC0FBB6403F6A234654CF205313BF5`
- LDPlayer profile tool SHA256: `6E900EEDF102677AB3764DCACD4D558AF3840035A1C26E180EB402A2A21BC8B3`; syntax/apply/9-profile verification exit 0 and all profiles retain `adbDebug=1`

## Current-source verification

- `flutter test --no-pub --reporter compact`: **1555/1555 passed**, exit 0, 08:08
- `flutter analyze --no-pub lib test tool`: **No issues found**, exit 0, 8.8s
- `flutter build apk --debug --split-per-abi`: exit 0; generated armeabi-v7a, arm64-v8a and x86_64 artifacts
- Known non-blocking build warning: four plugins still apply Kotlin Gradle Plugin and require future Built-in Kotlin migration

## Sync defect found and repaired on real retained data

- Vivo replay exposed `SyncFailure(invalidPayload)` from three legacy `learningTimeSegment` outbox rows; the transaction previously rolled back before supported rows could progress.
- Root fix is the bounded quarantine path in `drift_sync_store.dart`: every `InvalidSyncPayloadFailure` becomes `permanentFailure/invalidPayload`, while state/corruption failures still throw and roll back.
- Focused sync evidence: 32/32; connected sync evidence: 276/276; final full suite included above.
- Post-fix retained-data replay preserved the three legacy rows as permanent failures and allowed supported achievement/attempt rows to enter acknowledged/in-flight states. No uninstall, app-data clear, row deletion or credential exposure was used.
- Fix checkpoint: `docs/field/2026-10-23-lq-07-legacy-outbox-quarantine-checkpoint.md`, SHA256 `33F52332C2529B46F6633BDB06F101AE07FF340EE1BEA40C5210CE4463946387`.

## Physical Vivo V2041 evidence

- Hardware: Vivo V2041, Android 13/API 33, ARM64, 1080x2408, density 440, RAM about 7.8 GB.
- Installed the current universal debug APK with `adb install -r -d`; retained app data because the device previously had a higher version code.
- Relaunch and four-root tab smoke kept `com.lexiquest.app/.MainActivity` resumed with no AndroidRuntime/FATAL/Unhandled Flutter error.
- 200% font-scale portrait and landscape captures completed without visible overflow or fatal log. Original device values were restored: font scale `1.0`, accelerometer rotation `1`, user rotation `0`.
- TalkBack service was enabled temporarily. App produced 38 accessibility nodes, 12 clickable nodes, 18 focusable nodes and one focused node with no app crash/error. Original values were restored: enabled services `null`, accessibility enabled `0`.
- Evidence lives under `output/`: Vivo home/tabs/font-200/TalkBack PNG and XML files. This is one physical mid-tier device, not low/high/fold hardware coverage.

## LDPlayer responsive matrix

- Result CSV: `output/ldplayer/matrix-results-v2.csv`, SHA256 `1FF1A530F0C986AF8EE41B39920A4181E732990D10E2C2684D1228C1EA1671AB`.
- **9/9 profiles passed** the real Login render/activity/accessibility/fatal-overflow gate:
  - 393x876 canonical Vivo
  - 360x800 compact lower
  - 412x915 compact upper
  - 600x960 tablet small
  - 800x1280 tablet small-upper
  - 1024x1366 tablet medium
  - 1280x800 tablet landscape
  - 800x479 and 800x480 height boundaries
- Each profile rendered `เข้าสู่ระบบ LexiQuest`, resumed MainActivity, produced 26-30 accessibility nodes and 6-7 clickable controls, with zero fatal/Unhandled/RenderFlex-overflow lines.
- At 800x479 the lower controls begin outside the initial viewport by design; an actual swipe exposed both `เรียนแบบ Guest` and `สร้างบัญชีใหม่`, with zero fatal/overflow lines.
- All nine LexiQuest instances were stopped after capture. Screenshots, trees and full logs are under `output/ldplayer/<profile>/`.

## Design/workflow completion boundary

- R11 is a locally completed design/prototype specification: 240/240 specimens, 942 routes, 41 starts, 40/40 critique score and mapping to 22 canonical families with the frozen 8/44 catalog.
- This does **not** mean 240 Flutter screens or every R11 workflow is implemented. The production app currently implements the adaptive four-root shell, local account/owner flows, vocabulary import, Quiz/SRS/Reading/Flashcards/Voice, Source Voice Result repair, Ask Lexi word draft, Ghost result, Progress, marketplace baseline, sync status and bounded consent/export slices.
- Remaining local engineering includes Reading/Flashcards result-repair parity, richer Source context/history/provenance, Tutor targeted practice/context, limited-feature disclosure/setup CTA, explicit settings controls, deeper adaptive/list-detail/hinge behavior, and the research permit/assignment/protocol/instrument/withdrawal/upload/export/delete gates.
- Figma Cloud synchronization of the latest R11 remains unverified; the older cloud README still identifies R5.

## External/release-only dependencies

- Not certified here: low-tier and high-tier physical Android devices, fold/tri-fold hinge hardware, signed release/App Check/Firestore/Google OAuth configuration, trusted full-account deletion, real research issuer/ethics/instrument authority, participant enrollment/upload and stakeholder UAT.
- These gates remain fail-closed for their affected flows and do not block independent local engineering with synthetic/emulator data.

## Next executable order

1. Complete local user-visible workflow parity: limited-state disclosure, Reading/Flashcards results and Tutor targeted practice.
2. Complete explicit Settings controls and offline/permission surfaces.
3. Implement the approved research contracts and gates with synthetic fixtures; do not reserve a migration until the active schema/ledger confirms one.
4. Re-run current-source integration and device matrix after relevant UI/runtime edits.
5. Sync the accepted R11 state to Figma Cloud and verify the shared artifact separately.

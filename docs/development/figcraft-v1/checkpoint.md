# Continuous execution checkpoint

Updated 2026-11-14, approximately 01:47 Bangkok. This is a running checkpoint, not a pause or completion.

## Workspace and authority

- Work only in `C:/Users/Phet/.codex/worktrees/figcraft-flutter-v1/LexiQuest`, branch `codex/figcraft-flutter-prototype`.
- HEAD/pushed `984e616438f264f4c54565ea0c7e0787272d7386`. Draft PR https://github.com/Phoomxo/LexiQuest/pull/16 targets `codex/current-code-20261113`.
- Active continuous Goal covers the two-screen/camera/set-A milestone and then S1–S7, with unchanged denominators 48 screens / 44 features / 64 packages. Do not close it after the first card.
- No merge, deployment, app publication, real research enrollment/upload, data clearing, or unrelated process killing. Signing configuration in ignored `android/key.properties` must never be staged.

## Verified baseline and artifacts

- Source `984e6164` passed full local Flutter tests, 1,786/1,786, in `build/milestone-full-test.txt`. Full static analysis was clean before the subsequent in-progress changes.
- Debug emulator APK SHA-256 `9df9ccd40f631d829e5e44f97af18de1db8dff13082202d0e537fec97dc9b2cd`.
- Signed release APK versionCode 27, source `984e6164`, SHA-256 `51d1e1fdf416abb303b754dd09e794b060370bc9be33661039cfce6f1c0a8563`, at `build/app/outputs/flutter-apk/app-release.apk`. It successfully updated the vivo version 26 using the same signing certificate. Existing three sets remained visible. No uninstall/clear occurred.
- Emulator native comparisons are `evidence/android-984e6164/home-comparison.png` and `library-comparison.png`, already shown in this chat. Raw captures are 624×1350 at density 256, 390×843.75 logical, displayed beside FigCraft at 390×844. Synthetic reference seed is `tool/figcraft/emulator-reference.sql`; it has an explicit `.quit` because this emulator's shell did not close SQLite stdin automatically.
- Independent Impeccable native critique is `evidence/android-984e6164/critique.md`, RETURN_FOR_FIX, 23/40 for the two screens. Main findings are root Add Word, global word search, data-aware home actions, shared headings, and due-set context.
- Real vivo evidence is in `evidence/vivo-984e6164/README.md` and `manifest.json`. Actual camera attempts had no savable translated proposal. The second proposed wombat at 15.2%, with ground truth unknown. Do not claim camera accuracy or camera-to-save success.
- Separate JSON fallback actually imported station/ticket into `FigCraft-A-20261114`, answered one incorrectly and one correctly, showed 50%, returned to A, then retained words and the result through offline process restart. B remained empty. Images 35/36/40/44 were shown to the user. Physical 200% observations and TalkBack activation smoke are recorded separately. TalkBack speech comprehension/full focus flow is not verified.
- Latest user steering explicitly allows actual-photo workflow testing separately from known-object accuracy, and explicitly requests editable manual correction from camera results into the original set. Never substitute import success for camera success.

## Current writers and unfinished changes

| Writer | Exclusive files/task | Current state |
| --- | --- | --- |
| Root | Home/theme, camera journey regression, integration and evidence | Home/theme 26 GREEN; 50 final correction journey/layout checks GREEN; 140 subsystem checks GREEN. Source frozen for analysis/full regression. |
| `s1_tests` | Vocabulary summary/search, library/set UI and tests | All async/scope/double-launch/nested-create findings corrected and independently accepted. Style-only analyzer corrections complete. Writer stopped. |
| `ground_routes` | Progress category context, CSV MIME, editable camera correction and tests | Mapped/unmapped/no-proposal manual form, owner/category/original-scope checks implemented. Tests include no writes after scope replacement. Source review accepted. Style-only analyzer corrections complete. Writer stopped. |
| `design_critic` | Independent critique/evidence, S5/S6 impact maps | Source corrections accepted; maps prepared without claiming S5/S6 acceptance. Phone control remains with root. Writer stopped. |

The new dirty source has not passed the full suite yet. Do not reuse the 1,786 count as proof of these changes.

## Next executable steps

1. Manual correction is implemented for mapped wrong guesses, unmapped proposals, and no-confident-result captures. The valid RED logs are `build/manual-camera-valid-red.txt`, `manual-camera-empty-red.txt`, and `manual-camera-mapped-red.txt`. Initial fixture deadlocks came from crossing the Drift owner serialization gate between fakeAsync and runAsync; synthetic owner replacement now inserts an explicit active owner row instead. The owned test processes were stopped and reconciled; none remain running.
2. Current integrated scanner/library/offline/SQLite camera journey and layout suite passes 50 tests in `build/correction-journey-verified.txt`, after the final two scope corrections. It includes both verified acceptance and manual apple-to-orange correction, explicit save, practice of orange, original A/session after SQLite reopen, and B unchanged. A second focused subsystem suite passes 140 tests in `build/subsystems-verified.txt`. Home/theme passes 26, and the inspected Windows layout golden has been updated with all four layout checks passing.
3. Nested destination owner adoption and open manual draft scope replacement both have valid REDs (`build/library-nested-owner-red.txt`, `build/manual-draft-scope-red.txt`), fixes, GREEN coverage, and independent accepted review. The initial full analysis found only 22 missing-brace style diagnostics, corrected without changing logic. Final full analysis is clean and the full Flutter suite passes 1,821/1,821 in `build/correction-full-test.txt`. Formatting all 27 changed/new Dart files requires no changes. Source and index match. Session 54964 has completed; the Flutter queue is idle. Evidence is `evidence/correction-local.txt`.
4. Review dispositions for home/theme, S2, S3 and S4 are accepted for their source slices. Native rendering and manual camera correction on the new APK remain separate. S5/S6 maps document remaining work, including missing live deletion composition and unreachable legacy screens; they are not completed cards.
5. Commit/push verified changes and follow current-head CI. CI run 43469278726 on `984e6164` failed formatting only in `test/screens/figcraft_library_test.dart`. That file has since been formatted, with additional behavior tests now pending. Linux home golden is still the old baseline and must be updated from an inspected actual Linux render on the new UI.
6. Build the corrected APK, update vivo without clearing data, repeat actual photo → editable correction → explicit save into A → practice that word → result → A → process restart. Verify B unchanged. Show the resulting images promptly. Known-object recognition accuracy remains separate if physical positioning is unavailable.
7. Recapture both comparison images on the corrected source and repeat 200%/dark/TalkBack checks honestly. Continue remaining S1–S7 cards; the first milestone does not end the Goal.

## Process and device state

- No Flutter/Gradle/build/code-generation job should be running after root consumes the manual-camera RED result. Serialize the next commands in this worktree.
- Vivo is at the library filtered to FigCraft. Restored font scale 1.0, Wi-Fi 1, mobile data 0, TalkBack/accessibility/touch exploration disabled as originally observed. Only root may now drive it unless ownership is explicitly reassigned.
- LDPlayer emulator `5590` contains only task-created LexiQuest fixture data. Current display override 624×1350, density 256, font 1.0. Original display was 1280×720/density 240 and font setting null. Restore the override when finished with captures. A previous system-UI ANR/slow shell recovered; use `adb shell -x` and explicit SQLite `.quit`. Installed APK hash was checked on-device. Do not reinstall merely because an acknowledgement is slow.
- An old task-owned read-only adb client 7624 was identified by its exact command and stopped after it stalled. The unrelated old adb client 14240 and the adb server were preserved.
- Build-generated plugin line-ending churn, `android/.kotlin/`, and `test/screens/failures/` are not delivery changes. Preserve them and stage only intended files. Do not broad-clean the workspace.

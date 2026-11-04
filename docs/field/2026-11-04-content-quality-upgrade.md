# APK34 preserved-data upgrade evidence

Status: APK33 to APK34 upgrade and explicit starter 1.0.1 installation passed.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
APK source commit: `50bc9847329436d10b10b17464740399f66297d3`.
Evidence root: `D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality/upgrade34`.

## Scope and device

This check owns only `emulator-5554`, AVD `LexiQuest_All44_API35`.
The AVD uses `D:/LexiQuest-Storage/maintenance/2026-11-03/emulator44/avd`.
Its identity, `ro.kernel.qemu=1`, completed boot, and `RUNNING_UNLOCKED`
user state were checked before device mutation.
The baseline package reports `versionCode=33`, `versionName=1.0.0`.
Receipts are `baseline33-device.json` and `baseline33-package.txt`.

No uninstall, application-data clear, AVD wipe, learning action, pack install,
cloud operation, or physical-device command occurred in the baseline stage.
The application was force-stopped before pulling SQLite, WAL, and SHM.
`verify_snapshot.py` inspected temporary copies and confirmed that the
original evidence files remained unchanged.

## Baseline results

`baseline33-inspected.json` records schema 25, SQLite integrity, and foreign-key
checks passing. The database contains 20 answers, 7 sessions, 12 words, 12 lexical
snapshots, and one installed starter 1.0.0 pack. The pack has no cached package
bytes, is not pinned, and retains revision 4.
All 7 research tables and research events are empty. Reminders are disabled.
The 45 ordinary outbox operations remain present.

`baseline33-verified.json` compares the baseline with itself to exercise all 29
canonical table comparisons and rejects all 6 negative verifier cases.
This self-comparison validates the checker and expected baseline only.
It is not evidence of a completed upgrade.

Baseline file SHA256 values are recorded in `baseline33/snapshot.json`.

| File | SHA256 |
|---|---|
| `lexiquest.sqlite` | `a3581adca3fab8cd44255d8dcb95addf2b4989ac8ef0922c86143b807ef0deb6` |
| `lexiquest.sqlite-wal` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `lexiquest.sqlite-shm` | `fd4c9fda9cd3f9ae7c962b0ddf37232294d55580e1aa165aa06129b8549389eb` |

The self-comparison receipt SHA256 is
`2b6616e42db1174e2b7aca01fd1e405d6fd3ee093c6f571f0e7f0df6c7482fa9`.

## Upgrade results

The artifact is
`D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality/package/lexiquest-1.0.0+34/lexiquest-1.0.0+34.apk`.
Its SHA256 is
`bbaa4eccdf72914f970429a2f5a34955d7faa31683fcce21b536811227b655e9`.
The hash of the installed `base.apk` matches exactly in `installed34-sha256.txt`.
The release manifest records certificate SHA256
`e1b00e17896bfb73fe0dc42429768b966465213d49a8a5165de06688cc8fdc1f`.

`adb -s emulator-5554 install -r` returned `Success` in `install34.log`.
`after34-package.txt` records versionCode 34 and the unchanged first install time.
The normal `.MainActivity` launched successfully in `launch34.log`.
The observed local-login action reached Home in `after34-local-home.png` and XML.
No learning or new-pack installation preceded `after34-before-pack`.

`upgrade34-verified.json` compares that snapshot against `baseline33`.
All rows in all 29 canonical tables are exactly equal, including all 20 answers
and 7 sessions. The old pack remains version 1.0.0 with its cache evicted and
revision 4. Research rows and research events remain zero. Reminders remain off.
The checker again rejects all 6 negative cases. All three snapshot files have
the same hashes as the baseline, and inspection leaves those files unchanged.
The upgrade receipt SHA256 is
`2b6616e42db1174e2b7aca01fd1e405d6fd3ee093c6f571f0e7f0df6c7482fa9`.

## Explicit new-pack installation

The catalog first showed bundled 1.0.1 and installed 1.0.0 separately in
`pack-catalog-before.png` and XML. The preview disclosed AI-assisted review,
pending independent human editorial review, British pronunciation, and the
distinction between file integrity and expert certification.
The observed install button was scrolled into view and tapped once.
`pack-installed101.png` records successful installation.
`pack-catalog-both-versions.png` and XML show both installed versions afterward.

The actual close card in `close101-card.png` and XML displays verb, ปิด,
`/kləʊz/`, the door definition, `Close the door, please.`, and `กรุณาปิดประตู`.
The screenshot was inspected directly. Its SHA256 is
`3aedeecf9d6d0e58a869bfc845d0fdc98f5241ade933a627996726be29702908`.

`after34-installed101` contains the final SQLite, WAL, and SHM snapshot.
`verify_installed101.py` reuses the temporary-copy reader and asserts that
every baseline row remains unchanged across the 29 canonical tables.
It checks 24 words, 24 lexical snapshots, 20 answers, and 7 sessions.
The two close entries have different word IDs. The original version retains
`Close the window, please.` and its original Thai translation.
The new version has the observed door example and matching Thai in storage.
The new cached package bytes match SHA256
`3f200d57f3350277ea73d04f27238f3134453e35260b53c01c9490ba58f31dfd`.

`installed101-verified.json` passes all assertions and records the expected
additions of one category, 12 words, one import, 12 import rows, 12 lexical
snapshots, one pack version, and 13 ordinary outbox operations.
All research rows and events remain zero, and reminders remain off.
The old pack is still unpinned with no cached bytes and revision 4.
The receipt SHA256 is
`3d633cf16a709403d62bc6d538b1f90d2f1afde1a6eb4fa8306131a2637a8758`.

The final database base-file hash matches the baseline because the new rows
remain in WAL. The WAL SHA256 is
`cb23af986d77d9b8d2300891d093a2ca87c7f5c670746d9df8e666812dc55d67`.
The SHM SHA256 is
`717318570af00b2c7c6ce2c54d7a2cf6fa94d6909c94c540e33bf8e10826ad5a`.
The verifier copies and reads all three files together.

## Final state and limits

The application was stopped for the final snapshot. The task then flushed
device writes and shut down only emulator-5554 with `emu kill`.
`emulator-shutdown.log` and `emulator-stopped.json` record successful shutdown
and the absence of its emulator process. The preserved AVD retains APK34,
both pack versions, and the original history.
The launch receipt remains `emulator-25691104-154712-process.json`.
`actions.jsonl` records UI and snapshot actions. `receipts-sha256.json` records
the main verification and screenshot hashes.

No Flutter, Dart, build, or shared test command ran in this task.
This task verifies the upgrade and new-pack content on one task-owned emulator.
Fresh-install acceptance belongs to the separate root-owned emulator check.
Physical devices, cloud operations, real research, billing, and production
readiness were not tested or authorized here. No public deployment occurred.

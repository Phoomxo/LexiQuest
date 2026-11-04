# APK34 preserved-data upgrade evidence

Status: APK33 baseline verified. APK34 upgrade is awaiting the artifact.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
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

## Handoff state

The task-owned emulator remains running under launcher PID 19732.
Its process receipt is `emulator-25691104-154712-process.json`.
The matching stdout and stderr logs use the same prefix.
The application is stopped. The next step is to receive APK-ready, verify the
artifact, install APK34 with `adb install -r`, launch the normal application,
and compare a new snapshot before learning or installing starter 1.0.1.

No Flutter, Dart, build, or shared test command ran in this task.
APK34 upgrade, new-pack UI verification, physical-device testing, and production
readiness remain unverified at this checkpoint.

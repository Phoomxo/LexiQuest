# APK35 preserved-data upgrade evidence

Status: actual APK34 to APK35 upgrade passed with all 29 canonical tables intact.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
APK source commit: `fbcf6ee35d2f344896d5a1f80e7aa744c1716bdd`.
APK source tree: `cea136f0b0f3e3e832beb7cd892dc6c43be5f54e`.
Evidence root: `D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality/upgrade35`.

## Scope

This task owns only `emulator-5554`, AVD `LexiQuest_All44_API35`.
Its persistent data contains both starter versions from the completed APK34
check. The upgrade must preserve 24 words, 24 lexical snapshots, 20 answers,
7 sessions, and all rows in the 29 canonical tables.
It must retain pack bytes, hashes, revisions, and cache state exactly.
All research rows and events must remain empty, and reminders must remain off.
No uninstall, application-data clear, AVD wipe, new learning, or pack installation
occurred during this check.

## Comparator preparation

`verify_upgrade35.py` reuses the existing snapshot reader and research checks.
The reader copies SQLite, WAL, and SHM into a temporary directory before opening
the database and verifies that original evidence hashes remain unchanged.
The comparator checks table columns and exact multisets of every row across
the existing 29-table preservation list. Its comparison logic does not assume
that only one pack is installed.

Separate baseline assertions require starter 1.0.0 at revision 4 with no cached
bytes and starter 1.0.1 at revision 1 with its cached bytes intact.
Both packs are unpinned. The cached 1.0.1 bytes must match SHA256
`3f200d57f3350277ea73d04f27238f3134453e35260b53c01c9490ba58f31dfd`.

Preparation used the retained `upgrade34/after34-installed101` snapshot as both
inputs. `verifier-preparation.json` records exact equality, 24 words, 20 answers,
7 sessions, 58 ordinary outbox operations, empty research, and disabled reminders.
This self-comparison proves the comparator accepts the expected baseline.
It does not prove that APK35 preserves data.

The checker also creates six isolated in-memory copies and changes one row in
each. Every change is rejected by the same comparator.

| Negative case | Mutation |
|---|---|
| Answer | Flip one stored answer's correctness |
| Pack bytes | Replace cached 1.0.1 package bytes with zero bytes |
| Pack revision | Increment the old 1.0.0 revision |
| Research consent | Insert one explicitly synthetic consent row |
| Research outbox | Change one ordinary operation to research consent |
| Reminder | Enable the stored reminder |

`preparation-sha256.json` records these SHA256 values.

| Artifact | SHA256 |
|---|---|
| `verify_upgrade35.py` | `c6b573d47d844857351ca48c1bea2b2c7d000c6b639791cd86199a9065c00476` |
| `verifier-preparation.json` | `a4aeb73cffe66f48dfd0e6f47420cd8e2cb823155c68820a8a1d2490b62eec91` |

An independent read-only review accepted the comparator with no must-fix
findings. It checked exact row and package-byte comparison, revisions, safe
snapshot copies, and actual single-row mutations in all six negative cases.

## Actual upgrade

The owned All44 emulator started hidden without audio or snapshots.
`baseline34-device.json` confirms its AVD identity, `ro.kernel.qemu=1`, completed
boot, unlocked user, and installed versionCode 34. `baseline34-package.txt`
records the original installation metadata.
The freshly pulled `baseline34` snapshot matches the retained APK34 canonical
data exactly in `baseline34-verified.json`. Its SQLite, WAL, and SHM hashes also
match the retained snapshot. The six negative verifier cases pass again.

The signed artifact is
`D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality/package/lexiquest-1.0.0+35/lexiquest-1.0.0+35.apk`.
Its SHA256 is
`894d83c124b3bd9691f23dd966dd1b1f950a5db40cd7670f7a35177eaf130353`.
The on-device `base.apk` hash matches exactly in `installed35-sha256.txt`.
The release manifest records signing-certificate SHA256
`e1b00e17896bfb73fe0dc42429768b966465213d49a8a5165de06688cc8fdc1f`.

`adb -s emulator-5554 install -r` returned `Success` in `install35.log`.
`after35-package.txt` confirms versionCode 35 and unchanged first-install time.
The normal `.MainActivity` launch succeeded in `launch35.log`.
The observed local-login button reached Home in `after35-local-home.png` and XML.
The screenshot was inspected directly. No exercise or content change occurred.

`after35-before-learning` contains the final snapshot taken after local login.
`upgrade35-verified.json` compares it against the fresh `baseline34` snapshot.
All rows and columns in all 29 canonical tables are exactly equal, including
the complete package bytes and revision fields of both installed packs.
The result preserves 24 words, 24 lexical snapshots, 20 answers, 7 sessions,
and 58 ordinary outbox operations. Starter 1.0.0 remains unpinned at revision 4
with its cache evicted. Starter 1.0.1 remains unpinned at revision 1 with its
cached bytes intact. All 7 research tables and research events remain empty.
Reminders remain disabled. All six negative cases are rejected again.
The original evidence files remain unchanged during verification.

The physical database files differ between the before and after snapshots.
The after snapshot has an empty WAL and a larger main database.
The exact canonical row comparison passes despite those file-level changes.
Both sets of file hashes are recorded in `upgrade35-verified.json`.

`receipts-sha256.json` records the main result hashes.

| Artifact | SHA256 |
|---|---|
| `baseline34-verified.json` | `50a8323d811efca990f0955c30c157d0df9985ea7a0b5eb8938dfb8ed4415926` |
| `upgrade35-verified.json` | `7803c36b2a94454b86a6fc38ab76a28dc0fd0cdef2ccec730559ca1437f16015` |
| `after35-local-home.png` | `7741924c5f9348e83b6c2edab8a524ef64ba2d4fc4895cb5e1d9a7adadbdceaa` |

The after-snapshot SQLite SHA256 is
`3ec4265ad49f5576327305dc64a99df95f8f38276f265ef47b76680ae4812843`.
Its empty-WAL SHA256 is
`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
Its SHM SHA256 is
`fd4c9fda9cd3f9ae7c962b0ddf37232294d55580e1aa165aa06129b8549389eb`.

## Final state and limits

The application was stopped for the final snapshot. The task flushed device
writes and stopped only emulator-5554 with `emu kill` at 09:46:25 UTC.
`emulator-shutdown.log` and `emulator-stopped.json` confirm successful shutdown,
absence from ADB, and absence of the owned emulator process.
The persistent AVD retains APK35, both starter packs, and the original history.
Its launch receipt is `emulator-20261104-094306-process.json`.
`actions.jsonl` records the local-login and snapshot actions.

No Flutter, Dart, build, physical-device, cloud, billing, or real-research action
ran in this task. Root separately owns fresh-install and Reading keyboard
acceptance. This check establishes upgrade preservation and local Home launch
on one task-owned emulator. It does not establish production readiness.

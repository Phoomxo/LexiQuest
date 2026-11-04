# APK35 preserved-data upgrade evidence

Status: comparator prepared and checked on the retained APK34 snapshot.
The actual APK34 to APK35 upgrade awaits the signed artifact.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
Evidence root: `D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality/upgrade35`.

## Scope

This task owns only `emulator-5554`, AVD `LexiQuest_All44_API35`.
Its persistent data contains both starter versions from the completed APK34
check. The upgrade must preserve 24 words, 24 lexical snapshots, 20 answers,
7 sessions, and all rows in the 29 canonical tables.
It must retain pack bytes, hashes, revisions, and cache state exactly.
All research rows and events must remain empty, and reminders must remain off.
No uninstall, application-data clear, AVD wipe, new learning, or pack installation
is part of this check. The device will remain stopped until APK35 is ready.

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

## Next executable check

After APK35 is ready, launch only the owned All44 emulator and verify its AVD
identity, emulator property, completed boot, unlocked user, and installed APK34.
Capture a new baseline before installation. Confirm it matches the retained
APK34 canonical data. Install the verified APK35 with `adb install -r`, launch
the normal application, and use local login. Capture the after snapshot before
any learning or content mutation and run the comparator against the new baseline.
Record installed version, actual APK hash, comparison receipts, and shutdown.

No emulator or ADB command ran during preparation. No Flutter, Dart, build,
physical-device, cloud, billing, or real-research action ran in this task.
Actual APK35 behavior and production readiness remain unverified.

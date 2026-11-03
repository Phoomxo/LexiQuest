# Emulator acceptance of the 44 capabilities

Baseline docs/source HEAD: `19c4c445`; application source: `00d6c8ea`.
Target: signed offlineTrial26 on isolated LexiQuest_All44_API35 AVD, followed by
bounded responsive checks where useful. Preserve existing device data and all
untracked files. Use only synthetic learning data. No real account, provider,
payment, Cloud A/Billing, Research enrollment or upload is authorized here.

## Execution plan

- Read poteto-mode principles. Done.
- Phase A: Frame. Every frozen f01-f44 gets an explicit emulator workflow verdict
  and evidence, with external or synthetic-only coverage identified honestly.
- Phase B: Design the workflow. Root owns emulator/UI actions, integration tests
  and fixes. Read-only agents map routes and inspect isolated audio capabilities.
  One emulator and one Flutter/build writer at a time; no phone actions.
- Phase C: Run the loop. Establish emulator identity and artifact hash, inspect
  existing state, exercise grouped workflows, reproduce defects before fixes,
  and rerun affected workflows after a correction.
- Phase D: Keep the audit trail. Retain screenshots, UI trees, exact actions,
  package hashes and per-feature verdicts under the task's local evidence root.
- Phase E: Verify and hand back. Review all44 entries. Automated tests supplement
  emulator evidence; they do not replace or masquerade as emulator execution.

## Acceptance boundaries

The host microphone is disabled and read back before testing. Camera or microphone acceptance
requires verified synthetic input isolation. Emulator sound generation, captured
waveform, recognizer output and human audible quality are distinct observations.
No assumption that the assistant can hear or speak through this environment is
treated as a capability check. Physical stylus, OEM battery behavior, Bluetooth,
real provider and Research authority cannot be certified by an emulator alone.

Evidence root:
`D:\LexiQuest-Storage\maintenance\2026-11-03\emulator44`.

## Grounding and environment

The existing LexiQuest_API_35 contains version14 with a different signature.
Android correctly rejects an in-place26 update. Preserve that AVD/data; a new
task-owned AVD uses the same installed API35 Google APIs image and stores data
under the evidence root. Camera uses an emulated image, not a host webcam.

The SDK gRPC interface provides emulator-only PCM capture and synthetic PCM
microphone injection. A task-local client uses localhost token authentication.
The real host microphone is explicitly disabled and read back as disabled before
app testing. Waveform presence is not speech recognition or human-quality proof.

Fresh offline26 cannot generate Cloze content or enter trusted Research StudyHost.
Record unavailable/default-off outcomes honestly. Separate synthetic emulator
fixtures may exercise those success paths without changing the release profile.

## Release26 observations

Evidence is scoped to the signed APK26, not to a newly built application. No
runtime source has been changed in this acceptance task. `integration_test` is
an SDK dev dependency used only for a separate synthetic runner.

The fresh emulator owner installed the 12-word starter pack, saved `night`, and
filed one explicitly synthetic local word report. Definition choice completed
with one assisted wrong answer. Matching completed with four correct and one
wrong attempt, reporting 80 percent without advancing recall rewards. A ten-word
quiz completed at 10/10; leaving and resuming its first acknowledged answer did
not duplicate it. SRS, dictation and word scramble completed. Typed definition
completed at 1/1. The enabled interaction-time setting produced 4 seconds for
dictation and 11 seconds for typed definition, rather than elapsed wall time.

Achievements unlocked from real synthetic learning actions. The shop reported
10 earned coins and rejected an 80-coin purchase with the correct 70-coin deficit.
Companion hide/show, profile persistence, changing recommendations, pack search,
A1 filtering and dark/reduced-motion settings were exercised. Wi-Fi and mobile
data were disabled and read back as zero; cold startup returned to local login,
then restored the same local learning state and dark appearance.

The emulator gRPC output contained PCM during `night` and `book` playback.
This verifies audio output, not word recognition or perceived quality. The real
host microphone was disabled and verified. TalkBack bound successfully on the
emulator, but the limited navigation/PCM check is not whole-app TalkBack UAT.
Home was inspected at 200 percent font scale; the original scale was restored.

### Findings requiring correction or further acceptance

1. **Nested Dashboard navigation fails.** Dashboard -> Review Center -> Manage
   saved words -> Back replaces Review Center with "กิจกรรมไม่พร้อมใช้งาน".
   Evidence: 073-076. Read-only source review traces `_MasteryChildVisibility`
   treating a normal nested cover as launch invalidation, through `_coveredChild`
   and `binding.invalidateLaunch()`. The Dashboard builder then rejects the old
   generation. Preserve owner/dependency invalidation when correcting this.
2. **Achievement share does not complete in this route.** Card preview exists,
   but pressing share disables controls without an Android chooser. Evidence:
   063-066. Android focus/resumed activity was the app. The same parent launch
   invalidation is a candidate; this cause has not been independently confirmed.
3. **Mixed locale.** Focus Timer, Review Center, Saved Words, interaction-time
   settings and portions of the dashboard are English in the otherwise Thai UI.
4. **Transient calendar rejection.** An immediate return-and-open sequence showed
   Activity unavailable (070); a stable retry opened the calendar with correct
   16 attempts, 14 correct answers and 3 completed sessions (072). Do not call the
   initial observation a permanent calendar-data failure.
5. **Reminder update and cancellation diverge from Android.** Initial permission
   and 04:59 Africa/Abidjan scheduling succeeded (144). Changing to 05:02 persisted
   in the UI but returned a reopen error (146,153,154); Android retained the old
   alarm. Disabling also returned an error while the UI showed off (155). Cold
   restart recreated the old native alarm. Source review confirms preference
   commit precedes the native schedule/cancel boundary, which can reject owner,
   token or revision. The exact rejection and SQLite cause are not yet proven.
6. **Cache deletion is not durable.** Unpin/delete (148-150) removed cached bytes
   within the session and preserved vocabulary/history (152,161). After cold
   restart the pack returned pinned with valid bytes (174,180), without install
   or repair. Source inspection found no automatic bundled reinstallation.
   The correlated reminder/cache failures require a shared persistence-boundary
   investigation. Different Drift/native SQLite journal handling is a hypothesis,
   not a confirmed engine diagnosis. f40 and f44 fail durability acceptance.

No app fixes are included: the current instruction authorizes testing. These
findings are not waived by existing unit-test success.

### Evidence integrity

`feature-results.json` contains all frozen f01-f44 IDs, per-feature observations,
and screenshot/XML references. `actions.jsonl` preserves UI actions. The helper
uses `PASS_OBSERVED` only for the workflow specified in that row, not every path
or edge case of the entire capability. `PARTIAL` identifies unexecuted portions.
Neither status substitutes for real-provider or physical-device acceptance.
The helper
asserts the task AVD identity before control. Snapshot125 is invalid: Android
returned a null UI root during cold startup and the first helper version pulled
the previous XML. It is excluded from verdicts. The helper now asserts successful
fresh dumping before pulling, and valid snapshots126-127 establish restart state.

The quiz driver stopped safely at an unmapped word (`close`); remaining questions
were completed through inspected UI. That helper failure is not an app failure.

## Synthetic native runner

`integration_test/emulator_synthetic_workflows_test.dart` reuses existing Cloze,
scratchpad and assessment fixtures. It is built and installed only on the fresh
`LexiQuest_Synthetic_API35` AVD, preserving release26 and its data on
`LexiQuest_All44_API35`. The native selection excludes a host-only source-file
inspection test; it does not skip an observed product failure.

Static analysis of the runner passed. Debug APK build passed. The first native
selection passed three of four tests: both Cloze variants and assessment. The
scratchpad case failed because Save was not hit-testable after typing. A second
bounded native selection passed both optional-ink/undo/clear and frozen-ink ACK
scenarios. Only assertion diagnostics changed between runs; no app behavior or
test navigation was changed. The initial intermittent failure remains open.
Logs: `synthetic-tests.log` and `scratchpad-diagnostic.log`.

Run the bounded native selection with:

```powershell
flutter test integration_test/emulator_synthetic_workflows_test.dart -d emulator-5554 --name '^(accepted ClozeVariant\.(choice|typed) renders one masked gap and finishes actual saved facts|Typed Cloze freezes ink at Save and compares it only after the real typed ACK|canonical questions and controls remain score-free through completion)$'
```

This selects four existing scenarios. Do not run this aggregate entry without
the filter: its imported assessment suite also registers host source inspection.
The assessment fixture does not establish persistent research storage, trusted
real authority, consent approval, or upload readiness.

## Feature disposition

This table is a bounded acceptance record, not a claim of exhaustive coverage.
Detailed observations and untested variants remain in `feature-results.json`.

| ID | Capability | Emulator verdict |
| --- | --- | --- |
| f01 | Learning pack catalog | PASS_OBSERVED |
| f02 | Pack detail | PASS_OBSERVED |
| f03 | Rich lexical card | PASS_OBSERVED |
| f04 | Content quality/version | PASS_OBSERVED |
| f05 | Common lesson shell | PASS_OBSERVED |
| f06 | Flashcards | PASS_OBSERVED |
| f07 | Meaning quiz | PASS_OBSERVED |
| f08 | Definition quiz | PASS_OBSERVED |
| f09 | Cloze | PASS_SYNTHETIC |
| f10 | Matching | PASS_OBSERVED |
| f11 | Typed recall | PASS_OBSERVED |
| f12 | Handwriting | PASS_SYNTHETIC_WITH_ISSUE |
| f13 | Native mode integration | PARTIAL |
| f14 | Flashcard-first recommendation | PASS_OBSERVED |
| f15 | Recall ladder | PARTIAL |
| f16 | Session configuration | PASS_OBSERVED |
| f17 | Immediate feedback | PASS_OBSERVED |
| f18 | Distractor explanation | PASS_OBSERVED |
| f19 | Hints and context | PASS_OBSERVED |
| f20 | Saved words | PASS_OBSERVED |
| f21 | Content reports | PASS_OBSERVED |
| f22 | Review center | FAIL |
| f23 | Focus timer | PASS_WITH_ISSUE |
| f24 | Learning-time capture | PASS_WITH_ISSUE |
| f25 | Calendar/analytics | PASS_WITH_ISSUE |
| f26 | Goal/countdown | PASS_OBSERVED |
| f27 | Reminder | FAIL |
| f28 | Assessment/comparison | PASS_SYNTHETIC |
| f29 | Evidence-based quest | PASS_OBSERVED |
| f30 | Gentle streak | PARTIAL |
| f31 | Achievements | PASS_OBSERVED |
| f32 | Avatar/cosmetics | PARTIAL |
| f33 | Companion | PASS_OBSERVED |
| f34 | Achievement share | FAIL |
| f35 | Preference/goal quiz | PASS_OBSERVED |
| f36 | Personal profile | PASS_OBSERVED |
| f37 | Recommendation panel | PASS_OBSERVED |
| f38 | Accessibility | PARTIAL |
| f39 | Motion/theme | PASS_OBSERVED |
| f40 | Local-first | FAIL |
| f41 | Controlled rollout | PASS_OBSERVED |
| f42 | Today hub | PASS_OBSERVED |
| f43 | History | PASS_OBSERVED |
| f44 | Offline content manager | FAIL |

## Final acceptance and handoff

All 44 ledger entries have observations. This is not full acceptance: 28 pass the
specified release workflow, 3 pass with issues, 2 pass only synthetic native
fixtures, 1 synthetic case passes on rerun with an unresolved intermittent
failure, 5 fail, and 5 have partial coverage. The five partial entries are native
generated modes (f13), all recall-ladder paths (f15), multi-day streak behavior
(f30), purchases of earned-coin cosmetics (f32), and whole-app accessibility
(f38). No app code was changed to hide these findings.

Further observed checks: malformed JSON import rejected without an added pack
(179); local report ID and details survived restart (158); saved word removal
worked (159-160); month/prior/today calendar navigation retained 20 answers,
18 correct, 7 completed sessions and 15 interaction seconds (162-165); 181-minute
goal rejected, 15 minutes and 2026-12-31 accepted with 58-day countdown (167-169);
optional profile skip returned to study (171); free theme equip kept coin balance
(173). No real-money transaction occurred.

Review disposition: read-only independent review checked the 44 IDs, referenced
evidence, runner/fixture isolation and source explanations. It confirmed the
nested-route invalidation and absence of automatic cache restoration. It did
not certify a SQLite root cause or waive the intermittent scratchpad failure.
Final analysis of the integration runner and diagnostic test file passed;
`git diff --check` passed. The native runs are 3/4 followed by 2/2, with the
original failure retained. Do not add these as six independent passing cases.

The task AVD's notification permission was revoked and the app force-stopped.
Android reported zero active LexiQuest RTC alarms afterward. Font scale is 1.0
and TalkBack is disabled. This containment is not a pass for in-app cancellation.
Both task AVDs preserve their data; the physical Vivo and original AVD were not
modified. No Cloud A/Billing, provider, public rollout, real payment, real
participant enrollment or Research upload was performed.

Next executable work, under implementation scope: reproduce and correct the
shared persistence/native reminder boundary before claiming local durability;
then repair nested child-route invalidation and retest share. Preserve owner,
consent and revision guards. Re-run enable/change/disable/restart plus cache
delete/restart together, then the affected all44 workflows. Investigate the
scratchpad hit-test intermittency without weakening the assertion.

Checkpoint worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`,
branch `codex/remaining-system-readiness`. Task changes are this report,
`pubspec.yaml`, `pubspec.lock`, the new synthetic integration entry, and diagnostic
assertion detail in `test/screens/typed_cloze_scratchpad_test.dart`. Existing
untracked critique/failure artifacts are preserved. No Flutter/test process or
task emulator remains running at handoff. Changes are local and uncommitted.

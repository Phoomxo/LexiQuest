# Critique completion: internal trial 36

Status: application verification passed; signed artifact acceptance is pending. This record does not certify a public release.

## Intent and source

The approved task closes the five P2 findings in `.impeccable/critique/2026-11-04T23-19-27Z__lib.md`.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`. Starting HEAD: `ce058a45ad6c707e69b1d80920d2425bdd034e31`.
APK35 packaged source: `fbcf6ee35d2f344896d5a1f80e7aa744c1716bdd`.

Cloud A, Cloud Billing, public rollout, real charging, real provider calls, and real Research enrollment are excluded.
The approved 8/44 catalog, schema25, EvidenceContext, and EventEnvelopeV2 remain unchanged.
Five pre-existing critique files and 16 failure images remain untouched.

## Task cards and impact

| Card | Outcome and owner | Write set | Acceptance | State |
|---|---|---|---|---|
| R | Reading result and repair, honest optional sentence, simpler Home; Reading worker | choose_mode_screen, associative_reading_session_screen, quiz_screen, affected screen tests | Completed and wrong-answer flows, single original session, owner/content/route guards, optional skip, Reading-only gate | Done |
| T | Explain unavailable Tutor before key entry; Tutor worker | gemini_settings_screen, ai_tutor_screen, their tests | Null scope makes no load/configure call; recovery and scope loss clear stale input; connected behavior remains | Done |
| P | Compact pack preview; pack worker | learning_pack_catalog_screen and affected pack tests | Install discoverable at 320px, warning visible, complete expandable provenance, large text, existing confirmation/owner guards | Done |
| V | Integrate, independently review, verify and package; root | This record, decision trail, native runner and affected golden | Focused and full host checks, analysis, native affected flows, signed APK36 fresh/upgrade evidence | Running |

The root is the only Flutter/Dart/build runner. Each production file has one writer.
Implementation begins after regression tests demonstrate the defects. All writers pause for a consistent verification snapshot.

## Design decisions

Reading uses the existing `LearningSessionResult`, `QuizWord` snapshots, `ScoreScreen`, and `QuizScreen`.
Home route visibility is a launch condition. Owner, dependency, generation, lifecycle, feature and content validity survive the app's own child routes.
Foreign routes and stale owners must still retire the result. Reading results do not depend on the Quiz feature; only repair does.
The sentence exercise remains optional, unscored, and unsaved, with an explicit skip using the existing checkpoint path.

Tutor readiness uses the existing nullable `GeminiScope`, epoch, and invalidations. No parallel availability authority is added.
The message describes the missing trusted online account context without claiming that a key can repair it.
Pack preview uses existing Material expansion to retain full original provenance while moving installation before long details.
Home moves Reading earlier and collapses the existing motivation panels after activities; reward and learning authorities do not change.

Laziness Protocol favors the existing result, scope, and Material widgets over new domain layers.
Prove It Works requires native execution, a signed artifact check, and database comparisons rather than treating compilation as acceptance.

## Throughput checkpoint

1. Baseline source and APK35 evidence ground the five issues; Tutor needs an actual unavailable-screen baseline.
2. Three disjoint writers cover Reading/Home, Tutor, and pack preview in parallel.
3. Shared Home edits stay with one writer. Root serializes tests, goldens, Android builds and packaging.
4. The smallest complete deliverable is five fixes plus affected-flow acceptance and a new internal APK, with no new backend or schema.

## Verification record

Evidence directory: `D:/LexiQuest-Storage/maintenance/2026-11-05/critique-completion`.
APK35 baseline `baseline35-005.png` reproduces the false cancellation without entering any key or granting provider consent.
Tutor and pack focused tests pass 76 cases (`tutor-pack-green.log`). These precede the final integrated snapshot.
Initial Reading checks pass 71 cases and expose one stale lazy-list expectation after moving activities (`reading-green1.log`).
An independent review also identifies nested mistake practice as an owned route that must retain the Home flow context.
The follow-up repairs that callback propagation and exercises the full repair-to-result loop before acceptance.
The Tutor/pack independent diff review finds no actionable defect. Root refines the prerequisite copy into plain Thai.
The initial comment review finds no new suppressions or comments requiring removal.
The upgrade emulator baseline matches APK35 SHA-256 and all 29 preserved tables: 24 words, 20 answers, 7 sessions, and both starter versions.
These are pre-upgrade facts; APK36 preservation is still pending.
The nested repair test passes after waiting for the complete route-pop chain: three completed sessions and three answer attempts (`nested-repair-green.log`).
The broader Reading result suite then passes 14 cases (`reading-final.log`), including delayed launch cancellation, owner/content changes and foreign cover.
Root replaces the temporary child-active flag with the actual owned route to cover the gap before Score, and strengthens the asynchronous negative test.
Those last changes must pass the native and full-host checks below; the earlier 14-case run does not attest them.
Only the intentional Home large-text golden is regenerated and visually reviewed (`home-golden-update.log`). Original failure images remain intact.
The first analyzer pass reports five issues; root fixes mounted-context handling and required braces before native compilation.

## Review disposition

- Tutor/pack: no actionable defect from independent review; original metadata and trust guards remain.
- Reading: nested Quiz repair and report-close route restoration findings are fixed. Independent re-review accepts both changes.
- Pending Reading launch: a transient foreign cover retires preparation. The owned-route reference also protects the gap before Score.
- Comments/suppressions: no new comments or suppressions requiring removal. No broad comment cleanup is part of this task.

Final acceptance and artifact receipt: pending.

Native environment recovery: the first Android launch is killed by ActivityManager's process-start timeout before any test runs.
Host free memory is about 1.6 GB with two emulators. The idle upgrade emulator is stopped without resetting its data, raising free memory to about 4.1 GB.
Root stops only the waiting task-owned Flutter process and its logcat child, then reruns on the single emulator.
`native36.log` and `native36-start-timeout.txt` retain the failed startup evidence; they are not passing-test receipts.
The debug installation replaces the synthetic 5556 app only. Its APK35 database is saved in `baseline35-before36`, and upgrade acceptance uses the untouched 5554 dataset.

Native acceptance passes 104 cases on the final application source (`native36-single-emulator.log`, exit 0).
`native36-receipt.json` pins the log hash and 1,094 unchanged input hashes in `native36-source.json`.
Coverage includes Reading checkpoint/keyboard/result/repair, optional Stage5, pending and stale route rejection,
starter preview at 320px and 2x text, and Tutor unavailability/consent/draft/cancellation behavior with synthetic adapters.
This is Android execution of the affected suites, not a claim that all 44 capabilities were repeated on a normal APK.
Both emulators are stopped during the full host run, which uses four test workers to bound memory pressure.

The first full host run passes 5,715 cases and fails one Definition configuration test, with zero changed input hashes.
The focused reproduction fails at the same `pumpAndSettle` call after the dropdown is already visible (`definition-wait-red.log`).
The catalog retains an indeterminate busy indicator while awaiting the configuration dialog; global animation settlement is not an appropriate readiness condition.
The test now waits for a tappable menu option, then its selected value and the menu's removal. All configuration, owner, session, answer and Score assertions remain.
Both Definition flow cases pass (`definition-wait-green.log`). Application source is unchanged after the 104-case native run, as recorded in `native36-relevance-after-host-test-fix.json`.
The full host suite is rerun on the final test snapshot under the `delivery36-final` evidence prefix.

The final run passes 5,716 host tests and reports no analyzer issues, both exit 0.
`full-host-delivery36-final-result.json` records 1,094 input hashes with zero changes during verification.
The Definition test-only change also passes independent review with every original learning-data assertion retained.
The signed offlineTrial36 artifact must now be built from the committed matching source and checked through upgrade and fresh-install flows.
Only task-owned emulators `LexiQuest_Synthetic_API35` (5556) and `LexiQuest_All44_API35` (5554) may be used.
The physical Vivo is excluded from this run.

APK35 evidence is historical baseline, not evidence that these changes pass.
All44 baseline is from APK33, followed by affected-flow checks through APK35. This task will state exactly what is rerun.

## Release-only dependencies

Independent editorial/CEFR review, real-provider validation, whole-app physical-device voice/TalkBack,
OEM reminder behavior, and external Research authority remain separate from this internal offline trial.
No efficacy or production-readiness claim follows from synthetic acceptance.

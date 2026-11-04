# Content quality completion

Status: content and keyboard corrections pass current host/native checks; signed candidate35 acceptance pending.
Worktree: `C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`.
Branch: `codex/remaining-system-readiness`.
Baseline: `a5e46226247ef09e7faa8cc12248fe483d7034db`.

## Intent and done predicate

Audit every application-owned learning-content source shipped or reachable in
the current offline trial. Correct demonstrated English/Thai meaning, grammar,
part-of-speech, pronunciation notation, example, distractor and answer defects.
Trace content into its actual exercise and preserve existing accepted-plan pins
and installed historical content. Inventory external/generated/user-owned inputs
separately and check their existing validation boundaries. Do not claim that a
structural validator proves linguistic quality or that AI review is independent
professional certification.

Completion requires an exhaustive source inventory, an item-level review ledger
for finite shipped corpora, disposition for each confirmed finding, focused
regressions, independent review, current-source integration checks and a trial
artifact with verified new content and preserved-data upgrade behavior.
The frozen 8/44 catalog, schema25 and evidence contracts remain unchanged.
Cloud A/Billing, public deployment, real charging and real Research enrollment
remain excluded. No provider configuration is approved. Physical-device testing
is not implied; use only task-owned emulators.

## Playbook and throughput

- [x] Read the Principles section of the poteto-mode skill.
- [x] Phase A: Frame.
- [x] Phase B: Design the workflow.
- [ ] Phase C: Run the loop.
- [ ] Phase D: Keep the audit trail.
- [ ] Phase E: Verify and hand back.

1. Inventory concrete sources and callers before choosing edits. Quantify each
   finite corpus; distinguish training material, fixtures and shipped content.
2. Parallel read-only slices cover source/caller mapping, starter-pack language,
   and other bundled language data. Root reviews provider prompts and integration.
   Configured Grok/Claude models are unavailable; available Terra/Astra models
   provide independent review without claiming cross-family certification.
3. Record confirmed defects and the smallest complete write set. Reproduce
   semantic or versioning failures before changing runtime behavior. Reuse pack
   versioning and existing content/research authority boundaries.
4. Apply source corrections and bounded checks. Root serializes Flutter/Dart,
   generation, tests and builds. No parallel shared-output mutation.
5. Freeze source, obtain independent review, run relevant full integration gates,
   then verify the actual trial artifact and upgrade behavior.
6. Preserve the source/item review ledger, test receipts and decision trail;
   report exact remaining external limitations.

## Task cards

| Card | Writer | Acceptance | State |
|---|---|---|---|
| C1 source inventory | Root aggregates read-only slices | Every owned shipped source mapped to callers and size | Complete, bounded90-file ledger |
| C2 finite content review | Root integrates read-only language reviews | Every item and exercise option has a disposition | Complete for reachable finite corpora |
| C3 source/boundary corrections | Assign disjoint writes after C1/C2 | Reproduction, focused checks, historical pins preserved | Complete, independently reviewed |
| C4 integration and artifact | Root | Reviewed consistent source, emulator and APK evidence | Running |
| C5 attestation | Root | Honest scope, immutable receipts and remaining dependencies | Ready |

The original four untracked critique files and16 failure images are preserved.
No source writes outside this active worktree are authorized by this plan.

## Grounded findings and selected design

The reachable finite sources are starter12, scanner127 and the local reading
adapter. Additional inactive/demo sources are reviewed separately in the
additional-content ledger. The initial14 focused cases pass but do not detect
the demonstrated semantic defects. Review covers all12 starter entries,
36 choices/24 distractor explanations and all127 scanner entries.

Scanner corrections retain ScannedVocabulary and exact normalized labels.
Substring guesses can turn hotdog into dog or water into water bottle; unknown
or ambiguous labels must remain unmatched. No unverified model aliases are added.
The displayed confidence belongs to the classifier, not translation accuracy.

Architect phases: Ground, Sketch, Agree, Implement, Scrap. Two independent
designs considered installed lexical examples and a separate finite story bank.
Select installed examples with explicit word-list fallback. This reuses content
already owned by the app and avoids maintaining another story corpus. The reading
material keeps the same selected words, ordering, IDs and content revisions.
Examples retain source pins and must match current owner/content. Missing examples
are labelled as missing; storage corruption or owner change cannot expose old
content. Remove fake AI provenance and the hardcoded B1 claim. The rereading stage
must display the material, and recall instructions must describe ordered recall.
The existing canonical learning/evidence authority remains unchanged.

Root owns starter versioning, task documents and integration. The scanner writer
owns its data/lookup, result screen and scanner tests. The reading writer owns
the reading material adapter, Home reading entry, associative reading presentation
and their tests. Test/build commands are serialized by root.

## Implemented corrections and focused evidence

Starter1.0.1 corrects close to a door example with matching Thai, declares the
British pronunciation convention and separates AI-assisted review from pending
independent editorial review. Its package SHA256 is
`3f200d57f3350277ea73d04f27238f3134453e35260b53c01c9490ba58f31dfd`.
The original1.0.0 fixture retains published bytes and SHA256
`46203bc4328b66195a989df2471cd16b77e6c4c2f2833b35195956f07961251b`.
The catalog distinguishes integrity checks from expert certification.

Scanner lookup now requires complete normalized labels. Empty/substring labels
remain unmatched. Stapler has an example using the target noun. Model confidence
is not presented as certainty about the object, and local CEFR labels are estimates.
`scanner-green.log` passes28 focused cases.

Reading uses immutable pairs of selected words and lexical sources. It presents
authored examples when they contain the whole target, otherwise an explicit
missing-example word list. Stage2 displays the material without the extra Thai
support. Stage3 specifies ordered recall. An independent review found a latent
spelling-key collision made relevant by side-by-side pack versions. All callers
now pass ordered records with each target's ID and revision. Both ordinary and
source-bound recall regressions reach stored answers for two distinct IDs with
the same spelling. `reading-identity-regression.log` passes62 cases across6files.

`packs-regression-scroll.log` passes150 cases, including the historical starter
upgrade test. It installs both versions as24 distinct words/snapshots, preserves
the old pack, words, accepted plan and typed draft, resumes and answers using the
old ID, and keeps Research rows empty. Initial preview tests timed out because
the longer provenance moved a lazy install button below the viewport. They now
scroll to the real action before retaining the existing assertions.

Independent review approves the identity fix and transaction/revision boundaries.
No broad table watcher is needed for an immutable reading snapshot; canonical
admission validates revisions again. Comment review removed two narration blocks
without changing lookup behavior. Initial analyzer lints were corrected with
explicit mounted checks and braces, without suppressions. Final analysis is clean.
Full host and Android evidence must still complete on the recorded source.

The Home activity now says reading/review instead of promising a generated story.
`reading-copy-focused.log` passes43 cases. The first full-host run was intentionally
interrupted before these final text edits; its partial log is retained and is not
counted as an accepted full run. Native acceptance precedes the final full-host
rerun so any Android-specific issue can be corrected before source attestation.

The first Android run completed32 cases and stalled in the scanner lifecycle test.
The test simulated paused and then awaited pump before resuming. Local Flutter
source confirms that the live binding waits for a frame while paused disables
frames. Replace that wait with idle to drain microtasks without requiring a frame.
The same pause/resume assertions remain, and the focused Android case passes in
`native-scanner-lifecycle.log`. An independent reviewer confirmed this root cause.
The interrupted run is retained and not counted as a completed acceptance run.

The next Android run completed50 cases with one Tutor timing-test failure. The
synthetic input did not trigger its expected stop callback. The focused correction
asserts that generation finished and the field is enabled, then visibly focuses
and settles the input before injecting text. It verifies the exact controller
text and retains both stop acknowledgement and9,000,000us accounting assertions.
`native-tutor-input-focus.log` passes that focused case. No Tutor production logic
or expected duration changed. The full native runner is rerun before attestation.

The accepted Android rerun passes all51 cases in
`native-content-quality-accepted.log`. `native-accepted-receipt.json` records its
log hash and source-manifest link. Final analysis reports no issues. The full-host
run is active on the same frozen production/test inputs. The task emulator was
stopped cleanly after Android acceptance to release resources while host tests run.

The full-host run found one more stale lazy-preview assumption in the empty-library
recommendation entry. It was stopped after that identified failure to correct the
test before final verification. The test now uses the existing catalog scrolling
helper on both preview openings. Its assertions still prove no rows change before
confirmation and explicit installation creates the starter. The focused file
passes in `recall-preview-green.log`; a new full run follows on frozen inputs.

## Integrated source acceptance

The final full-host run passes5692 tests. Analysis reports no issues.
`full-host-delivery34-result.json` records exit0 for both checks and1091 source
inputs with no hash changes during verification. It records the baseline commit
because the reviewed changes were still staged; the per-file manifest identifies
the tested working-tree snapshot. The later source commit must match those inputs.
The four original critique files were untouched and all16 pre-existing failure
images retain their recorded hashes. `git diff --cached --check` passes.

Android acceptance passes51 cases on the same application code. The only later
test edit adjusts scrolling in the separate Recall entry test, which is not
imported by this Android runner. No application code changed after that run.
Build and real signed-APK fresh/upgrade acceptance remain required for delivery.

## Signed candidate34 found a keyboard defect

Candidate34 built from `50bc9847329436d10b10b17464740399f66297d3`.
Its upgrade preserved all29 canonical tables,20 answers and7 sessions. Explicit
starter1.0.1 installation retained the old pack and produced24 distinct words and
lexical snapshots; the new close card displayed the corrected door example.
The separate upgrade report records these accepted checks.

Fresh signed-APK testing then found first-tap focus loss in Reading stages3/4.
Opening the Android keyboard crosses the440px layout threshold and reparents
the stage subtree. Without a persistent key Flutter recreated the text fields.
Candidate34 is therefore retained as evidence, not the final trial delivery.
Its reproduction database contains2 answers and1 completed recall session, while
Reading progress remains unfinished at stage4, with no Research rows or events.
Screenshots and SQLite/WAL/SHM were preserved before replacing
only the task-owned Synthetic emulator installation.

`reading-keyboard-focus-red.log` reproduces both failures. A State-owned GlobalKey
on the existing stage Column preserves its input state across the layout change.
The expanded regression passes3 cases, covering stages3/4/5, keyboard show/hide,
focus, text, selection, composing and continued input without refocusing.
Independent review accepts the two-line production fix. Candidate35 requires
fresh native/host acceptance and signed-APK fresh/upgrade checks before delivery.

The current-source rerun passes51 Android cases in `native-content-quality35.log`
and5695 host tests in `full-host-delivery35.log`. Analysis reports no issues.
`full-host-delivery35-result.json` records1092 inputs with no changes during
verification; `native35-receipt.json` pins the Android log and Reading source hash.
The new3 keyboard regressions run on the host; normal signed-APK checks must still
exercise the actual Android keyboard. No failing test was skipped or weakened.

All logs, emulator captures and package receipts for this task are under
`D:/LexiQuest-Storage/maintenance/2026-11-04/content-quality`.
The decisions TSV records the accepted choices and their evidence.

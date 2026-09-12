# R4 acceptance and six-lesson quality follow-up

Use executing-plans inline in the existing `02fa/LexiQuest` worktree.
The user authorizes implementation and has selected keeping six lessons and
improving quality. Human audio, live AI and second-device testing are deferred
by the user's 2026-09-12 reply. No additional approval gate or paid call applies.

Goal: verify the existing R4 artifact first, then refine the six original
passages without changing learning authority or claiming certified CEFR levels.
Architecture: retain `LocalReadingCatalog`, its six-level API and the existing
reader. Revise B1/B2 editorial text and their content revision IDs; keep
one text-supported reflection per lesson. No new learning authority or curriculum.
Native R4 exposed a history reader mismatch: `startQuiz` persists `quiz` for
configured CEFR and other quiz modes. Accept that existing carrier only for its
explicit supported modes, retaining evidence/owner/configuration validation.
The synthetic manual harness also needs app-support storage and idempotent
seeding so a relaunch preserves the same vocabulary and history. Copy its
verified existing synthetic database before the in-place preview update.

- [x] Diagnose Windows stdin transfer with a one-block reproduction; use
  ADB sync-protocol pushes with part and whole-file hashes.
- [x] Preserve synthetic QA data before updating; reconcile installed APK
  and restore package-manager-cleared synthetic cache files from verified backup.
- [x] Verify all six readers, reopen/scroll/Back, vocabulary-linked completion,
  four/six-pair results, Today history and Focus Timer on unchanged R4.
  History failed; reproduce with the actual synthetic vivo database and fix.
- [x] Characterize the 100-candidate boundary with synthetic positive/negative
  route tests in `test/screens/choose_mode_screen_test.dart`: 100 unclassified
  IDs before an A1 word must not start it; an eligible word in that window must.
- [x] Strengthen `test/services/ai_voice_reading_adapters_test.dart` so B2
  fallback reports only the target actually in its revised passage. Observe
  failure for the old copy; retain local provenance and deterministic identity.
- [x] In `lib/services/local_reading_catalog.dart`, revise B1's unnatural
  `space ... used to collect rubbish` and B2's unnecessary `ephemeral`; increment
  only their `r1` IDs to `r2`. Preserve all six titles and provisional notice.
- [ ] Run the reading catalog/adapter/library/reader and ChooseMode tests, then
  touched analysis and scoped diff review. Record the exact current source.
- [ ] Include history allowlist/rejection/replay tests and a persistent synthetic
  store reopen test; verify the corrected history on vivo without reseeding.
- [ ] Archive a clearly labelled candidate APK after local checks and verify
  revised content on vivo when installing it in scope. Do not call it a final
  release while external acceptance is outstanding.
- [ ] Record editorial rationale, question answer keys, acceptance evidence,
  data-persistence limitation of the manual harness and remaining dependencies.

Transfer evidence stays in ignored `build/verification/r4-recovery-20260912`.
APK R4 remains immutable. No live service, microphone capture or camera-scene
collection while the holder is unavailable; no change to the shipped model.

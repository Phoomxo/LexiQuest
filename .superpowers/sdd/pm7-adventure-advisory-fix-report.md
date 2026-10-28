# Spec Compliance

- **I1 Closed at the inspected source boundary.** The required owner invalidation now discards the route's accumulated diagnostic scope and permanently disables its old decoration entry point. No confirmed residual defect was found in this focused fix. This is an advisory I1 closure, not whole-PM7 approval.

# Verified behavior

- `lib/features/adventure/presentation/adventure_pair_experience.dart:196` makes invalidation sticky, replaces the private `AdventureDiagnostics` instance, and rebuilds presentation. The decoration gate at `:246` remains off thereafter; the retained old `_decorate` closure returns the supplied canonical board immediately at `:175`. It cannot construct another renderer, invoke the custom decoration, record another counter, or invoke the supplied failure callback after scope invalidation. Route disposal also discards its private instance at `:204`.
- `lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart:195` explicitly limits the optional callback to presentation cleanup. The existing owner check invokes it on mismatch at `:775`, and the existing owner watch invokes it when there is no valid matching live owner at `:807`. The callback passes through the existing pane and shell-feedback composition (`:525`, `:737`), adding no owner query, subscription, session/evidence authority, or relaxation of canonical admission.
- The same keyed canonical host remains mounted (`lib/features/adventure/presentation/adventure_pair_experience.dart:249`). Owner invalidation does not manufacture another session, source snapshot, operation ID, or controller. The renderer's existing listener disposal and mounted guards continue to isolate queued health work from a new route.
- `test/features/adventure/presentation/adventure_pair_experience_test.dart:41` starts a real mounted Pair, records a diagnostic, and deactivates the actual database owner without unmounting the route. It verifies identical host state and no decoration, invokes the captured old decoration closure with a failure callback that must not run (`:123`), reports late health failure, and verifies no further historical counter change, no IDs, and no answers (`:130`). Keeping the test-held historical object unchanged is correct: closure means discarding the current private scope and preventing future use; it does not require erasing historical references retained by a test. A new route naturally constructs its own separate diagnostics instance.

# Directly related retirement check

- `lib/features/learning/presentation/unified_lesson_shell.dart:688` first closes acceptance and clears ephemeral state, then returns the existing terminal future before any repeated pause or cutoff work. Its new pause condition at `:694` only pauses a Pair whose current live owner still equals the accepted plan owner, avoiding the stale-owner pause exception exposed by actual route disposal.
- The retirement work still waits initialization, in-flight start, and all accepted operations (`:717`, `:729`, `:733`). It then uses the existing bounded settlement path (`:747`), whose retry/finish/flush decisions remain in `_settlePair` (`:407`). Existing exact close and disposition paths remain intact; the fix does not add an owner bypass or discard accepted work to avoid the error.
- The current owner-versus-plan comparison is the existing PM7 contract. PM8 runtime-owner/plan-owner rehome changes remain explicitly outside this review.

# Evidence and source boundary

- Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch supplied by root: `codex/pair-matching-pm0-pm8`; committed baseline supplied by root: `cbc4541ff4ad058e11f056f2d06f7eada201e3f9`. No Git command was rerun.
- The initial dispatch hashes changed during review because main applied analyzer style fixes and formatting. This mismatch was reported immediately; the old identities are not certified. Root reconciled the refreshed manifest, and this reviewer checked the current owner-lifecycle sections and actual file hashes:
  - Experience: `f413c5ef8f14748a8be7fafea2e7cd31a1d314a23af73db5d745ed43fe1f3ee6`.
  - Pair host: `bc724ff113e2eb4db8a8da9d193e2503a4f06be850d1fb002f656c6e2d820a3b`.
  - Unified shell: `92c0c383153679c9de1697615c0236d1f77477fc8cf652c0a86853fae34082ed`.
  - Adventure experience test: `5c9a84d461d7d03167351494cd43f10237cdc3af82f93eccbbd8fb1fd55b35e8`.
- These four entries match `.superpowers/sdd/pm7-frozen-sha256.txt`, whose actual SHA-256 is `df1074668691d8228dd13e7afd1d697b2e905408f640a6a7429245d9e957e2bf`.
- Read `.superpowers/sdd/pm7-owner-diagnostics-green3.log`: the exact named owner diagnostic test passed, 1 test in 1 second. Root identifies this run as preceding the later retirement/style edits; it is focused historical evidence, not final integrated current-source evidence.
- Read `.superpowers/sdd/pm7-final-disposition-host-green2.log`: 60 tests passed in 20 seconds, including the retained accepted-answer retirement and parent feature-gate recovery cases. Main subsequently supplied the actual executed argv selecting `pair_configured_disposition_test.dart`, `pair_matching_experience_host_test.dart`, and `adventure_pair_experience_test.dart` (25 + 27 + 8 = 60), which includes the new Adventure owner diagnostic test; concurrent expanded reporter labels did not enumerate every test name, so the earlier omission inference was incorrect, and this run still preceded the final style snapshot.
- Final integrated validation of the current snapshot is pending root/main's final run and whole-PM7 review. No current full-regression claim is made here.
- No test, Flutter, Dart, pub, formatter, generator, build, or scanner was run by this reviewer. No source/test/index/branch mutation or additional process was created. The sole write is this focused report.

# Assessment

**Focused task quality: Approved — I1 Closed.**

The fix closes the requested diagnostic owner lifecycle through existing owner observations and preserves canonical session ownership and retirement ordering. Final PM7 acceptance remains with root after current integrated evidence and a separate fresh whole-phase review.

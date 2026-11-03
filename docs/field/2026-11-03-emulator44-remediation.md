# Emulator44 remediation

Worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Branch: `codex/remaining-system-readiness`; starting HEAD `19c4c445`.
User authorizes fixes against the emulator44 acceptance report. Preserve its
historical observations and existing uncommitted test additions. No public
rollout, Cloud/Billing, real provider/payment, participant enrollment or upload.

## Task board and acceptance

1. Ground/plan: complete. Reproduce native persistence with live FFI SQLite and
   native reminder bind/cancel, then close/reopen. Root owns reminder bridge,
   manifest, native integration tests and evidence. Do not merely change WAL
   flags without addressing two SQLite libraries' same-process lock ownership.
2. Native boundary: implemented and native regression passed. Compare read-only/WAL-only opening against a
   private Android process. Read-only loses the existing reserved transaction
   fence; WAL-only retains same-process cross-library risk. Use a private
   ContentProvider broker and receiver process with WAL-compatible native open.
   Keep owner/deletion/revision guards and all method-channel contracts.
3. Nested navigation: implemented, focused regression passed.
   Prefer existing child lease lifetime over a new navigation ownership graph.
   Prove Review -> Saved -> Back, Achievement -> Preview/share, rapid calendar
   return, and owner replacement rejection.
4. Locale: implemented in main.dart, pubspec.yaml and root locale
   test. Central Thai Flutter localization fixes existing locale-aware surfaces;
   do not duplicate Thai defaults in every screen. Root owns lock generation.
5. Scratchpad: original native sequence passed again with diagnostics and no
   production layout change. Root cause remains unconfirmed; preserve the
   original failure. Focused suites and whole-project analysis passed.
6. Review/attest/integrate: independent diff review and emulator regression of
   reminder enable/change/disable/restart together with cache delete/restart,
   nested routes/share and locale. Record unresolved external acceptance honestly.

Data shapes remain owner-bound reminder settings `(enabled, minute, zone,
revision)`, native scope token, and existing child-launch generation. No schema,
Research contract or parallel learning/reward authority is introduced.

Throughput: root serializes Flutter/build/device work. Agents may edit only
their declared disjoint files and must stop before integrated verification.
No physical Vivo actions. Use the existing task AVDs with synthetic data.

## Evidence during execution

- Focused host regression: 58/58 passed (root locale, dashboard nested routes,
  dashboard guards, achievement scope, reminder repository/runtime/platform/UI).
  Log: `D:/LexiQuest-Storage/maintenance/2026-11-03/emulator44/repair-focused.log`.
- Native RED: the new isolated WAL fixture binds/cancels revision 1 through the
  unchanged Android bridge, then the next Dart transaction fails with SQLite
  code 11, `database disk image is malformed`, at `BEGIN IMMEDIATE`.
  This is synthetic data only. Log: `repair-native-red.log` in the same folder.
- The native fix now moves all delivery preferences/database access into the
  private `:study_reminders` process, including the receiver, and preserves WAL
  when opening the database. Native GREEN passed after increasing the bounded
  method-channel wait from 5 to 15 seconds for the private process cold start.
  `repair-native-green.log` retains the first startup timeout;
  `repair-native-green2.log` records the passing current-revision/write/reopen
  check. The final test also requires the exact stale-revision rejection code,
  WAL mode and SQLite quick_check, and closes its fixture despite retire failure.
- Manifest checks: 16/16 passed, including private broker/receiver process.
- Independent source review found an additional chooser lifecycle race: native
  share returns before chooser completion, while dashboard invalidates its
  child launch on inactive. This requires a bounded external-operation lifetime
  and a return-from-chooser regression before share acceptance.
- Scratchpad review points to an IME/caret scroll timing race in the test helper;
  no production UI fix is justified yet. Preserve native hit-test diagnostics
  and rerun the original sequence before changing the helper.
- Storage/Cloze/reminder host suite: 177/177 passed in
  `repair-storage-cloze-host.log`. Navigation/share/locale host suite: 34/34
  passed in `repair-share-host.log`. These overlap the initial 58 tests.
- Share now keeps the existing token-bound external operation until the native
  chooser returns and the composer resumes/revalidates. Independent review
  identified a misleading cancellation message after dispatch; replace it with
  neutral request-ended wording, then rerun the owner-ABA assertion.
- Integrated Android runner: 5/5 passed in `repair-integrated-native.log`:
  typed/choice Cloze, scratchpad original failing sequence, synthetic assessment,
  and the strengthened native reminder WAL/quick_check regression. Scratchpad's
  original intermittent failure remains historical evidence, not a proven fix.
- Whole-project `flutter analyze`: no issues, `repair-analysis.log`.
- Before updating the preserved All44 AVD, force-stop and copy its synthetic
  database to `before-repair-database`. Read-only inspection of that copy:
  quick_check=ok, journal_mode=delete, reminder enabled at 04:59 revision 1,
  pack cache pinned/present, 20 answer attempts. This confirms the earlier
  05:02/disable/cache-delete UI changes did not survive; do not count them as
  successful writes. No database reset or repair was performed.
- First full regression has one new-test failure: the return-from-chooser case
  reads a button that the lazy ListView no longer builds after image layout.
  The preview assertion passes, but `widget(share)` reports `No element`.
  Restore the button to view before checking that it is enabled; keep all
  lifecycle, owner and hit-testing checks. Preserve this first full-run log.
- First full regression completed: 5,597 passed, one new-test failure. After
  restoring the share button into view and asserting `hitTestable`, all nine
  navigation/share checks passed in `repair-share-final.log`. No production
  source changed to resolve this test failure. A final full run follows the
  internal APK build while the preserved AVD workflows are exercised.
- Independent review disposition: native process/authority checks accepted;
  exact rejection assertion and cleanup improved. Share review accepted after
  neutral cancellation wording and owner-ABA assertion. No new scoped comments
  require removal. Internal offlineTrial27 packaging is the next step, not a
  public release approval.
- Internal release build exposed a pipeline defect: `--no-pub` retained the
  debug `integration_test` plugin registration while release Gradle excluded
  that dev dependency. Installed Flutter 3.44.7 source confirms platform tooling
  regeneration returns early when pub is disabled. Let both release builds run
  Flutter's normal regeneration, then require the dependency-lock hash to remain
  unchanged before packaging. Preserve `repair-package.log` as the failed build.

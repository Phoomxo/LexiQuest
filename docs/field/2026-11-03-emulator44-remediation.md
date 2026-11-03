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
  The first failure is a generic StudyReminderException; a cold-start timeout
  is suspected, not established by that log's underlying native diagnostics.
  `repair-native-green.log` retains the first startup failure;
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

## Final verification and handoff

Implementation commits: `fbc7e2392888fcd6cc9d41d7ee7257806d855c21` and
`998171bc2e8be949557e108697e98712e7fd7bab`. Final full host regression:
**5,598/5,598 passed**, `repair-full-tests-final.log`; native integrated runner:
**5/5 passed**, `repair-integrated-native.log`. Analysis found no issues.
Packaging checks passed (signing 63, release configuration 150); these are
separate suites, not additional distinct feature counts.

Signed internal `offlineTrial` 1.0.0+27 APK/AAB built successfully from commit
`998171bc2e8be949557e108697e98712e7fd7bab`, source tree
`9ca5654e3987e3e30616dc21ef8de4b8a92ac0ca`. Evidence and manifest:
`D:/LexiQuest-Storage/maintenance/2026-11-03/emulator44/repair-package/lexiquest-1.0.0+27/`.
APK SHA256: `95F85DF7D933B8E478AD641340D323C6A8215BA9C315A81D47CB883F946187A4`.
Installed over the preserved synthetic All44 app without clearing its data.
No public release, real purchase, participant enrollment or image send occurred.

Release27 emulator observations (all evidence below under the artifact root):

- Review -> Saved -> Back -> Dashboard -> Calendar works; counts remain 20
  answers, 18 correct, seven sessions (`repair-237` through `repair-240`).
- Achievement preview opens the real Android chooser and returns with working
  buttons; back reaches Dashboard (`repair-242` through `repair-247`). No image
  was sent. Owner-change rejection is covered separately by host tests.
- Thai Dashboard, Review, Saved, Calendar and Focus Timer are visible on the
  English device (`repair-236` through `repair-240`, `repair-249-focus`). This
  does not assert every data-driven string is translated.
- Reminder enable after first granting notification permission initially showed
  request-unconfirmed (`repair-221`); explicit retry succeeded (`repair-222`).
  Changing 23:55 to 23:56 replaced the scheduled alarm by exactly 60 seconds;
  disabling removed the live alarm before force-stop (full final dump:
  `repair-final-alarms.txt`; `repair-alarm-off-live.txt` is only an excerpt).
  First-permission handoff remains unresolved, not a first-attempt success claim.
- Cache delete preserved imported learning content. After a cold restart,
  reminder remains off (`repair-250-reminder-reopened`), and pack detail still
  has no cached file (`repair-252-cache-reopened`).
- Read-only stopped database copy after restart: WAL, schema25, quick_check=ok,
  no foreign-key violations, 20 answers, reminder `(0,1436,Africa/Abidjan,5)`,
  cache `(unpinned,no bytes,revision4)`. See `after-restart-database.json`.
  No database repair/reset was used. Final alarm dump has only cancellation
  history for the app, no live reminder (`repair-final-alarms.txt`).

Containment: restored notification permission to the prior denied state, stopped
the trial app and returned ADB to non-root. Physical Vivo and the original API35
AVD were not changed. Synthetic data and evidence remain available.

Remaining acceptance: investigate first-permission request-unconfirmed; scratchpad
intermittent hit-test cause is still unconfirmed despite the passing original
sequence. The baseline report's partial generated-mode, full-ladder, multi-day,
earned-coin purchase and whole-app accessibility coverage is not superseded by
this focused repair run. Real provider, physical audio/TalkBack certification,
Research authority, Cloud/Billing and real payment are outside this run.
Next executable work is a focused cold permission-grant reminder reproduction
with native stage diagnostics, followed by the remaining partial workflow cards.
Engineering fixes and internal artifact verification do not certify all44
features end-to-end or authorize production rollout.

Cross-model trail review (gpt-6-astra): verified the final test counts, artifact
and database evidence. Corrected an evidence filename and distinguished a
suspected cold-start timeout from the logged generic exception. The full alarm
dump establishes no active app alarm; the earlier excerpt alone does not.
The original session transcript was unavailable to this reviewer, so the review
is limited to artifacts, source and supplied execution context. Remaining flags
are the two unresolved intermittent behaviors and incomplete whole44 acceptance.

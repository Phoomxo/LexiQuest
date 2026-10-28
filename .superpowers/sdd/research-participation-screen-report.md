# Research participation screen — bounded integration handoff

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`.
Branch: `feature/adventure-research`.

Status: **16/16 focused screen tests GREEN on the final formatted source;
2-file analyzer clean; slot explicitly RELEASED to MAIN for Mencius/next queue.**
All owned test/format/analyzer commands ended; release-time process inspection
showed no matching leftover test/analyzer process. No further Dart/Flutter command
will run without a new grant. No commit.

Handoff freeze: **all three owned files FROZEN** after MAIN confirmed 16/16 GREEN
and assigned the slot to Mencius. Hashes and final content/whitespace review are
complete. MAIN will perform independent review and full regression later; no
further product/test edits or Dart tools are planned under this handoff.

## Exact ownership

- `lib/features/research/presentation/research_participation_screen.dart` —
  existing untracked MAIN file explicitly handed over; initial SHA-256
  `75CDA95745917D97BF90A2BE28A4CF504F7D2DAA9FC0C433759EA379F2E69DBF`.
- NEW `test/features/research/research_participation_screen_test.dart`.
- This report only.

The completed form/panel and their 52 tests remain untouched, as do MAIN's
Host/runtime/use-cases/bootstrap, shared fixture, and all other product files.
No commit, new route/task, Figma, external service, scanner or dependency work.

## Grounded gaps and unchanged API

Read active AGENTS, approved R5 plan, prior lifecycle/UI handoffs, the actual
screen/runtime/use-cases/repository code and the exact shared
`test/support/motivation_research_fixture.dart`. Applied TDD and systematic
debugging: the handed-over screen subscribed only in initState, omitted didUpdateWidget
and lifecycle/expiry handling, and async callbacks used mutable widget properties
across awaits with only a mounted guard. RED also exposed a synchronous Flutter
assertion: assignment-expression setState callbacks returned the assigned Future.

Keep `ResearchParticipationScreen({key, required runtime, required ownerId})`.
The implementation is confined to current-permit projection, context generations,
watcher replacement, expiry timer and lifecycle revalidation. Runtime methods
remain the validation/mutation authority. Old callbacks must not target a new
owner/runtime or publish stale results. No local approval creation.

## Prepared test coverage

Tests use the real screen, completed panel, AdventureResearchRuntime, shared
MotivationResearchFixture and SQLite repositories. Only the fixture's explicitly
synthetic signature/receipt authority and user-initiated clipboard boundary are
controlled; no fake runtime or repository replaces the real code.

16 cases cover default zero enrollment, validated document import, rejected
signature, committed withdrawal plus ordinary navigation, owner prop change,
active-owner database change, stale import closure across owners, runtime
replacement with pending authority, stale import/withdrawal closures across
runtimes, expiry while open, resume with lost receipt authority, resume after
clock expiry, unavailable entry authority, stale import refresh and disposal
during lookup. Assertions check both visible verified status and persisted
cardinality/consent/run state; barriers are released during cleanup.

## Bounded RED evidence and recovery

Command granted and run:

`flutter test --no-pub test/features/research/research_participation_screen_test.dart --reporter expanded`

- Initial compilation rejected ambiguous `Column` (Drift/Flutter); corrected
  the own test import with `hide Column`.
- Original production screen then failed with `setState() callback argument
  returned a Future`, reproducible from the initial watcher emission.
- Initial cleanup used `runAsync(close)` while fake-zone SQLite operations
  remained pending; moved close to outer teardown and drain after unmount.
- Last bounded attempt reported **0 passing / 7 failing** before a direct
  async fixture wait stalled. This is **aborted partial evidence, not a complete
  16-test result**. Own process 86758 was stopped with Ctrl-C, exit 1; read-only
  process inspection showed no matching leftover test process. MAIN notified
  explicitly RELEASED before implementation.
- Further test-only correction now pumps fake-zone work and real I/O using a
  bounded `complete` helper, including database operations while a screen read
  may hold a transaction. No assertions removed or skipped.

## Implemented and functionally verified within screen scope

Synchronous setState bodies; a single Future projection; distinct context/read
generations; owner/runtime-bound mutation closures; keyed panel disposal on
context changes; watcher resubscription; fail-closed authority handling; expiry
timer checked against the runtime clock; lifecycle invalidation and resume
revalidation; disposal invalidates late results and cancels timer/subscription.
Runtime remains responsible for import/owner validation and committed withdrawal.
No direct database logic, new public API, local approval or enrollment default.

## Final granted-slot evidence — 2026-09-05

1. First full post-implementation screen run: **13 pass / 3 fail**, exit 1.
   All three were test harness `Guarded function conflict` errors: calling
   `expectLater` after the bounded helper had begun a guarded pump. Production
   correctly rejected stale closures with `ResearchCaptureDenied(ownerConflict)`.
   Fixed the test helper to attach an error handler, finish pumping, then assert
   the denial type. No assertion removed, weakened or skipped.
2. Focused screen run after helper correction: **16/16 pass**, exit 0.
3. `dart format lib/features/research/presentation/research_participation_screen.dart test/features/research/research_participation_screen_test.dart`
   initially formatted 2 files. Analyzer reported one info-level
   `unnecessary_underscores`; changed unused StackTrace parameter to `_`.
4. Final identical format command: **2 files, 0 changed**, exit 0.
5. `flutter analyze --no-pub lib/features/research/presentation/research_participation_screen.dart test/features/research/research_participation_screen_test.dart`:
   **No issues found**, exit 0.
6. Final `flutter test --no-pub test/features/research/research_participation_screen_test.dart --reporter expanded`:
   **16/16 pass**, exit 0, test elapsed 8 seconds; process session 31864 ended.
7. Read final owned file contents and checked scoped diff whitespace. Previous
   form/panel source and both test SHA-256 values still match their 52-test handoff.
   Their suites were neither edited nor rerun. Runtime/Host/bootstrap and shared
   fixture were not edited.

The test harness temporarily suppresses Drift's multiple-AppDatabase warning
because runtime replacement deliberately uses separate `NativeDatabase.memory()`
executors. The prior warning setting is restored in teardown; databases never
share an executor. All authority barriers are released and widgets unmounted.

Final SHA-256:

- screen: `DAAA41990604246D75E9E7907E87A5B9277F508983A3E7DD650F644FB04669F0`
- screen test: `17E10CACE70077BD1F604417CEB6CB28320130E35C122BB11C8517DC5B54E8CE`

## Boundaries / unresolved broader scope

No known failing case remains in these 16 screen checks. They verify the real
runtime/repositories against the shared synthetic issuer/receipt fixture, not a
production issuer, full cryptographic test vectors or external receipt service.
Expiry is timer-driven; receipt authority is revalidated on watched local changes
and app resume. No external push/polling service or runtime timeout was added.
Pending authority is never shown as verified; this screen does not cancel an
already-started runtime transaction when the view changes or is disposed.

MAIN retains integration/release verification, Host/bootstrap/use-case ownership,
physical-device/UAT, and production enrollment/rollout authority. The default-off
configuration is not changed. This report is not end-to-end research readiness,
research efficacy evidence, ethics approval or permission to enroll participants.
Next executable step belongs to MAIN: review the two owned files and integrate
their focused evidence while the next worker uses the released slot.

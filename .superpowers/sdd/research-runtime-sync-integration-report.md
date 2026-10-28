# Runtime → research sync integration completion report

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
Branch: `feature/adventure-research`; base `6968ce97`.

Status: 8/8 GREEN on the actual composed pipeline, including a final rerun after
formatting; focused analyzer clean. Exclusive Dart/Flutter slot released to
MAIN immediately after final completion. No sidecar command remains running.
This is new integration evidence against existing implementations, NOT
preimplementation RED. No production defect or fixture/compile error was found.

Owned files ONLY:

- `test/features/research/research_runtime_sync_integration_test.dart`
- `.superpowers/sdd/research-runtime-sync-integration-report.md`

The previous authorizer/source/98-test suite are frozen. No production, sync,
Host/runtime, shared fixture, schema, or other test files were edited.

## Exact verification evidence (2026-09-05)

`flutter test --no-pub test/features/research/research_runtime_sync_integration_test.dart --reporter expanded`

- Initial run: exit 0, `00:21 +8: All tests passed!`; session 1566,
  output chunks 0093da/a425ef/8f5b9f.
- `dart format test/features/research/research_runtime_sync_integration_test.dart`:
  exit 0, `Formatted 1 file (1 changed) in 0.03 seconds.`; chunk a49480.
- `dart analyze test/features/research/research_runtime_sync_integration_test.dart`:
  exit 0, `No issues found!`; chunk f2e9b9.
- Final post-format rerun of the same focused test command: exit 0,
  `00:20 +8: All tests passed!`; session 10563,
  output chunks 4637cd/cadd2a/c8ae0c.
- Owned-file whitespace/scope check completed; only the normal LF→CRLF Git
  advisory appeared. No test/source edits followed final verification.

No broader test suite, production analysis, scanner, commit, new task,
deployment, or remote transaction was executed by this sidecar.

## Boundary exercised

Configured `AdventureResearchRuntime.fromConfig` with a genuine mathematical
P-256 signature made by a clearly NON-PRODUCTION test-only key and an explicit
synthetic receipt authority. Signed JSON import → runtime use cases → committed
mutation hook → real `DriftSyncStore.enqueueResearchForOwner` → ordinary owner
Sync gate → actual claims → beginAttempt → real gateway preflight calling the
real `DriftResearchSyncAuthorizer`. No permissive authorization callbacks.

Passing assertions cover five research collections and exact signed/ref fields,
UUIDv7 timestamp reconstruction, both presentations with canonical accepted
session/completion + post and all four neutral events, withdrawal while claims
are held, evidence preservation, expired/inactive authority deny-only withdrawal
recovery/retry/acknowledgement, signed renewal replacing stale wrappers without
duplicate evidence, missing participation and forged-document denial.

No external Firestore/Firebase initialization or network transactions. The
preflight transaction is a local sentinel; the withdrawal acknowledgement is a
synthetic remote receipt passed to the actual codec. Policy/network tests remain
with the sync worker. This does not assert deployment, real enrollment, remote
freshness, ethics approval, or questionnaire efficacy.

## Outcomes

- Genuine signed JSON imported through the configured runtime; five after-commit
  notifications reached the real enqueue hook. All five collection types were
  already present in pending outbox before claim-time recovery.
- Real ordinary gate claims, beginAttempt, gateway preflight and payload codec
  accepted the produced permit/run/response/opportunity/event payloads. Exact
  signed fields and permit references survived every boundary.
- Both presentations produced four neutral event types, two coded responses,
  and a completed run after canonical learning completion: nine deliverable
  claims each. Research did not alter the seeded canonical session, create
  learning answers, or issue rewards.
- Withdrawal while five claims were held prevented every beginAttempt and
  push authorization without spending attempts. Signed permit fields, answer
  rows, event rows and the closed denominator remained intact.
- After expiry and receipt loss, a fresh store recovered exactly one deny-only
  withdrawal in the existing outbox without any receipt lookup. Retry reused
  its identity; a synthetic acknowledgement prevented requeue.
- Genuine signed renewal invalidated old held payloads, refreshed permit
  references and preserved the event envelope with no duplicated evidence.
- Missing participation and forged signatures created no research enrollment
  or queue records; receipt loss blocked claims without deleting evidence.

No production target needs a defect handoff from these eight tests. Independent
authorizer/sync review and broader release evidence remain MAIN's separate work.
Sidecar work is finished; slot and running-process ownership are released.

## Final hashes / frozen inputs

SHA-256 `test/features/research/research_runtime_sync_integration_test.dart`:
`3839280C1F09D27A17A86F91F369E8BAE98A3B87F3514D875A5D9B0727B37848`

Confirmed unchanged from the previous 98-test handoff:

- `lib/features/research/data/drift_research_sync_authorizer.dart`:
  `339E49B5F06F8AB520ECD894ADF41C930AAE587DBAF37C53489C3CAC1F96C7DF`
- `test/features/research/research_sync_authorizer_test.dart`:
  `F64B1D2706C8E02A25DF22D5197AF4C9059FA8292D17CBED2EE47E58A1D5AEB1`

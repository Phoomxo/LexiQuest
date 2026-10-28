# Research Sync authorizer — bounded completion report

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
Branch: `feature/adventure-research`; base `6968ce97`.

Status: bounded authorizer implementation complete; focused GREEN 98/98 and
two-file analyzer clean. Exclusive Dart/Flutter slot explicitly released to
MAIN immediately after final test completion. No command remains running for
this task. Shared runtime/transport integration remains MAIN/sync-worker scope.

RED evidence (2026-09-05):
`flutter test --no-pub test/features/research/research_sync_authorizer_test.dart --reporter expanded`
completed exit 1, `00:06 +71 -23: Some tests failed.` All 23 failures are positive
authorization expectations (`Expected: true`, `Actual: <false>`) against the
fail-closed scaffold; no compilation or fixture error. Total 94 tests.
Unified command session 9261 completed; output chunks 3d9078 and 40adfb.

First GREEN attempt: same command, exit 1, `00:08 +96 -2`. Root cause was an
intervening sync contract API addition: `validate` now accepts `phase` and
defaults to push, so two valid signed revocation pulls were denied. Corrected
the authorizer to pass the actual phase and signed deletion flag. All requests
now use `ResearchSyncContract.validate`; the earlier deletion codec workaround
was removed. No sync-owned file was edited and no assertion was weakened.

After that correction: exit 0, `00:08 +98: All tests passed!` (session 93472).
Targeted analyzer found one informational braces lint; added the braces and
reverified the final source:

- `dart format lib/features/research/data/drift_research_sync_authorizer.dart test/features/research/research_sync_authorizer_test.dart`
  — exit 0, `Formatted 2 files (0 changed) in 0.06 seconds.`
- `dart analyze lib/features/research/data/drift_research_sync_authorizer.dart test/features/research/research_sync_authorizer_test.dart`
  — exit 0, `No issues found!` (output chunk 062cb1).
- `flutter test --no-pub test/features/research/research_sync_authorizer_test.dart --reporter expanded`
  — exit 0, `00:08 +98: All tests passed!` (session 35435, chunks 9a1433/02db5b).

No main opportunity/Host/widget/new-service tests, broad analysis, scanners,
commits, task creation, deployments, or real research uploads were run here.

## Owned files

- `lib/features/research/data/drift_research_sync_authorizer.dart`
- `test/features/research/research_sync_authorizer_test.dart`
- `.superpowers/sdd/research-sync-authorizer-report.md`

No sync, runtime, shared fixture, crypto or lifecycle source was changed.
The constructor matches the requested database/study/validator/nowUtc API.
Production `.authorize` is implemented after the observed RED, with no public
API change. It returns a fail-closed boolean and only performs reads. The
zero-write tests use SQLite `total_changes()` as well as research/outbox counts.

## Public API / integration

`DriftResearchSyncAuthorizer(database:, study:, validator:, nowUtc:)`
exposes `Future<bool> authorize(ResearchSyncRequest)`; pass `.authorize` to the
existing `ResearchSyncAuthorizer` callback. No lockOwner/acquire/renew/write.

MAIN's next executable step is the separately owned runtime/composition focused
GREEN with this callback. Four additional authority/replay/response-race cases
were added after the original 94-case RED; they are included in final GREEN,
not retrospectively claimed as part of the initial RED.

Verified coverage: ordinary Sync gate versus actual owner-transition fence,
all phases/null-token push, gate/owner/consent/assignment/permit/receipt/expiry
races, signed enrollment/renewal/revocation/deletion and stale/forged replay,
minor receipts, immutable run/response/opportunity/envelope pins, withdrawn and
tombstoned parents, completed/skipped/abandoned upload, deterministic identities,
actual coded response ordinal, four neutral events/UUIDv7 milliseconds and zero
authorizer writes. All signing uses explicitly synthetic P-256 test material.
The final implementation was read through and the owned paths checked for
scope/whitespace; no production/test edits followed final verification.

## Integration and trust constraints

- `isOwnerFenced` means an explicit owner marker joined to a matching active
  global gate, NOT merely a busy global Sync gate. Reuse its read-only check;
  never acquire/renew/write a fence from this authorizer.
- Current request has no outer transport revision/tombstone fields. Transport
  must validate those independently; signed permit revisions remain exact.
- Contract now supports phase-aware signed deletion/revocation pull. The
  authorizer passes those exact fields through it, authenticates both stored
  predecessor and incoming state, enforces immutable pins/monotonic revisions,
  and allows exact cutoff replay without re-enrolling unknown cutoffs.
- Pull requires locally available permit/run/opportunity and learning-session
  parents as appropriate. An opportunity pull may precede its referenced child
  events; present child rows are validated and subsequent event authorization
  validates exact owner/opportunity/session links. Upload rejects missing child
  events. Transport must order/retry dependent pulls; authorizer never writes
  placeholder rows or repairs evidence.
- This validates coded items/ordinals and permit/run/event timestamp bounds.
  Full baseline/post eligibility and first accepted-session reconciliation stay
  with the capture/measurement component; this is not a new scoring authority.
- Local authority snapshots and injected receipt/issuer trust are not proofs
  of server freshness. Rechecking after awaits closes observed local races, not
  an unavailable remote revocation oracle. Rollout/enrollment remain default-off;
  no issuer approval, ethics approval, deployed rules or real participant result
  is asserted here.

## Final source SHA-256

- `lib/features/research/data/drift_research_sync_authorizer.dart`:
  `339E49B5F06F8AB520ECD894ADF41C930AAE587DBAF37C53489C3CAC1F96C7DF`
- `test/features/research/research_sync_authorizer_test.dart`:
  `F64B1D2706C8E02A25DF22D5197AF4C9059FA8292D17CBED2EE47E58A1D5AEB1`

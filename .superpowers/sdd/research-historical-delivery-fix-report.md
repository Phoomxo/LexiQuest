# P2 historical delivery / lost ACK — completion report

ผล: **P2 focused 57/57 GREEN; affected regression 191/191 GREEN; final five-file analyzer clean.**
คืน exclusive Dart slot ไปยัง MAIN โดยตรงแล้ว และ freeze production/test files
ก่อนเขียนรายงานนี้ ไม่มี task-owned command ค้าง ขั้นต่อไปเป็น Gibbs review และ
MAIN R6 integration checks ไม่ใช่การอนุมัติ production enrollment/upload

Worktree: `C:/Users/Phet/Documents/LexiQuest/.worktrees/research`
Branch: `feature/adventure-research`
HEAD/base: `6968ce97ff9b383e244b17b77cf0ed0f61eaaf3d`
Shared dirty/untracked implementation; no commits or new worktree/task.

## Changes in this sidecar

- `lib/features/research/data/drift_research_sync_authorizer.dart`: only PULL can
  carry the same permit ID with a strictly lower positive revision and canonical
  bounded hash. Each before/after snapshot validates provenance payload binding
  or an exact known local fact plus its historical outbox admission identity.
  Current genuine signed permit, receipts, consent, owner/UID, actual gate/fence,
  assignment and every instrument/event/pin/parent/timestamp check remain strict.
  No writes, events or outbox operations in the authorizer; strict clock retained.
- `lib/features/sync/data/drift_research_sync_adapter.dart`: validates complete
  server marker binding before forwarding it only on PULL, and again after the
  async authorization. Same-fact reconciliation records delivery metadata and
  exact operation identities without changing signed fields, original facts or
  lifecycle times. New-device event imports receive a zero-attempt acknowledged
  ledger row so restart/queue cannot upload the already delivered event again.
  Current enqueue/claim/push still require exact current permit references.
- `lib/features/sync/data/drift_sync_store.dart`: RESEARCH conflict branch
  accepts reconciled ACK only after the complete claimed fact and outer revision
  match cloud evidence. Changed content cannot become an acknowledged claim.
  Ordinary learning/outbox/delete behavior was not changed by this sidecar.
- `test/features/research/research_sync_authorizer_test.dart`: 47 new P2 cases.
- `test/features/research/research_runtime_sync_integration_test.dart`: ten new
  P2 cases plus one raw +321us clock integration, classified as new integration
  evidence against MAIN's already-implemented clock fix, not fabricated RED.

Existing `test/features/sync/research_measurement_sync_test.dart` ran as focused
regression but was not edited; its hash still matches independent-review input.
No gateway/rules/domain-contract, fixture, prior reports, schema or signed assets
were edited. MAIN supplied the additive provenance API and gateway stamping.

## Provenance and integrity boundary

Historical wrapper references are transport scope metadata, not issuer
signatures over research events/responses. Such facts are unsigned even when
their references are current. A valid-format unknown hash alone is insufficient.

The accepted new-device boundary is an authenticated same-UID Firestore server
read plus server admission/immutability rules. MAIN's process-local
`SyncServerReadProvenance` is not decoded/serialized from JSON; only the trusted
gateway attaches it in production. Explicit synthetic server fixtures may attach
it in tests. This is a trusted in-process boundary, not a cryptographic proof
against malicious application code.

Adapter `matchesEntity` binds UID, collection, ID, payload hash, revision,
deleted flag, payload version and client/server timestamps. Authorizer
`matchesPayload` repeats UID/collection/ID/payload validation in each snapshot.
Current local signed authority is still validated before and after authority
awaits; the marker supplies neither consent nor upload permission.

Without a marker, lost-ACK recovery requires both exact local fact equality and
the durable exact old-wrapper outbox fingerprint. Neither route rewrites an old
immutable cloud wrapper. ACK touches only known equivalent identities, never
every job for the entity; pending delete jobs are outside this path.

Historical pulls cannot restore withdrawn/tombstoned capture, substitute a
different permit/owner/assignment, bypass current receipt or active authority,
or turn conflicting answers/pins into delivered facts. New-device history is
not permanently blocked: parent-first run/response/opportunity/event replay is
verified in a separate database with no original local facts or outbox.

## Exact verification evidence

### Real behavioral RED

Command:

`flutter test --no-pub test/features/research/research_sync_authorizer_test.dart test/features/research/research_runtime_sync_integration_test.dart --name P2 --reporter expanded`

Session `68795`; chunks `ca8321`, `bb0608`, `d64d96`.
Final: `00:20 +44 -13: Some tests failed`, exit 1, 57 cases, no compile blocker.

Nine historical authorizer positives returned false. Four integration positives
(lost ACK via conflict/pull, known four-collection replay and marked new-device
restore) threw `SyncFailure(providerUnavailable)` at pre-fix adapter line 340.
This observed P2 failure preceded production changes. Slot explicitly released.

The generic Drift two-database warning was fixture-only: device B uses its own
in-memory executor. The warning setting is now scoped/restored in those tests.

### Focused GREEN and affected regression

The same focused command: session `57741`; chunks `84bae1`, `778b5f`,
`74af82`; final `00:21 +57: All tests passed!`, exit 0.

Affected command:

`flutter test --no-pub test/features/research/research_sync_authorizer_test.dart test/features/research/research_runtime_sync_integration_test.dart test/features/sync/research_measurement_sync_test.dart --reporter expanded`

Session `92281`; chunks `54a47d`, `638768`, `9faa2f`;
final `00:43 +191: All tests passed!`, exit 0. Includes earlier authorizer and
integration cases, the existing measurement-sync regression, and raw-clock
runtime capture -> real enqueue -> claim/beginAttempt -> real push authorizer
for all five collections. The real authorizer shares runtime's canonical clock;
signed permit input remains byte-for-byte equivalent.

The lost-ACK fixture commits E1 entity plus operation into synthetic remote maps
using production codecs, withholds local ACK, imports genuine P-256 renewal v2,
then recovers E2 from the actual store. Conflict and historical pull both
durably acknowledge the identical event. Remote fact/operation counts stay one,
the old cloud wrapper stays unchanged, and repeated claim cannot retry the event.

### Final formatting, analyzer and scope

Formatted the two changed tests and two dedicated production files. Formatted
RESEARCH portions of the shared store, restoring three unrelated shared-claim
formatting hunks so out-of-scope baseline text remains intact.

Initial scoped analyzer reported one redundant `!` and style-only brace infos.
These were corrected mechanically; no behavior correction was needed after
57/57 and 191/191 GREEN. Tests above precede this final format/brace cleanup;
the final analyzer below checks the frozen post-cleanup files.

`dart analyze lib/features/sync/data/drift_research_sync_adapter.dart lib/features/sync/data/drift_sync_store.dart lib/features/research/data/drift_research_sync_authorizer.dart test/features/research/research_sync_authorizer_test.dart test/features/research/research_runtime_sync_integration_test.dart`

Final chunk `a03b2e`: exit 0, `No issues found!`
Scoped `git diff --check -- lib/features/sync/data/drift_sync_store.dart`: no
whitespace errors; Git only emitted its existing LF/CRLF notice. Shared-store
diff inspected; pre-existing research integration was preserved.

## Frozen SHA-256 handoff

Paths are relative to the worktree above; hashes include formatting.

| File | SHA-256 |
| --- | --- |
| lib/features/sync/data/drift_research_sync_adapter.dart | 6CA7B15C7F0230EAC2A7B9B735A26603C15934B68CCC5D2106D728186F31CE77 |
| lib/features/sync/data/drift_sync_store.dart | 24CD3DC7706B1BF2911E23AEED24E0BF9BB1AB1DE72BACC3F7B23EF404D233AD |
| lib/features/research/data/drift_research_sync_authorizer.dart | 5FD896444B625210FCB2F429E342002708C2CFEB7022484DB56CBECA5E7751D4 |
| test/features/research/research_sync_authorizer_test.dart | E45C6FE4442EB2B80A6119376279AECC19BE09C05709DB24AC94EA81EE42995D |
| test/features/research/research_runtime_sync_integration_test.dart | 89AB3D2986E921E176C2302D1D2B6A2E84E00DA8189965E8C8C2C382F7D4EFE1 |
| test/features/sync/research_measurement_sync_test.dart (unchanged) | 267D881685FD0207883CB70441A57FC1FDAC725AAE277E7B7E19DAB1C8964B95 |

## Handoff and limits

TDD, receiving-code-review and systematic-debugging guided reproduction and
policy separation; verification-before-completion guided fresh evidence.
Review context/paths/counts were sent to MAIN for the existing Gibbs review
(no additional reviewer task was created). Exclusive slot explicitly released
before report writing. Production/tests frozen; only this report changed after
release. No task-owned process, unresolved test failure, commit, full scan,
deployment, real participant data, external Firestore network or new task.

MAIN/Gibbs review and R6 are still separate integration/release checks. This
bounded completion neither certifies deployed rules/freshness nor supplies
issuer/ethics/receipt approval or permission for real enrollment/upload.

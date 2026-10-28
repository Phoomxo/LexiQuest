# PM8 owner authentication and upgrade implementation handoff

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.
Implementation subtask only; no approval or release-readiness claim.

## Exact write set

- `lib/features/identity/data/drift_owner_upgrade_repository.dart`
- `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart`
- `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart` (new)
- This handoff report.

The assigned `drift_pair_matching_session_purpose_reader.dart` required no edit:
its existing query/decode integration automatically uses the expanded tracked
`historicalOwnerQuery` dependency set. No schema, generated file, immutable
EvidenceContext/EventEnvelopeV2 field, pure engine, or other checkout was changed.
The main implementer remains the sole Flutter/Dart/pub/build/format/generator
owner; this helper ran none of those commands and made no Git mutation.

## Implemented behavior and integration APIs

`PairMatchingSessionPurpose` now exposes:

- `authorizeActor({ownerId, actorId, occurredAtUtc, historicalOwners,
  secondPrecision = false})`: canonical destination existence and direct local
  historical lineage with UTC millisecond owner ranges; optional event-second
  interval handling. Read-only inactive account history remains permitted.
  Mutation consumers must separately require the sole active runtime owner.
- `authorizeSnapshot({ownerId, session, snapshot, historicalOwners})`: immutable
  original plan P, canonical owner R, session identity, full configuration owner
  projection, frozen actor/occurrence/content/classification authentication.
- `projectConfigurationOwner(SessionConfiguration? accepted, String ownerId)`:
  `SessionConfiguration.validated` projection retaining every accepted field
  other than owner ID.
- Immutable `reservations`, keyed by evidence ID and accumulated from the full
  authenticated strict prefix, preserving acknowledged and pending occurrences.

Strict decoding requires revision 1 actor P and original actor-derived key,
contiguous supported transitions, exact start/plan/config pins, consistent
reservations, and authentic actors for each checkpoint/frozen operation.
Legacy 1–5 retains its previous actor marker behavior. Tracked owner extraction
includes R, original plan owner, every checkpoint actor, and frozen owner/actor,
including absent rows so tracked authorization invalidates upon insertion.

Actual owner upgrade preflights before category remapping. It retains the existing
16 active Matching bound, pages all/terminal Matching sessions in groups of 32,
loads at most 65 envelopes to enforce 64 revisions, authenticates strict Pair
lexical IDs, canonical attempts/source events, and every exact reservation.
Only transaction-local IDs are retained across pages. Authenticated v6 sessions
skip legacy collision abandonment; their zero-answer pins enter the existing
tombstone/projection-alias path. The existing colliding-attempt validation still
runs. Moved sessions, owner-only configurations, attempts, and lineage are
revalidated after canonical row movement/marker rewrite before commit.

The canonical destination's remaining completion capacity is checked before the
first cutover/category/word merge write and again after rehome, using main's
optional codec `runtimeOwnerId` argument. Each accepted session is re-read and
authenticated separately rather than retaining terminal JSON across pages.
Default same-owner reserve remains unchanged; a destination that would exceed
the existing 64-KiB budget refuses the transaction before remapping pins.

Frozen full-precision timestamps are preserved. SQL owner/session/attempt fields
remain milliseconds and stored event timestamps remain seconds; no rounding or
new time authority is added by this helper.

## Test-first evidence (main's serialized execution)

- `.superpowers/sdd/pm8-auth-upgrade-red2.log`: 0 passed / 6 failed, expected
  real-upgrade matrix RED: noncollision/category rejected moved purpose and word
  collision reached the legacy-only fence. The earlier `pm8-auth-upgrade-red.log`
  was compile-invalid while main temporarily referenced the not-yet-created
  shared API; it is not represented as behavioral RED.
- `.superpowers/sdd/pm8-integration-first.log`: all six real collision/config
  positives passed; this helper's file was 18 passed / 1 failed. The failing
  anonymous-bind test incorrectly expected no unrelated canonical cutover events.
  It was corrected to assert the original Pair checkpoint row exactly, preserving
  the real bind's cutover behavior. Main's unrelated fixture compilation failure
  and overall 39 passed / 2 failed remain in that retained log.
- `.superpowers/sdd/pm8-runtime-boundaries-red.log`: this helper's then-current
  21 tests all passed, including actual logout/new guest/account return and second
  repository merge with canonical direct-link rewrite. Overall run was 31 passed /
  6 failed in main-owned runtime/host/export paths; that is not a whole-task pass.
- `.superpowers/sdd/pm8-fractional-red.log`: 0 passed / 1 failed as intended for
  the new fractional frozen timestamp regression: an extra microsecond rejection
  prevented durable reservation admission. The guard was then removed; exact
  frozen bytes and canonical SQL precision checks remain.
- `.superpowers/sdd/pm8-runtime-boundaries-green1.log`: this helper's 34 tests
  all passed. Overall run was 48 passed / 2 failed in main-owned widget timer
  cleanup; this was not a complete integration pass.
- `.superpowers/sdd/pm8-replay-clock-red.log`: existing replay controls were
  0 passed / 2 failed because the new optional frozen-plan-start time floor
  rejected historically accepted replay clock behavior. That additional floor
  was removed; owner lifetime and upgrade timestamp checks remain.
- `.superpowers/sdd/pm8-owner-capacity-red.log`: 0 passed / 1 failed as intended:
  actual near-ceiling merge returned success instead of refusing destination
  completion overflow. The destination capacity preflight was then implemented.
- `.superpowers/sdd/pm8-auth-runtime-green2.log`: final focused GREEN, 56 passed /
  0 failed in 19 seconds, main reports process exit 0. This is this helper's 37
  tests plus main's 19 runtime/recovery tests. Main formatted identity, purpose,
  auth test, and codec sources before the run. The helper independently read the
  retained successful log tail and current source hashes without rerunning
  Flutter/Dart, preserving main's sole tooling ownership.
- Current scoped `git diff --check` produced no whitespace errors (one inherited
  LF-to-CRLF Git advisory). Full analyzer and release/legacy regression gates are
  outside this focused result and remain main/root integration ownership.

The 37 tests cover actual anonymous bind; no collision, category-only collision,
and zero-answer word collision in both directions/densities with configuration;
malformed strict preflight rollback; ten canonical marker/actor/config tamper
controls; twelve self-consistent replacement configurations with independently
parsed valid identities; tracked R/P/checkpoint/frozen identities; actual logout
and return; actual second repository merge and broken rewritten marker; exact
fractional frozen reservation preservation through real upgrade.
The three added capacity controls cover atomic near-ceiling refusal with unchanged
canonical owner/content/session/evidence/outbox snapshots and usable same-owner
completion, plus successful actual Thai256/control256 destination merges that
write new current-actor answers and complete the unchanged accepted plan.

Second bound-account merge is tested through the actual repository with synthetic
owners. Current repository/use-case source does not prohibit that topology; this
does not claim that account authentication UI offers account merging.

## Frozen focused source identities

SHA-256 after main's formatting and the 56-test GREEN run:

| File | SHA-256 |
| --- | --- |
| `lib/features/identity/data/drift_owner_upgrade_repository.dart` | `FED32D8B1DF3BDB0B9D635EF09BFB1ABB1443D47AD35719F33F11348CAFD3AC8` |
| `lib/features/learning/pair_matching/domain/pair_matching_session_purpose.dart` | `7FBB4F30205C970B9735DE3329759BF5433FB8EEEFD368697A7529A5C9FA0F47` |
| `test/features/learning/pair_matching/pair_matching_owner_upgrade_auth_test.dart` | `DF7699C8530DCEED7F99CA5830B0BA49DDF1D37016FBDC1DACA3D49CA8F5EFAE` |
| `lib/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart` (main-owned integration dependency) | `9F0CEF206F69B58F24E703D6E001BE980D5BCFBDAA0A08F6F0371071E82FEAC5` |

Root has this frozen subset for independent review. Any relevant subsequent
source edit invalidates this particular snapshot's evidence and requires the
affected checks to be repeated by main/root.

## Remaining integration ownership

Main owns runtime/coordinator/host/disposition authorization, first-write historical
actor exception, disk reopen/retry/terminal/export/deletion, canonical projection
alias effects, complete legacy controls, formatting/analyzer, and final review.
Persisted candidate time comparisons must respect SQL milliseconds while original
command versus frozen comparisons remain exact; this cross-boundary concern was
sent to main and is outside this helper's write set.

No helper-owned processes remain running. All helper source/test ownership is
released to main after the focused GREEN; the reviewed subset stays frozen until
reviewer outcome/main release. No self-approval, commit, deployment, enrollment,
upload, or production activation was performed.

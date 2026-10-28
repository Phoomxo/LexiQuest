# Progress Authority and Trusted-Writer Migration

Date: 2026-07-27
Branch: `feature/production-vertical-slices`

## Purpose

State the trust boundary for learner progress (points, answers, games) and
the shop balance; explain why the current Firestore layout cannot make a
client-mintable balance trustworthy; and lay out a compatibility-ordered
migration to a server-authoritative writer. This is a design artifact, not a
declaration that any callable or rules migration is complete.

## Current writers and readers

Three divergent per-user counter stores exist. Only one is consumed by the
shop.

### `state/{uid}` — the balance the shop trusts

- Writers:
  - `lib/screens/score_screen.dart` `_updateUserStats`: `set(..., merge)` with
    `FieldValue.increment(correctAnswers)` on `totalPoints`,
    `totalCorrectAnswers`, `totalWrongAnswers`, and `+1` on `gamesPlayed`.
  - `lib/screens/shop_page.dart` `_buyProduct`: inside `runTransaction`,
    `transaction.update` with `FieldValue.increment(-productPrice)` on
    `totalPoints`.
  - `lib/screens/select_wallpaper_screen.dart` `_setWallpaper`: `.update` of
    `selectedWallpaper`.
- Readers: `lib/screens/score_screen.dart` (renders `totalPoints` and stats),
  `lib/screens/shop_page.dart` `_fetchUserPoints` (balance for purchase
  gating), `lib/screens/quiz_screen.dart` `_loadBackground` (wallpaper),
  `lib/services/user_service.dart` `getTotalPointsFromState`.
- Rule: `firestore.rules` `match /state/{uid}` allows `create, update` for the
  signed-in owner with type/bound checks. **`totalPoints` is a
  client-incrementable integer**; the rule does not bind it to a graded
  result.

### `users/{uid}.totalPoints` — divergent counter, not consumed by the shop

- Writer: `lib/screens/quiz_screen.dart` `_savePointsToFirestore`:
  `set(..., merge)` on `users/{uid}` with `FieldValue.increment(userPoints)`
  and `+1` on `gamesPlayed`.
- Reader: none evidenced for purchase or display. This counter drifts
  independently of `state.totalPoints` and is a redundant authority.

### `users/{uid}.points` — third counter, partially dead

- Writers: `lib/services/user_service.dart` `saveUserData` (literal `set`) and
  `updateUserPoints` (`FieldValue.increment`);
  `lib/services/quiz_service.dart` `savePointsToFirestore` (literal `update`).
  `QuizService` is not instantiated in the app (per the client access
  inventory), so that writer is effectively dead.
- Reader: `lib/models/user_model.dart` `AppUser.fromMap` reads `points`,
  surfaced via `lib/screens/setting_screen.dart`.

### `purchased_items/{purchaseId}` — ownership records

- Writer: `lib/screens/shop_page.dart` `_buyProduct`, inside the same
  transaction that debits `state.totalPoints`, writes `user_id`,
  `product_id`, `total_price`, `created_at`.
- Readers: `lib/screens/shop_page.dart` `_buyProduct` (duplicate-purchase
  guard, filtered by `user_id` + `product_id`) and
  `lib/screens/select_wallpaper_screen.dart` (ownership list, filtered by
  `user_id`).
- Rule: `firestore.rules` `match /purchased_items/{purchaseId}` allows
  `create` only when `purchaseIntegrityOk(database)` holds (see below);
  update and delete are denied.

## Divergent points stores

`totalPoints` lives in two documents (`state/{uid}` and `users/{uid}`), and a
third `points` field lives on `users/{uid}`. They are written by three
different code paths with no shared authority:

- `state.totalPoints` is debited by purchases and rendered as the balance;
- `users.totalPoints` is incremented at end-of-quiz and never spent;
- `users.points` is written by `UserService` and a dead `QuizService`.

Net effect: a learner can hold three different "totals" at once, and only the
shop-readable `state.totalPoints` has any spend-side guarantee. Any analytics
or ranking that reads a different field measures a different quantity than
the shop honors.

## ScoreScreen side effect in `build()`

`ScoreScreen.build()` calls `_updateUserStats(...)` synchronously (a
fire-and-forget `Future`) on every build. Because the surrounding widget is a
`FutureBuilder` over `state/{uid}`, each rebuild re-issues a Firestore write
that increments `totalPoints`/answers/`gamesPlayed`. `build()` is otherwise
expected to be free of side effects; placing an incrementing write there means
the recorded progress depends on how often the framework rebuilds the widget,
not only on how many questions the learner answered. This is the proximate
double-counting hazard and the reason a single idempotent writer is needed.

## Why `purchaseIntegrityOk` is necessary but not sufficient

`firestore.rules` `purchaseIntegrityOk(database)` is a strong atomic guarantee
for *spending*: a `purchased_items` create is accepted only when, in the same
batch, `state.totalPoints` drops by exactly the positive catalog `price`, the
balance before was at least that price, and the product exists. It prevents a
client from creating ownership records without paying, or from paying a
mismatched price.

It cannot make the balance itself trustworthy because the balance is
client-incrementable. A signed-in user can write `state/{uid}` directly (the
rule permits `update` of `totalPoints` within bounds) and mint any balance up
to the field ceiling before calling `_buyProduct`. `purchaseIntegrityOk` then
correctly observes "the balance was debited by the price" — but the balance it
observes was self-awarded. Atomic spend-integrity and authoritative
credit-integrity are different properties; the rules provide the former, not
the latter. No client-side check can supply authoritative credit, because the
crediting write originates on the client.

## Research-data integrity impact (scoped)

This is bounded and must not be overstated:

- The research exports (`lib/services/research_data_exporter_service.dart`
  CSV for SPSS, the CRISP-DM and Brahmawong analytics services, and the
  research/thesis PDF exporters) consume per-word SRS/telemetry record lists
  passed into them; they do not read `state`/`users` aggregate counters.
  Their integrity is therefore independent of the forgeable balance.
- `voice_telemetry_events` are append-only, privacy-safe, and carry no
  spendable value, so they are not affected by the balance problem.
- The integrity gap is confined to anything that trusts an aggregate counter
  as a measure of learning: shop unlocks, future leaderboards, or any later
  research artifact that joins `state.totalPoints` or per-user answer totals.
  Treat those counters as self-reported until a server-authoritative writer
  exists, and exclude them from population-level learning claims.

## Target progression (compatibility-ordered)

Each step is a prerequisite for the next. None is declared complete here.

1. **Local idempotent outbox (underway via TDD; no Firebase dependency).**
   Capture each completed session once, by stable session id, in a local
   store before any Firestore write. The test
   `test/progress/local_progress_repository_test.dart` fixes the contract:
   `ProgressRepository` with `recordSession(ProgressSession)`,
   `readSnapshot()` returning
   `{totalPoints, totalCorrectAnswers, totalWrongAnswers, gamesPlayed}`, and
   `pendingSessions()` (the outbox). `recordSession` is idempotent by
   `sessionId`, validates non-negative/bounded counts, and survives a process
   restart via `SharedPreferences`. This removes the `build()` double-count
   once the UI is routed through it and yields a replayable queue. It does not
   yet make the balance trustworthy; it makes the client explicit about what
   it intends to claim.

2. **Authenticated callable trusted writer.** Add a server-side endpoint (a
   Firebase Callable / second-generation Cloud Function under the Admin SDK)
   that is the sole authority for crediting progress. It verifies the Firebase
   ID token, accepts a session, applies the same validation as the local
   repository, and writes `state/{uid}` (and reconciles `users/{uid}`) using
   Admin writes that bypass client rules. The client drains
   `pendingSessions()` through this endpoint and acknowledges on success.
   This is a Firebase-project prerequisite and is not present in this
   repository today (no `functions/` backend exists).

3. **Rules deny client counter writes.** Once the callable owns all credited
   writes, tighten `firestore.rules`: deny client `create/update` of
   `totalPoints`, `totalCorrectAnswers`, `totalWrongAnswers`, and
   `gamesPlayed` on `state/{uid}`, and the divergent counters on
   `users/{uid}`. `selectedWallpaper` and profile fields stay client-writable.
   `purchaseIntegrityOk` stays, now guarding spends against a balance the
   client can no longer inflate. Deploy and emulator-test before shipping;
   clients must be off the client-write path first (see order below).

4. **Optional server-side grading (residual hardening).** Move correctness
   scoring server-side so the answer tally is not client-claimed. This closes
   the last forgery surface but is the largest change and is warranted only
   if a leaderboard/economy depends on it.

## Local-only vs Firebase-project prerequisites

- **Local only (no Firebase project required):** Step 1 — the
  `LocalProgressRepository` and its tests run on `SharedPreferences` and have
  no network or rules dependency.
- **Firebase project / deployment required:** Steps 2–4 — the callable and
  its runtime, Admin SDK credentials, and deployed `firestore.rules`.
  These are out of scope for a repository-only change; the deployed project
  must be reconciled with the reviewed rules (per
  `docs/security/2026-07-26-stabilization-gate.md`).

## Compatibility order (do not break old clients)

1. Ship Step 1 (local outbox). Existing client counter writes still work;
   behavior is unchanged for users who never upgrade.
2. Deploy the callable (Step 2) and have *new* clients route credits through
   it while still tolerating the old client-written counters.
3. Only after telemetry shows no active clients writing counters directly,
   tighten the rules (Step 3). Tightening before clients migrate makes the
   app silently lose progress on old versions, because the existing writers
   (`score_screen.dart`, `quiz_screen.dart`) would be denied.

## Residual limitation

Until Step 4 (server-side grading), correctness and therefore points remain
client-claimed: a determined client can still report a session with inflated
`correctAnswers`. Steps 1–3 make writes authenticated, idempotent, and
server-owned, but they cannot make a client-claimed result authoritative.
State this in any thesis appendix that relies on the counters.

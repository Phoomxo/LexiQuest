# Progress Authority and Trusted-Writer Migration

Updated: 2026-07-29
Release A security status: remote economy writes are closed at the Firestore
rules boundary.

## Purpose

State the trust boundary for learner progress (points, answers, games) and the
shop balance. Release A keeps progress local and non-spendable, disables Shop
and leaderboard navigation, denies client writes to remote economy state and
purchase ownership, and preserves owner reads of legacy records. A trusted
server writer is still required before any remote economy can be reopened.

## Current writers and readers

The legacy schema can contain three divergent per-user counter stores. Only
`state.totalPoints` is referenced by the dormant Shop implementation.

### `state/{uid}` — legacy balance and wallpaper state

- Client write attempts:
  - `lib/screens/shop_page.dart` still contains the legacy purchase
    transaction, but production navigation and the screen itself are closed
    by `RemoteEconomyPolicy`, and Firestore rules reject its counter debit.
  - `lib/screens/select_wallpaper_screen.dart` may update only
    `selectedWallpaper` on an existing owner document.
  - `ScoreScreen` records progress through the local idempotent
    `ProgressRepository`; it no longer writes remote counters.
- Readers: dormant `ShopPage` and `UserService.getTotalPointsFromState` can
  read the legacy balance; `QuizScreen._loadBackground` reads the wallpaper.
- Rule: `firestore.rules` `match /state/{uid}` preserves owner reads, denies
  client creates and deletes, and permits updates only when
  `selectedWallpaper` is the sole affected field. Remote counters are
  read-only to clients.

### `users/{uid}` — profile with legacy counter fields

- `UserService.saveUserData` is an unused legacy helper whose payload omits
  required registration fields and is rejected on create by current rules.
  No active quiz path writes `points`, `totalPoints`, or `gamesPlayed`.
- The rules preserve existing `points`, `totalPoints`, and `gamesPlayed`
  fields during validated profile updates but deny clients from adding,
  changing, or removing any of them. They remain non-authoritative until a
  trusted migration reconciles them.
- `AppUser.fromMap` can read `points` for profile display compatibility.

### `purchased_items/{purchaseId}` — ownership records

- Dormant legacy writer: `lib/screens/shop_page.dart` `_buyProduct` attempts
  to write `user_id`, `product_id`, `total_price`, and `created_at` in the
  same transaction that debits `state.totalPoints`; current rules reject it.
- Readers: `lib/screens/shop_page.dart` `_buyProduct` (duplicate-purchase
  guard, filtered by `user_id` + `product_id`) and
  `lib/screens/select_wallpaper_screen.dart` (ownership list, filtered by
  `user_id`).
- Rule: `firestore.rules` `match /purchased_items/{purchaseId}` preserves
  owner reads of legacy ownership records and denies all client writes.

## Divergent points stores

Legacy data can contain `totalPoints` in both `state/{uid}` and `users/{uid}`,
plus a third `points` field on `users/{uid}`. These fields have no shared
authority and are not part of the local `ProgressRepository`.

Net effect: legacy documents can still contain three different "totals".
Release A treats all of them as non-authoritative, excludes them from remote
economy and research claims, and prevents clients from changing all three
stores. The redundant fields on `users/{uid}` remain a migration concern, but
no enabled purchase or leaderboard path consumes them.

## ScoreScreen persistence status

The former Firestore increment from `ScoreScreen.build()` has been removed.
`ScoreScreen` now records a stable `sessionId` through
`ProgressRepository.recordSession(...)`, and displays a device-local snapshot.
This closes rebuild-driven double counting without claiming that local results
are server-authoritative or spendable.

## Release A remote economy lockdown

The earlier exact-debit rule was insufficient because the same authenticated
client could first mint `state.totalPoints`, then debit the fabricated balance
and create a matching ownership record. Release A therefore closes both sides
of that chain at the trusted boundary:

- clients cannot create `state/{uid}` or change any remote counter;
- clients cannot add, change, or remove legacy counters on `users/{uid}`;
- a state update succeeds only when `selectedWallpaper` is the sole affected
  field;
- clients cannot create, update, or delete `purchased_items`;
- owner reads of existing state and ownership records remain available.

Firebase Admin SDK writes are not governed by client Firestore rules. Every
deployed privileged writer must therefore be inventoried and reviewed against
this authority contract. A future trusted writer can be deployed and validated
before narrowly reopening any client-facing workflow.

Firebase anonymous authentication remains available for entry to the product
shell and shared read-only content. Anonymous identities cannot read or write
remote profile, state, purchase, category, category-word, or telemetry
records; guest learning progress remains local.

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

The status of each step is stated explicitly; reopening the economy still
requires the trusted-writer sequence below.

1. **Local idempotent progress store (complete for Release A).**
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

3. **Rules deny client economy writes (complete for Release A).**
   `firestore.rules` denies client creation and counter mutation on
   `state/{uid}`, denies all client writes to `purchased_items`, and preserves
   legacy `users/{uid}` counters while making them immutable to clients.
   `selectedWallpaper` remains the only allowed state update. Before reopening
   the economy, reconcile the divergent counters, deploy the trusted writer,
   inventory every privileged writer, test deployed-policy parity, and route
   the client through the local outbox.

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
  and its privileged writers must be reconciled with the reviewed rules (per
  `docs/security/2026-07-26-stabilization-gate.md`).

## Compatibility order for reopening the economy

1. Keep Shop, purchases, leaderboards, and remote economy writes disabled.
   Old clients that attempt those writes are intentionally denied; their
   self-authored balances cannot remain a production authority.
2. Deploy the callable and validate authentication, App Check, bounds,
   idempotency, atomic debit, and rollback behavior.
3. Route new clients through local outbox → callable → acknowledgement while
   retaining the closed client rules.
4. Confirm telemetry shows no dependency on legacy client writers, migrate
   redundant `users/{uid}` counters, and only then design narrowly scoped
   rules or callable-only purchase flows.
5. Reopen Shop or leaderboard navigation only after deployed-policy parity
   and security gates pass on the same release SHA.

## Residual limitation

Local correctness and points remain client-observed and must not support
spending, rankings, or research claims. The Release A rules prevent those
values from becoming remote economy authority, but they do not create a
trusted progress pipeline. A future callable still needs server-side
validation and, if the product requires strong anti-cheat guarantees,
server-side grading. State this limitation anywhere legacy counters appear.

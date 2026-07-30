# LexiQuest Field-Test-Ready Development Program Design

**Date:** 2026-07-30  
**Status:** Approved master design for implementation  
**Primary target:** Android APK for a 30-participant field trial  
**Development strategy:** Local-first data spine with end-to-end vertical slices

## 1. Purpose

This program turns the current LexiQuest prototype into a field-testable Android
application whose visible results come from real participant activity. The
finished application must continue to support learning without a network,
survive process termination and device restart, synchronize safely when a
connection returns, and produce research exports that can be traced to stored
learning events.

There is no production Firebase data to preserve. The program may therefore
introduce a new versioned Firestore layout and local Drift schema without a
legacy cloud-data migration. Existing local development data is disposable, but
all schema changes after the first field APK must use explicit Drift migrations.

The program is complete only after all enabled participant-facing features use
real data or real device/provider input. A feature that cannot meet this rule
must be hidden from the field build. Fabricated confidence values, scores,
pronunciation measurements, AI responses, ownership records, and sample
research cards are not permitted.

## 2. Program Outcomes

The field build must provide:

1. Durable local categories, vocabulary, imports, sessions, answer attempts,
   reading progress, SRS state, points, achievements, ownership, and outbox
   operations.
2. Offline vocabulary management and learning flows that remain available when
   Firebase and Gemini are disabled.
3. Idempotent Firebase synchronization with deterministic conflict handling.
4. Guest-to-account upgrade without losing or duplicating local learning data.
5. Quiz, SRS, reading, weakness, mastery, streak, achievement, recommendation,
   and game progression derived from recorded participant activity.
6. Real camera, speech-to-text, text-to-speech, pronunciation, and on-device
   inference paths on supported Android devices.
7. Gemini bring-your-own-key support with Android Keystore protection and
   provider-specific error states.
8. Real CSV, PDF, Anki, and research dataset exports with cancellation and
   file-write recovery.
9. One Material 3 application shell with typed routes, accessible Thai text,
   dark mode, and no direct infrastructure calls from widgets.
10. A release-signed APK, participant documentation, consent flow, feedback
    path, known limitations, and evidence from three device tiers.

## 3. Delivery Model

### 3.1 Data spine plus vertical slices

The program does not build an entire technical layer in isolation. It first
establishes the minimum shared data spine, then completes one participant
journey at a time across:

`domain contract -> Drift transaction -> repository/use case -> UI -> outbox ->
Firebase -> analytics projection -> focused tests -> installable APK`

Each accepted slice becomes part of the next slice. Screens never create a
second source of truth. Drift is the authoritative runtime store; Firebase is a
replica and exchange mechanism.

### 3.2 Stable integration branch

Development continues on the current feature branch unless the owner explicitly
requests a branch change. Each work package:

1. freezes its input/output contract;
2. adds a failing behavior test for the current package;
3. implements only that package;
4. runs its focused verification;
5. reviews its diff;
6. integrates only when the package gate passes.

Unrelated generated-file changes and owner changes are preserved and excluded
from package commits.

### 3.3 Field-build feature policy

Features have one of three release states:

- `enabled`: real input, persistence, error handling, and acceptance evidence
  exist;
- `limited`: real implementation exists but is allowed only on a documented
  device/provider allowlist;
- `hidden`: the navigation entry and production path are absent from the field
  build.

There is no participant-visible `demo`, `random`, or `sample success` state.

## 4. Architecture

### 4.1 Layer boundaries

#### Presentation

Flutter screens and widgets render state and dispatch use cases. They may use
camera, microphone, file picker, and sharing only through injected application
ports. They do not import Firebase, HTTP clients, Drift tables, secure-storage
implementations, or platform work schedulers.

#### Application

Use cases coordinate transactions and policies such as:

- create, edit, delete, and import vocabulary;
- begin, answer, and finish learning sessions;
- record reading progress;
- schedule SRS reviews;
- award points and achievements;
- calculate weakness and recommendations;
- enqueue synchronization;
- upgrade guest ownership;
- export selected datasets;
- run model, camera, speech, and Gemini operations.

#### Domain

Immutable domain types define identifiers, timestamps, answer outcomes, SRS
ratings, points ledger entries, achievement conditions, ownership, sync
operations, research consent, and provider results. Domain code does not depend
on Flutter or infrastructure plugins.

#### Infrastructure

Adapters implement Drift, Firestore, Firebase Auth, Android WorkManager, Android
Keystore, Gemini REST, LiteRT, camera, STT, TTS, filesystem, PDF, and Anki
output. Infrastructure exceptions are converted to typed application failures.

### 4.2 Composition

`AppBootstrap` creates infrastructure adapters once. `AppDependencies` exposes
application ports and use cases. Tests replace ports with deterministic fakes.
Screens receive dependencies from the application scope or typed-route
arguments.

### 4.3 Runtime source of truth

All participant-facing queries read Drift. A successful local transaction
updates domain rows and appends an outbox operation atomically. The sync engine
sends outbox operations later and applies acknowledged cloud state back into
Drift. A cloud listener never bypasses Drift to update the UI.

## 5. Local Data Design

Every table uses stable string identifiers generated on device, UTC timestamps,
an `owner_id`, a monotonic local revision, and a deletion marker where
appropriate.

### 5.1 Identity and consent

- `local_owners`: local guest identity, optional Firebase UID, account state,
  creation time, and upgrade time.
- `research_consents`: consent version, accepted/withdrawn state, timestamps,
  and export eligibility.
- `app_installations`: installation ID, app version, build ID, and device-tier
  classification without direct personal identifiers.

### 5.2 Vocabulary

- `categories`: name, normalized name, sort order, ownership, revision, and
  tombstone.
- `words`: category ID, spelling, normalized spelling, meaning, part of speech,
  CEFR metadata, source, ownership, revision, and tombstone.
- `imports`: source type, filename hash, started/completed status, counts, and
  failure summary.
- `import_rows`: import ID, row number, normalized payload hash, accepted,
  rejected, or duplicate status.

Uniqueness uses owner, category, and normalized content keys. Import retries use
the import-row hash to avoid duplicate vocabulary.

### 5.3 Learning evidence

- `learning_sessions`: activity type, start/end time, completion state, score
  summary, and source build.
- `answer_attempts`: session ID, word ID, prompt mode, correctness, measured
  response time, attempt number, and optional provider provenance.
- `reading_progress`: document ID, last position, completion state, and update
  time.
- `reading_events`: opened, position-changed, completed, and abandoned events.
- `association_records`: participant-created associations linked to words.

Raw microphone audio, camera frames, prompt text containing personal data, API
keys, access tokens, and passwords are not stored in learning tables.

### 5.4 Derived learning state

- `srs_states`: word ID, stability/ease fields required by the selected
  algorithm, interval, repetitions, lapses, last review, and due time.
- `weakness_snapshots`: versioned projections with source-attempt counts.
- `recommendation_snapshots`: ranked word/activity recommendations with reason
  codes and evidence counts.
- `daily_activity`: date, answered count, correct count, active minutes, and
  completed sessions.

Derived rows can be rebuilt from immutable evidence. Evidence rows are not
rewritten to change an aggregate.

### 5.5 Progress and ownership

- `points_ledger`: append-only award/spend entries with idempotency key and
  source event.
- `achievements`: achievement definition version and visibility.
- `achievement_unlocks`: owner, achievement, source event, and unlock time.
- `catalog_items`: avatar equipment and wallpaper definitions.
- `owned_items`: owner, catalog item, acquisition ledger entry, and equipped
  state.
- `game_progress`: mode, level, experience, rank, and source revision.

Balances and ownership are computed or transactionally updated from the ledger.
The shop remains hidden until purchase, balance, ownership, and restore tests
pass.

### 5.6 Synchronization

- `outbox_operations`: operation ID, entity type, entity ID, operation kind,
  payload version, base revision, attempt count, next attempt time, and state.
- `sync_checkpoints`: owner, collection, last server cursor, and last success.
- `sync_conflicts`: local/cloud revisions, resolution policy, outcome, and
  timestamp.
- `model_downloads`: model version, expected checksum, bytes downloaded, retry
  state, and activation state.

## 6. Synchronization Design

### 6.1 Local commit

Creating or changing synchronized data is one Drift transaction:

1. validate the domain command;
2. update the local entity;
3. increment its local revision;
4. append a deterministic outbox operation;
5. commit;
6. notify local query streams.

The UI reports success after the local commit. Cloud availability does not
control offline learning success.

### 6.2 Push

The sync worker claims a bounded batch, sends idempotency keys, and records an
acknowledgement. Retries use bounded exponential backoff with jitter and a
maximum retry delay. Authentication, permission, validation, quota, and
transient network failures produce different operation states.

The worker never logs entity payloads, API keys, tokens, email addresses, or
personal content.

### 6.3 Pull

After push, the worker requests changes after the stored checkpoint. Pulled
changes enter Drift in a transaction and advance the checkpoint only after all
changes apply successfully.

### 6.4 Duplicate prevention

- stable client-generated entity IDs;
- stable outbox operation IDs;
- unique database constraints on natural duplicate keys;
- Firestore transaction checks for operation acknowledgement;
- replay-safe points, achievement, import, and answer-event idempotency keys.

### 6.5 Conflict policy

- Immutable events and ledger entries: union by stable ID.
- Category and word edits: highest acknowledged revision wins; equal revisions
  use the latest server UTC update, with the losing value recorded in
  `sync_conflicts`.
- Delete versus edit: tombstone wins unless the edit is based on a later
  acknowledged revision.
- SRS: replay missing answer attempts and recompute state; do not merge derived
  intervals field by field.
- Reading position: furthest position wins within the same document revision;
  completed state cannot be reverted by an older update.
- Equipped items: latest valid ownership-backed command wins.

### 6.6 Guest upgrade

The first launch creates a local owner before Firebase is required. Anonymous
Firebase sign-in later binds a UID to that owner. Credential linking is the
preferred upgrade path because it retains the UID. If linking returns a
different existing UID, one local transaction reassigns all owner-scoped rows,
rewrites pending outbox ownership, and records an upgrade marker. Replaying the
upgrade is a no-op.

### 6.7 Android background execution

WorkManager schedules constrained sync when a network is available and triggers
an immediate foreground-safe sync after local changes, login, app resume, and
manual retry. Work is unique per owner and cannot run concurrently for the same
owner. Android may defer background work; foreground use must not depend on its
timing.

## 7. Development Increments and Stage Gates

### Gate 0: Reproducible baseline

#### Work

- Record current analyzer, Flutter test, backend test, and Android debug-build
  results.
- Classify pre-existing failures by owner and affected feature.
- Add field-build feature flags and hide known fabricated participant paths.
- Establish test fixtures, deterministic clock/ID sources, and build identity.

#### Exit criteria

- Baseline evidence is stored in the development record.
- Current build can be reproduced from documented commands.
- No new work package is held responsible for an unrelated pre-existing
  failure, but all release-blocking failures remain visible.

### Gate 1: Local data spine and vocabulary journey

#### Work

- Add Drift/SQLite and schema migrations.
- Implement identity, categories, words, imports, sessions, attempts, SRS,
  reading, progress, ownership, and sync tables.
- Replace direct Firebase access for category and vocabulary CRUD with local
  repositories and use cases.
- Persist imports transactionally with per-row results.
- Complete the offline vocabulary journey and process-restart recovery.

#### Exit criteria

- Guest can create, edit, delete, and import vocabulary without a network.
- Data survives app termination and restart.
- Every visible vocabulary query reads Drift.
- Duplicate category, word, and import behavior is deterministic.

### Gate 2: Reliable cloud synchronization and account ownership

#### Work

- Introduce the versioned Firestore schema and sync gateway.
- Implement push, pull, outbox retry, checkpoints, tombstones, and conflict
  records.
- Implement anonymous binding, guest upgrade, logout, and owner switching.
- Add WorkManager background synchronization and cloud kill switch.
- Add Firebase rules/emulator contract tests for the new schema.

#### Exit criteria

- Offline changes synchronize exactly once after reconnection.
- Repeated sync and process restarts do not duplicate entities or points.
- Guest upgrade preserves local data.
- Disabling cloud leaves all local learning features usable.

### Gate 3: Core learning evidence

#### Work

- Migrate Quiz to local vocabulary.
- Persist session lifecycle, each answer, response time, correctness, and score.
- Select and document one SRS algorithm and calculate due dates from attempts.
- Persist reading position, completion, and reading events.
- Generate weakness, mastery, streak, achievement, recommendation, and game
  progression projections from stored evidence.
- Remove built-in participant data from Mastery Dashboard, Weakness Clinic,
  Ghost Shadow Duel, Weakness SRS, AI Tutor, and Shadowing Challenge.

#### Exit criteria

- A complete quiz produces auditable sessions, attempts, SRS state, points, and
  projections.
- Reading resumes at the stored position after restart.
- Empty accounts show empty states and sample size zero, not sample content.
- Rebuilding projections from evidence produces the same result.

### Gate 4: On-device model lifecycle

#### Work

- Select and license the field model and record its input/output contract.
- Implement resumable download, retry, checksum verification, activation, and
  rollback.
- Implement the LiteRT inference adapter.
- Benchmark CPU and XNNPACK on each device tier.
- Enable GPU delegate only for allowlisted model/device/driver combinations
  that pass correctness, stability, memory, and thermal checks.

#### Exit criteria

- A corrupted or incomplete model is never activated.
- Download interruption resumes without restarting valid bytes.
- CPU inference produces repeatable real outputs within the documented budget.
- The UI does not claim GPU readiness outside the tested allowlist.

### Gate 5: Camera and speech journeys

#### Work

- Implement camera permission, preview, capture, pause/resume, rotation, and
  lifecycle cleanup.
- Run Object Scanner through the activated model and persist accepted
  vocabulary through the standard use case.
- Implement microphone permission, audio capture, STT, TTS, and cancellation.
- Derive pronunciation feedback only from real transcript/acoustic evidence and
  expose method provenance and unavailable states.
- Remove random confidence, pitch, phoneme, and score paths.

#### Exit criteria

- Camera and audio denial, interruption, backgrounding, and return are safe.
- Object results originate from model inference.
- Speech results originate from captured audio.
- Unsupported measurements are not shown.

### Gate 6: Gemini BYOK and AI Tutor

#### Work

- Implement add, validate, replace, and remove key journeys.
- Store the key in Android Keystore-backed secure storage.
- Implement Gemini REST requests with explicit timeout and cancellation.
- Map invalid key, quota, offline, timeout, provider outage, and malformed
  response errors.
- Build AI Tutor context from consented local learning summaries.
- Redact request metadata and prohibit secrets/personal data in logs.

#### Exit criteria

- The key never enters Drift, Firestore, analytics, crash text, or logs.
- Removing the key prevents future provider calls.
- AI Tutor has no canned successful answer.
- Provider failure does not block local study.

### Gate 7: Progress, rewards, export, UI, and account journeys

#### Work

- Complete ledger-backed points, achievements, shop transactions, ownership,
  equipment, wallpaper, and progression; hide any incomplete commerce surface.
- Generate CSV, PDF, Anki, and research datasets from selected local records.
- Support progress, cancellation, permission denial, insufficient space, and
  partial-file cleanup.
- Show chart sample sizes, definitions, and no-data explanations.
- Move all screens to typed routes and one Material 3 theme.
- Correct Thai encoding/copy, minimum touch targets, scaling, contrast, and
  dark mode.
- Complete registration, login, email verification, password reset, App Links,
  password change, logout, and upgrade journeys.
- Configure cloud budget alerts at 50%, 80%, and 100%.

#### Exit criteria

- Enabled reward/shop surfaces have transactional ownership.
- Exported files open in independent applications and match selected records.
- No screen imports Firebase, HTTP, Drift, or platform plugins directly.
- Automated account journeys pass against the approved test environment.

### Gate 8: Field certification

#### Work

- Run automated participant journeys across enabled features.
- Test offline, force-stop, restart, reconnect, and synchronization.
- Test clean install, upgrade, device restart, background, and foreground.
- Test low-, mid-, and high-tier Android devices.
- Test camera, CPU/GPU policy, TTS, STT, and Gemini with real services.
- Run a 30-minute continuous-use thermal, RAM, battery, and stability session.
- Produce and verify a release-signed APK.
- Prepare consent/privacy text, installation guide, feedback channel, support
  escalation, and known limitations.
- Complete owner smoke test before participant distribution.

#### Exit criteria

- All release-blocking journeys pass on the required device matrix.
- Data exported after a sync round trip matches local evidence counts.
- The APK signature, version, build ID, and upgrade path are recorded.
- The owner approves distribution to 30 participants.

## 8. Verification Policy Without Unbounded Test Loops

### 8.1 Four bounded verification levels

#### Level A: Work-package test

Run only the new behavior test and directly affected unit tests. This is the
red/green cycle for the current change.

#### Level B: Slice regression

At the end of a coherent slice, run tests for the affected repository, use
case, screens, and data migration. Do not run unrelated device/model/backend
suites.

#### Level C: Integration gate

When a slice joins the field branch, run Flutter analysis, the relevant
integration journey, database migration tests, and an Android debug build.

#### Level D: Release gate

Run the full bounded verification suite once per release candidate and after a
release-blocking fix. Device acceptance is run on the matrix defined by the
current gate, not after every code edit.

### 8.2 Failure handling

1. A failure is classified as current-package, regression, pre-existing, or
   environment.
2. Current-package and true regression failures block the package.
3. Pre-existing unrelated failures are recorded and assigned to their planned
   gate; they do not trigger unrelated edits inside the current package.
4. Environment failures require one diagnostic pass and one controlled rerun
   after the cause is changed.
5. Repeating the same command without a code, configuration, or environment
   change is prohibited.
6. If the same failure remains after two evidence-based correction attempts,
   stop implementation for that package, perform root-cause analysis, and
   revise the package contract or escalate the blocker.
7. A tool retry loop, repeated filesystem error, or ten minutes without
   measurable progress causes an immediate stop and report.

### 8.3 Release blocker priority

Fix order is:

1. data loss, corruption, ownership crossover, consent, or secret exposure;
2. app crash, startup failure, migration failure, or unusable offline journey;
3. sync duplication or conflict-policy failure;
4. incorrect learning evidence, SRS, points, exports, or research counts;
5. broken device/provider journey;
6. accessibility and field-usage blockers;
7. cosmetic defects.

Lower-priority defects do not interrupt an active higher-priority package unless
they prevent its acceptance test.

### 8.4 Verification commands

The exact commands and test files belong in each sub-project implementation
plan. Repository-wide verification uses the existing CPU-safe CLI and bounded
local checks: Flutter analysis/tests, backend tests, Firestore policy/emulator
tests, Supabase policy tests when affected, Gitleaks, OSV Scanner, dependency
audits, and focused manual diff review. Codex Security, Security Scan, Deep
Scan, and Codex Security worker workflows are excluded.

## 9. Data Collection and Research Integrity

### 9.1 Collected evidence

The research dataset may include pseudonymous installation/owner ID, consent
version, app/build version, activity type, content ID, category/CEFR metadata,
timestamps, response time, correctness, attempt number, SRS schedule, reading
progress, model/provider provenance, and device-tier performance aggregates.

### 9.2 Excluded data

Exports and telemetry exclude API keys, auth tokens, passwords, email addresses,
raw camera frames, raw microphone audio, unredacted AI prompts, and direct
personal identifiers unless a separately reviewed protocol explicitly requires
them.

### 9.3 Traceability

Every dashboard value and export aggregate states its sample size and can be
traced to immutable evidence IDs. Derived projections declare algorithm and
schema versions. Withdrawing consent stops future research export eligibility
without destroying learning functionality.

## 10. Operational Controls

- Cloud kill switch blocks new cloud work while preserving local study.
- Provider-specific switches disable Gemini, model download, GPU delegate,
  camera inference, or speech paths independently.
- Model and schema versions are recorded with produced evidence.
- Sync batch size, retry limits, and upload cadence are remotely bounded but
  have safe local defaults.
- Budget alerts are configured at 50%, 80%, and 100% of the approved monthly
  Firebase/Gemini budget.
- Participant logs are privacy-safe and exportable for support without secrets.

## 11. Sub-Project Plan Structure

After this master design is approved, implementation is decomposed into these
ordered plans:

1. `P0 Baseline and field feature controls`
2. `P1 Drift data spine and offline vocabulary`
3. `P2 Firebase sync, WorkManager, and guest ownership`
4. `P3 Quiz, SRS, reading, and evidence-derived progress`
5. `P4 LiteRT model lifecycle and benchmark policy`
6. `P5 Camera, STT, TTS, and pronunciation`
7. `P6 Gemini BYOK and AI Tutor`
8. `P7 Rewards, exports, typed navigation, UI, and account completion`
9. `P8 Android field certification and participant package`

Each plan identifies exact files, interfaces, migrations, tests, commands,
expected results, commits, and its dependency on earlier accepted plans. A plan
does not contain work from a later gate merely because a full-suite test exposes
it.

## 12. Definition of Field-Test Ready

LexiQuest is field-test ready when:

- the participant can complete all enabled journeys with intermittent or no
  connectivity;
- local data survives process death, restart, upgrade, and guest conversion;
- synchronization is idempotent and conflict behavior is documented;
- visible learning, progress, reward, AI, camera, speech, and export results
  originate from real stored evidence or real providers;
- unsupported functionality is clearly unavailable or absent;
- consent and privacy controls are active;
- automated gates and the three-tier device matrix pass;
- the release-signed APK passes the owner smoke test;
- the participant package explains installation, consent, feedback, support,
  and known limitations.

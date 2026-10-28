# LexiQuest Real Local-First Prototype Design

## 1. Objective

LexiQuest v0.1 is an Android functional prototype for academic demonstration
and an invited test group. Every visible feature must be connected to a real
data source, device API, deterministic algorithm, or configured external
provider. Production code must not fabricate user history, camera results,
speech measurements, AI responses, purchases, or export observations.

The prototype may simplify an algorithm or reduce visual complexity. It may
also show a truthful unavailable state when a required device capability,
permission, API key, network connection, or remote service is absent.

The prototype is not presented as a production launch. Production-scale
operations, public enrollment, service-level guarantees, and store publication
remain outside this scope.

## 2. Binding decisions

- Platform: Android 10 or newer.
- Baseline device: 4 GB RAM and 2 GB free storage.
- Recommended device: 6 GB RAM or more.
- App version line: `0.1.0`; each distributed prototype increments build
  number.
- Identity and synchronization provider: Firebase only.
- AI provider: Gemini only, using a user-supplied API key.
- Local source of truth: Drift/SQLite.
- Remote account source of truth: Firebase Auth.
- Remote synchronized state: Firestore and trusted Firebase Functions.
- No Supabase runtime dependency.
- No developer Gemini key or fallback AI secret in the APK.
- Branch names do not contain `codex`.
- Every unavailable feature explains why it is unavailable and how to recover.

## 3. Definition of a real connected feature

A feature is connected when all of the following are true:

1. Its production entry point is reachable through the typed route registry.
2. Its input comes from the user, persisted application state, a device API,
   or an explicitly configured provider.
3. Its result is produced by a documented deterministic algorithm, real
   on-device inference, or a real provider response.
4. Its successful mutation is persisted locally before the UI reports
   completion.
5. A syncable mutation receives a stable operation ID and enters the outbox.
6. Restart, empty, offline, denied-permission, recoverable-error, and permanent
   unavailable states are implemented.
7. The feature does not substitute sample or random output for a failed
   dependency.

Test fakes remain permitted under `test/` and `integration_test/`. Curated
learning content is permitted when it is versioned product content and is
identified as such rather than presented as a user's generated history.

## 4. Application architecture

### 4.1 Layers

Each feature uses four layers:

1. Presentation: Material 3 screens, typed routes, forms, and state rendering.
2. Application/domain: use cases, validation, learning rules, game rules, and
   provider-independent contracts.
3. Local data: Drift repositories, file storage, secure key storage, and the
   sync outbox.
4. Adapters: Firebase, Gemini, Android device APIs, TensorFlow Lite, camera,
   speech, TTS, and file sharing.

Screens do not instantiate Firebase, HTTP clients, secure storage, camera,
speech, or inference plugins. `AppDependencies` owns production adapters and
tests inject provider-neutral fakes.

### 4.2 Canonical local records

Drift stores:

- users and guest/local owner identities;
- categories, vocabulary, imports, and tombstones;
- immutable learning-session and answer events;
- SRS review events and derived scheduling state;
- progress, mastery, weakness, streak, quest, achievement, and world
  projections;
- locally visible economy balance, ownership, equipment, and pending trusted
  operations;
- content-pack metadata;
- export jobs and their source filters;
- sync outbox entries and failure metadata;
- schema and migration state.

UI reads local projections. Remote snapshots are applied to local tables and
never become an alternate screen-specific source of truth.

## 5. Offline synchronization

Every syncable operation contains:

- operation ID;
- owner ID;
- entity type and entity ID;
- local revision;
- creation timestamp;
- payload schema version;
- attempt count and next-attempt timestamp;
- state: pending, in-flight, acknowledged, retryable failure, permanent
  failure, or conflict.

The foreground worker runs after authenticated boot and connectivity recovery.
Android WorkManager performs bounded background retries. Backoff is
exponential with jitter and a maximum delay. Saving a lesson never waits for
remote acknowledgement.

Conflict policy:

- learning events append by immutable ID;
- SRS derives from ordered review events;
- vocabulary updates use revisions and retain a visible conflict copy;
- deletions use tombstones until acknowledged;
- trusted economy operations are idempotent and server-authoritative;
- guest upgrade reassigns local ownership once and uploads through the same
  outbox.

## 6. On-device CPU/GPU execution

### 6.1 Capability profile

The app records a bounded capability profile using Android version, ABI,
available memory, free storage, battery saver, thermal status, and a short
inference benchmark. It assigns:

- Lite: CPU/XNNPACK, compact model, reduced frame frequency, restrained
  animation.
- Balanced: CPU with available native accelerators and standard analysis
  frequency.
- Enhanced: Android GPU delegate when initialization and benchmark succeed.

Capability selection never depends only on a model name or the ability to run
a game. Failed GPU initialization falls back to CPU and records a
non-sensitive reason.

### 6.2 Real device features

- Camera uses the Android camera feed and explicit permission handling.
- Object recognition uses a bundled, checksummed TensorFlow Lite model.
- GPU delegate is attempted only on Enhanced devices; XNNPACK CPU is the
  fallback.
- Native Android TTS is the dependable offline speech-output baseline.
- Android speech recognition supplies real captured speech where supported.
- Pronunciation screens distinguish acoustic measurements from documented
  heuristic estimates.
- Heavy camera/audio inference stops when the app backgrounds, battery saver
  requires it, or thermal status becomes severe.
- Buffers, controllers, delegates, and interpreters are released on lifecycle
  transitions.

Optional model packs are versioned, checksummed, atomic, removable, and never
contain personal data or secrets.

## 7. Gemini BYOK

The Gemini implementation uses a provider-independent `AiProvider` and a
single production `GeminiProvider`.

- The user can save, validate, replace, and delete a key.
- The key is stored only through Android Keystore-backed secure storage.
- Validation uses a minimal bounded request.
- Invalid key, quota, unsupported model, timeout, offline, and provider outage
  remain distinguishable.
- Logs redact authorization data, URL query values, prompts, responses, and
  key-like strings.
- Generated content is length-bounded, labeled as Gemini-generated, and
  validated before entering a lesson.
- If Gemini is unavailable, curated offline content may be used only when it
  fulfills the same learning purpose and is labeled as curated content.
- Live AI tutor actions show unavailable rather than returning canned text.

## 8. Feature behavior

### 8.1 Vocabulary and practice

Personal vocabulary supports create, edit, delete, bulk entry, import,
restart recovery, and outbox sync. Quiz, SRS, scramble, cloze, dictation,
CEFR, weakness, associative reading, and recommendation features consume real
local vocabulary and learner events. Empty libraries provide onboarding
actions.

### 8.2 Reading and story

Curated article and story packs are versioned product content. Generated
stories require Gemini and are stored with source metadata. No `_sample*`
production list is presented as user-generated content.

### 8.3 Voice and pronunciation

TTS, STT, dictation, shadowing, and pronunciation screens use device adapters.
Pitch or alignment values derived from heuristics are labeled estimates.
Random pitch curves and simulated phoneme measurements are prohibited.

### 8.4 Object scanner

The scanner displays a real preview, analyzes captured frames, applies a
confidence threshold, presents an uncertain state when appropriate, asks for
confirmation, and saves the confirmed word into the real vocabulary
repository. Images are not uploaded by default.

### 8.5 Progress and game systems

World map, bosses, ghost duel, mastery, streaks, quests, ranks, and
achievements derive from canonical learning events. The ghost opponent is a
deterministic bot using persisted weakness data; it is not described as a
trained AI model.

### 8.6 Economy

Point awards, purchases, ownership, equipment, and wallpaper selection use
trusted idempotent operations. The local database may show pending operations
offline, but spendable remote balance is reconciled with the trusted writer.
No screen-local balance or pre-owned sample equipment is authoritative.

### 8.7 Research and exports

CSV, SPSS-style, PDF, glossary, Anki/dictionary, appendix, and chart exports
read selected persisted records. Exports include schema version, time zone,
app version, build ID, filters, and sync status. Empty selections produce an
honest empty artifact. Share cancellation and write failures are visible.

## 9. Navigation and UI

The typed registry contains the canonical five top-level destinations and
every included feature route. Legacy `MaterialPageRoute` bridges and direct
remote screen construction are removed after migration.

All production screens use the central Material 3 theme, shared page scaffold,
buttons, forms, cards, loading states, empty states, and errors. Thai copy is
natural UTF-8. Prototype labels describe algorithm or provider limitations;
they are not used to excuse fabricated data.

## 10. Error handling and privacy

- Error categories remain typed: validation, offline, permission, timeout,
  authentication, quota, conflict, storage, provider unavailable, and
  permanent unsupported.
- Logs exclude email, password, token, action code, Gemini key, prompt,
  vocabulary content, raw audio, and captured images.
- Global boundaries keep a single feature failure from crashing the shell.
- Diagnostics show local database, sync, Gemini, camera model, speech, and
  Firebase availability without exposing secrets.

## 11. Verification cadence

Implementation does not run the complete verification suite after every
sub-item.

- A work package uses focused tests for the code it changes.
- One consolidated gate runs at the end of each major phase.
- Full Flutter, backend, policy, CLI, and APK verification runs only at
  integration milestones and the final candidate.
- A failing phase gate is diagnosed once and fixed before the next phase.
- Repeated filesystem or tool errors trigger the repository stop rule rather
  than a retry loop.

## 12. Prototype completion gate

The prototype is ready for academic demonstration only when:

1. every production menu has a real connected behavior or truthful unavailable
   state;
2. confirmed sample, simulation, placeholder, and canned-response production
   paths are removed;
3. core learning works offline and reconnect synchronization is demonstrated;
4. camera, TTS, STT, and on-device inference run on a physical Android device;
5. Gemini key lifecycle passes without a bundled provider secret;
6. economy and exports use persisted real records;
7. navigation and UI use one system;
8. migration from a representative prior database is restart-safe;
9. the exact prototype commit passes consolidated verification;
10. a signed prototype APK installs, launches, restarts, and completes the
    demonstration script on Android 10/4 GB;
11. Firebase email/App Link and any paid cloud gates are explicitly recorded;
12. the final hash, commit, build command, known limitations, and rollback APK
    are recorded.


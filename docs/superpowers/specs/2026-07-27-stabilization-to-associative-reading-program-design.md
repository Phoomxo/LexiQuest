# LexiQuest Stabilization-to-Associative Reading Program Specification

- **Date:** 2026-07-27
- **Current integration branch:** `feature/production-vertical-slices`
- **Planned feature branch:** `feature/associative-reading-loop`
- **Status:** Draft for owner review
- **Scope:** Complete and stabilize the existing product before adding the
  associative-memory and mixed-vocabulary reading system.
- **Implementation model:** Cointh/GLM is the primary patch author. Codex
  decomposes work, constrains prompts, reviews every proposed change, applies
  approved patches, runs verification, and controls commits and pull requests.

## 1. Purpose

This document is the controlling specification for the next LexiQuest
development program. Its purpose is to prevent an implementation model from:

- mixing unfinished stabilization work with new learning features;
- changing architecture, dependencies, security policy, or user-visible
  behavior without an explicit requirement;
- editing many files in one unreviewable patch;
- presenting simulated, unavailable, or unverified behavior as production
  functionality;
- weakening tests to make a patch appear successful;
- consuming model tokens without producing reviewable engineering value.

The program has two strictly ordered releases:

1. **Release A — Stabilized LexiQuest:** finish, secure, integrate, and verify
   the existing application.
2. **Release B — Associative Reading:** add association-assisted recall and
   mixed-vocabulary reading as one adaptive learning loop.

Release B implementation must not begin until the Release A exit gate passes
and its pull request is merged or the owner explicitly authorizes an isolated
prototype that cannot enter the production branch.

## 2. Product outcome

LexiQuest will become a research-ready vocabulary-learning application in
which a learner:

1. encounters a planned mixture of due, weak, confusable, and new words in a
   level-appropriate passage;
2. reads with initial support;
3. recalls words after cues are progressively removed;
4. creates or selects a meaningful personal association;
5. transfers the word into a new context;
6. feeds objective recall evidence into a versioned spaced-repetition model.

The product must remain usable when optional AI or voice services are
unavailable. AI supplies suggestions and content candidates, not unquestioned
truth. Learning progress and research events must be reproducible,
versioned, privacy-aware, and distinguishable from simulated data.

## 3. Non-negotiable invariants

### 3.1 Release and repository invariants

1. Release A is completed before Release B production code.
2. Branch and pull-request names must not use a `codex/` prefix.
3. The existing branch is preserved. No destructive reset, force push, or
   automatic rebase is allowed.
4. Before any push, remote divergence must be reviewed and reconciled without
   discarding either the owner’s work or collaborator commits.
5. Each commit represents one coherent, passing unit of work.
6. Generated files, caches, model weights, credentials, and machine-local
   configuration are not committed.
7. The Flutter package name may remain `vocab_learning_app` during Release A
   to avoid an unrelated mass import rename.

### 3.2 Security and data invariants

1. Authentication, authorization, and economy failures must fail closed.
2. A client must never be authoritative for points, purchases, quiz rewards,
   verification status, model identity, or research-group assignment.
3. Anonymous Firebase users are treated as guests, not trusted authenticated
   users.
4. Guests may keep local learning progress but may not mutate shared curated
   vocabulary, global word indexes, economy state, or research telemetry.
5. No API key, Firebase token, service-role key, model token, or legacy
   credential may appear in source, tests, logs, screenshots, or model
   prompts.
6. Model artifacts must be revision-pinned, integrity-checked, and loaded
   without arbitrary remote code.
7. Raw microphone audio is not retained by default.
8. User-created memory associations are private by default.

### 3.3 Runtime invariants

1. Voice API and LexiQuest-LM remain separate Python environments.
2. Release A must not start or resume GPU training.
3. One bounded real OmniVoice inference smoke test is allowed only after
   static, CPU, and unit gates pass.
4. No patching of Flutter, Pub, Gradle, Python, or package-manager caches is
   permitted.
5. An optional service failure must produce a truthful unavailable or fallback
   state, never a fabricated success.
6. Tests must not download model weights, contact paid APIs, or require a GPU
   unless they are explicitly labeled bounded integration tests.

### 3.4 Research invariants

1. Algorithm, content, schema, and experiment versions are stored with events.
2. Treatment assignment is stable and server-controlled for consented
   participants.
3. Research mode never silently enrolls a learner or upload data without
   consent.
4. Experimental conditions differ only by the intervention under study.
5. Self-reported confidence cannot be the sole basis of correctness or score.
6. Simulated scanner, AI, voice, or research results must be visibly labeled
   as simulated.

## 4. GLM execution contract

This section is mandatory for every Cointh/GLM coding request.

### 4.1 Roles

- **Codex owns:** task decomposition, context selection, acceptance criteria,
  security decisions, patch review, file application, test execution,
  regression analysis, commits, branch operations, and pull requests.
- **GLM owns:** analysis of the supplied microtask and production of a minimal
  proposed patch or focused review.
- **GLM does not own:** expanding scope, selecting unrelated dependencies,
  committing, pushing, editing secrets, weakening tests, or declaring the
  repository complete.

### 4.2 Unit of work

1. One GLM request addresses one behavior.
2. One GLM request edits one file by default.
3. A second file is allowed only when it is the inseparable focused test or a
   mechanical rename required for compilation. The exception must be stated
   in the prompt before generation.
4. A behavior change follows separate **RED**, **GREEN**, and optional
   **REFACTOR** requests.
5. GLM calls run sequentially. Parallel burst calls are prohibited because the
   Cointh gateway has a five-hour usage window and burst failures lose useful
   work.
6. A failed or rate-limited request is recorded and retried only after the
   gateway reset. It is not replaced with fabricated GLM output.
7. Model effort is set to the highest supported mode, but token use must be
   productive. Repetition, filler, intentional token burning, and artificial
   expansion are prohibited.

### 4.3 Required prompt envelope

Every implementation prompt must contain these fields:

```text
SYSTEM: You are the patch author for one bounded LexiQuest microtask.

TASK-ID: <release.phase.sequence>
PHASE: RED | GREEN | REFACTOR | REVIEW
OBJECTIVE: <one observable behavior>
ALLOWED-FILES:
  - <one exact repository-relative path>
OPTIONAL-SECOND-FILE:
  - <exact path and reason, or NONE>
READ-ONLY-CONTEXT:
  - <minimal contracts or short snippets>
FORBIDDEN:
  - Edit any unlisted file
  - Change public behavior outside OBJECTIVE
  - Add or upgrade dependencies
  - Weaken, delete, skip, or broadly rewrite tests
  - Read, print, request, or embed secrets
  - Patch generated files or package caches
  - Perform Git operations
ACCEPTANCE-CRITERIA:
  1. <binary condition>
  2. <binary condition>
TEST-COMMAND: <one focused command Codex will run>
OUTPUT:
  1. Assumptions, maximum 5 bullets
  2. Unified diff only for ALLOWED-FILES
  3. Risks, maximum 5 bullets
  4. No prose after the diff except risks
```

If GLM cannot satisfy the task without another file or architectural decision,
it must return `BLOCKED` with the exact reason and no patch.

### 4.4 Patch rejection rules

Codex rejects a proposed patch if it:

- touches an unlisted file;
- changes formatting across unrelated code;
- introduces a new dependency without a separately approved dependency task;
- catches an error and converts it into success;
- trusts a client-provided identity, score, price, role, or model revision;
- bypasses a test, analyzer, security rule, or type check;
- changes a public API without named caller migration;
- logs credentials, request bodies containing private content, or raw audio;
- depends on network, GPU, wall-clock timing, or nondeterministic randomness in
  a unit test;
- claims completion without the stated command passing under Codex control.

### 4.5 Review and commit protocol

For each accepted microtask, Codex:

1. verifies the patch is inside the file allowlist;
2. reviews the diff against this specification;
3. applies the patch;
4. runs the focused test;
5. runs the nearest affected suite;
6. inspects the working-tree diff;
7. commits only the coherent passing unit;
8. reports actual useful GLM usage when telemetry is available.

No model-generated statement substitutes for a local test result.

## 5. Release A — Stabilized LexiQuest

### 5.1 A1 — Authentication correctness

#### Required behavior

1. Account creation uses only the password entered on the registration screen.
2. Account creation sends the first verification email to that newly created
   Firebase user.
3. Resending verification uses the current Firebase user. It must never create
   an account and must never use a hard-coded or generated password.
4. A resend request must compare the expected email with the current user’s
   normalized email. Missing user, missing email, or mismatch fails closed.
5. Verification checking reloads the current user and then re-reads the
   refreshed Firebase user before checking `emailVerified`.
6. No signed-in user returns “not verified.” A verified user returns “verified.”
   Backend/network errors are surfaced as typed failures and never converted
   to `true`.
7. The profile form does not request, accept, or ignore a second password.
8. UI screens depend on an injectable verification abstraction so tests do not
   require Firebase or network access.

#### Required interface boundary

```text
EmailVerificationGateway
  createAccountAndSendVerification(email, password)
  resendForCurrentUser(expectedEmail)
  reloadAndCheckCurrentUser()
```

The concrete Firebase adapter may use project-specific result types, but
screens must not call FirebaseAuth directly for this flow.

#### Acceptance tests

- Resend invokes verification on the current user and invokes no account
  creation method.
- Email matching is case-insensitive after trimming.
- User absence and email mismatch return a visible failure.
- Reload failure does not return verified.
- The refreshed user object determines the final state.
- The registration password reaches account creation exactly once.
- The profile form contains no duplicate password field or unused password
  argument.
- Focused unit and widget tests pass without Firebase initialization.

### 5.2 A2 — Firestore authorization and economy integrity

#### Required behavior

1. Direct client writes to `state/{uid}.totalPoints`, user points,
   `gamesPlayed`, shop ownership, prices, and purchase ledger state are denied.
2. A purchase is performed by a trusted backend transaction that reads the
   canonical item price, checks balance and ownership, subtracts points, and
   records ownership atomically.
3. Quiz rewards are not accepted from a raw client-provided point delta.
   Production reward credit requires a server-issued quiz session or
   server-verifiable result token.
4. Until the authoritative reward path is deployed, remote economy mutation is
   disabled and the UI truthfully marks it unavailable. Local practice
   progress may continue without creating spendable production currency.
5. Anonymous users cannot write shared `global_words`, curated `vocabulary`,
   economy collections, or research telemetry.
6. Shared curated word creation is an admin/controlled import operation.
7. User-owned private learning records are scoped to the matching non-anonymous
   UID.
8. Administrative seed scripts require an explicit project allowlist, default
   to dry-run, use Application Default Credentials, and write the canonical
   schema only.

#### Backend transaction contract

```text
purchaseItem(itemId)
  authenticate non-anonymous user
  read canonical item and current balance
  reject missing/disabled/already-owned/insufficient-balance cases
  transactionally debit and grant
  return authoritative balance and ownership version

awardQuizResult(sessionId, signedResult)
  authenticate non-anonymous user
  verify session ownership, expiry, one-time use, and server result
  compute bounded reward on the server
  transactionally append reward and update balance
```

The implementation platform may be Firebase Functions or an existing trusted
backend, but rules must deny equivalent direct client mutation.

#### Acceptance tests

- Firestore emulator denies arbitrary point top-up and `gamesPlayed` mutation.
- Emulator denies anonymous writes to every shared curated collection.
- Emulator permits the minimum intended owner-private learning record.
- Purchase replay, price tampering, UID substitution, and insufficient balance
  all fail.
- Successful purchase is atomic and idempotent.
- Quiz result replay and client-selected reward fail.
- Seed script dry-run performs zero writes and rejects an unapproved project.
- Flutter UI has a truthful unavailable state when trusted economy endpoints
  are absent.

### 5.3 A3 — AI API and Voice API abuse resistance

#### Shared API requirements

1. Production OpenAPI documentation is disabled; development and test may
   enable it explicitly.
2. Authentication occurs before paid or compute-heavy work.
3. Request body size is rejected before full model validation.
4. Rate limiting is keyed by verified principal, not a client-supplied UID.
5. Limiter state is bounded and old keys expire.
6. Upstream timeouts and response-size limits are enforced.
7. Logs include request ID, route, status, latency, and safe capacity metadata,
   but exclude prompts, tokens, raw audio, credentials, and private content.
8. Unit tests use fake providers or engines and require neither network nor GPU.

#### Baseline limits

| Boundary | Default |
|---|---:|
| AI API JSON body | 16 KiB |
| Voice API JSON body | 16 KiB |
| Single vocabulary/query text | 500 Unicode characters |
| Provider response body | 1 MiB |
| Authenticated request rate | 30 requests/minute/principal |
| Voice active generation | 1 per process/GPU |
| Voice waiting capacity | 1 request per process/GPU |

Limits are configuration values with safe production defaults. Raising them is
an operational change, not a code shortcut.

#### Voice-specific behavior

- A nonblocking capacity gate reserves an active or waiting slot before
  expensive work.
- Excess capacity returns a retryable `429` or `503` with `Retry-After`.
- The existing generation lock remains the single-inference safety boundary.
- A request timeout stops waiting and discards a late result; it must not claim
  that a running GPU thread was forcibly cancelled.
- Readiness fails closed on an unsupported Torch/Torchaudio/OmniVoice runtime.

#### Acceptance tests

- Oversized body is rejected without invoking a provider or engine.
- Unauthenticated request consumes no paid/provider capacity.
- Principal rate limit returns `429` and recovers after the configured window.
- Limiter storage remains bounded under many distinct principals.
- Full voice capacity rejects promptly without creating unbounded queued work.
- Provider timeout and oversized response produce stable safe errors.
- Production docs endpoints are unavailable.
- Existing API success and error contracts remain compatible.

### 5.4 A4 — Hugging Face model and publishing integrity

#### Runtime requirements

1. Production model loading requires a full 40-character hexadecimal commit
   revision.
2. `trust_remote_code` is false.
3. SafeTensor artifacts are required where the model class supports them.
4. Revoked revisions are checked.
5. Model generation uses a bounded concurrency gate and a serialization lock.
6. Chat input has count, per-message, and aggregate character limits.
7. Tests mock model loading and generation and never fetch weights.

#### Baseline chat limits

| Boundary | Default |
|---|---:|
| Request body | 64 KiB |
| Messages | 32 |
| Characters per message | 4,000 |
| Aggregate prompt characters | 16,000 |
| Active generation | 1 per process/device |
| Waiting capacity | 2 per process/device |

#### Publishing requirements

1. Upload tools accept an allowlisted artifact set only.
2. Directory-recursive upload is prohibited.
3. Allowed files are safe model weights, adapter configuration, tokenizer
   assets required by the runtime, and reviewed model documentation.
4. Model repositories default to private. Public publication requires an
   explicit `--public` flag and confirmation of the destination repository.
5. Tokens are read from the standard secure environment or authenticated CLI
   cache, never from a command-line `--token` value.
6. The destination repository and pinned source revision are printed for
   review; secrets and local absolute private paths are not printed.

#### Acceptance tests

- Missing, short, branch-name, or nonhex revision fails before model loading.
- Unsafe or unexpected upload files are rejected.
- Default publication is private.
- CLI help exposes no token argument.
- Input and capacity limits reject before generation.
- Safe model-load arguments are asserted in isolated tests.

### 5.5 A5 — Client, CI, Android, and supply-chain hardening

#### Continuous integration

1. CI runs every committed repository contract test, including Android release
   signing and Firestore rules security tests.
2. Official GitHub Actions remain pinned to reviewed full commit SHAs.
3. Global Firebase CLI installation uses `--ignore-scripts`.
4. Flutter analysis, Flutter tests, Android debug build, Python suites,
   security rules tests, secret scanning, and dependency audits are required
   checks.
5. CI must not require production credentials for pull requests.

#### Android identity and permissions

The proposed production Android application ID is
`com.phoomxo.lexiquest`. This value is a release identity decision and requires
owner approval. When approved:

- update Gradle namespace/application ID and Kotlin package paths together;
- use display name `LexiQuest`;
- require a matching owner-provided Firebase Android configuration;
- never fabricate or copy an incompatible `google-services.json`;
- block Firebase-connected release builds until the matching configuration is
  supplied.

The `CAMERA` permission is removed while the Object Scanner remains simulated.
It may return only with a real reviewed camera feature and explicit runtime
permission UX.

#### Import/export safety

1. CSV exports neutralize spreadsheet formulas beginning with `=`, `+`, `-`,
   or `@` while preserving round-trip data through an explicit escaping rule.
2. LaTeX exports escape control characters and user-provided content.
3. Imports have bounded file size, row count, field length, and parse time.
4. Rejected imports produce actionable errors and no partial mutation.

#### Dependency policy

- Direct dependencies with no imports stay removed.
- Compatible transitive upgrades are allowed only when all Flutter and Android
  gates pass.
- Flutter-SDK-constrained packages are documented rather than forced.
- Strict Built-in Kotlin remains deferred while Flutter or required plugins do
  not support it.
- Gradle dependency verification is added only if it is stable in local and CI
  environments and does not require cache modification.

#### Acceptance tests

- Workflow contract tests prove all required suites are invoked.
- Release signing configuration fails safely when required secrets are absent.
- Firestore rule tests execute in CI.
- Android debug APK builds without camera permission.
- Application-ID migration does not begin without owner approval and matching
  Firebase configuration.
- CSV, LaTeX, and import-boundary tests cover malicious and oversized input.
- Dependency and secret scans have no unresolved high-severity result.

### 5.6 A6 — Stabilization exit gate

The same reviewed commit must satisfy all applicable gates:

1. `flutter analyze` reports no issue.
2. The complete Flutter test suite passes.
3. Android debug APK builds successfully.
4. AI API, Voice API, and LexiQuest-LM CPU suites pass in their isolated
   environments.
5. A bounded real OmniVoice GPU inference produces a valid nonempty WAV after
   CPU gates pass.
6. Firestore emulator and Supabase policy contract tests pass.
7. Authentication, API-capacity, HF-integrity, export-safety, CI-contract, and
   signing tests pass.
8. Gitleaks and dependency audits have no unresolved high-severity result.
9. Codex Security findings are validated, fixed or explicitly risk-accepted by
   the owner, and rescanned.
10. Git working tree is clean.
11. Remote divergence is reconciled without lost commits.
12. The pull request has automatic green checks and a concise migration note.

Passing historical test counts are useful evidence but are not fixed
requirements because new regression tests increase those counts.

## 6. Release B — Associative Reading

### 6.1 B1 — Learning-domain foundation

The learning engine is independent of Flutter widgets, Firebase, AI providers,
and voice engines. It uses deterministic domain inputs and outputs.

#### Core records

```text
AssociationRecord
  associationId
  ownerId
  wordKey
  cueType
  cueText
  source
  privacy
  strength
  successCount
  failureCount
  createdAt
  updatedAt
  schemaVersion

RecallAttempt
  attemptId
  sessionId
  wordKey
  recallMode
  cueLevel
  correctness
  responseTimeMs
  confidence
  contextId
  algorithmVersion
  occurredAt

MemoryState
  ownerId
  wordKey
  strength
  cueDependency
  stability
  difficulty
  lapseCount
  lastReviewedAt
  nextDueAt
  lastErrorType
  algorithmVersion

ReadingSession
  sessionId
  ownerId
  cefrLevel
  targetWordKeys
  mixPolicyVersion
  contentId
  contentVersion
  completedStages
  startedAt
  completedAt
  schemaVersion
```

#### Enumerations and constraints

- `cueType`: `personalStory`, `keyword`, `collocation`, `synonym`, `antonym`,
  `sensory`, or `context`.
- `source`: `user`, `curated`, or `aiSuggested`.
- `privacy`: `private` initially; sharing is outside Release B.
- `cueText`: 1–500 Unicode characters after normalization.
- `confidence`: integer 1–5.
- `correctness`: objective graded result plus a stable error classification.
- Times are UTC instants; display timezone is a presentation concern.
- Every persisted record includes a positive schema version.

Learning events are append-only. Derived memory state may be rebuilt from
events for a supported algorithm version.

#### Acceptance tests

- Serialization round-trips every record and enum.
- Invalid lengths, confidence, time, privacy, and version values fail.
- Domain tests are deterministic with a supplied clock and seed.
- Migration tests preserve historical events.
- No domain test imports Firebase, Flutter widgets, AI, or voice packages.

### 6.2 B2 — Associative-memory vertical slice

#### Learner flow

1. After an incorrect, slow, or low-confidence recall, show up to three
   relevant curated association prompts.
2. The learner may select, edit, create, or skip an association.
3. The learner owns the final wording and can delete it.
4. On the next encounter, show the association only after unaided recall fails
   or the session policy explicitly begins with support.
5. Track how often a cue was requested and whether recall succeeded after it.
6. Gradually fade cues as independent recall improves.

#### Source policy

Curated prompts ship first. AI suggestions are enabled only after structured
output validation and must be labeled as suggestions. AI cannot overwrite a
user association. A failed or invalid AI result falls back to curated prompts.

#### Acceptance tests

- Association create, edit, select, skip, and delete work offline.
- Another user cannot read the association.
- A cue is not shown before the configured stage.
- Cue usage updates evidence without awarding correctness by itself.
- AI output cannot bypass length, type, safety, or ownership validation.
- Curated fallback works with AI disabled.

### 6.3 B3 — Mixed-vocabulary reading loop

#### Versioned default mixer

Each session selects target words using:

- 50% due words;
- 30% weak or confusable words;
- 20% new words.

The target is 4–8 words per passage with at most two new words. Empty pools are
redistributed deterministically toward due, then weak, then new words. A
supplied seed resolves ties. The mixer records its policy version and selected
word keys.

#### Passage contract

- CEFR level matches the learner profile or selected research level.
- Passage length is 80–180 words for the initial release.
- Each target word appears naturally one or two times.
- Non-target vocabulary stays within the level budget.
- Content has a stable ID and version.
- Generated content passes structural and vocabulary validation or falls back
  to curated content.

#### Six-stage session

1. **Supported reading:** passage, target highlighting, and optional
   pronunciation support.
2. **Cue fading:** remove translations and progressively reduce highlighting.
3. **Recall:** cloze or free-recall questions without answer leakage.
4. **Association:** select or edit a memory cue after evidence is recorded.
5. **Transfer:** use or recognize the target in a different sentence/context.
6. **Scheduling:** update memory state from correctness, latency, cue use,
   confidence, and transfer evidence.

The UI cannot jump directly to scheduling without recording the preceding
graded stages, except an explicit abandoned-session event.

#### Acceptance tests

- Mixer proportions, pool redistribution, word caps, and seed determinism pass.
- Invalid passage does not reach the learner.
- Every target word occurs within its allowed frequency.
- Stage transitions cannot skip required evidence.
- Failed or abandoned sessions produce valid events without false success.
- The same event sequence produces the same memory state.

### 6.4 B4 — AI and voice enrichment

#### AI contract

AI may propose a passage, distractors, contextual examples, and association
prompts through a versioned structured schema. A deterministic validator checks
CEFR budget, target inclusion, forbidden leakage, length, type, and field
limits. Invalid output is discarded; it is never partially trusted.

#### Voice contract

OmniVoice may provide:

- passage read-aloud;
- target pronunciation;
- shadowing playback;
- bounded speaking feedback when a reliable input path exists.

Native platform TTS may provide a declared practice fallback. Research events
record the actual engine and version. Raw microphone recordings are processed
ephemerally and deleted unless the learner separately consents to retention.

#### Acceptance tests

- Full learning loop remains functional with AI and voice disabled.
- Invalid AI schema uses curated content.
- Voice failure preserves text flow and records a technical failure, not a
  learner error.
- Engine identity and content version are recorded.
- No raw audio is retained under default settings.

### 6.5 B5 — Adaptive scheduling engine

#### Inputs

- objective correctness;
- response time normalized by task type;
- cue level and cue requests;
- confidence;
- transfer-context success;
- lapse history;
- word difficulty and confusability.

#### Outputs

- updated strength/stability and difficulty;
- cue-dependency estimate;
- next due time;
- recommended next task type;
- reason code suitable for debugging and research.

The first production algorithm is deterministic, versioned, and covered by
golden cases. It must not be silently replaced by an opaque ML model. Future ML
ranking may recommend content but requires offline evaluation, fairness checks,
rollback, and an explicit algorithm version.

#### Acceptance tests

- Correct independent recall increases interval more than cued recall.
- Incorrect or slow recall reduces stability within configured bounds.
- Successful novel-context transfer improves evidence more than repeated
  recognition.
- Identical inputs, clock, seed, and version yield identical outputs.
- Extreme values cannot produce negative, infinite, or unbounded intervals.
- Algorithm migration never rewrites historical evidence.

### 6.6 B6 — Research experiment

#### Initial study arms

1. **Control:** existing spaced repetition.
2. **Association:** spaced repetition plus association workflow.
3. **Combined:** spaced repetition plus association and mixed-vocabulary
   reading.

#### Measurement windows

- immediate post-session;
- delayed recall at 1, 7, 14, and 30 days.

#### Primary outcomes

- delayed recall accuracy;
- novel-context transfer accuracy;
- response time;
- cue dependency;
- retention/adherence.

#### Secondary outcomes

- confidence calibration;
- lapse recovery;
- session completion;
- perceived cognitive load;
- technical failure rate.

#### Experiment requirements

- informed consent and withdrawal path;
- stable server-side assignment;
- sample-size and analysis plan fixed before outcome inspection;
- algorithm/content/app version captured per event;
- no raw email, token, prompt, or microphone data in analytical events;
- export uses pseudonymous participant IDs;
- missing data and technical failures remain distinguishable from incorrect
  answers.

## 7. Storage and synchronization strategy

Release B begins local-first for learning continuity. Repositories expose domain
interfaces; Flutter UI does not read Firestore directly.

```text
Learning UI
  -> Application use cases
    -> Learning repositories
      -> Local store (required)
      -> Authenticated sync adapter (optional until enabled)
```

Synchronization requirements:

- append-only attempt/event IDs are client-generated collision-resistant IDs;
- server enforces owner UID and rejects anonymous research sync;
- conflict resolution never overwrites event history;
- derived state selects the newest supported algorithm projection and can be
  rebuilt;
- delete requests cover private associations and consented research data under
  the approved retention policy;
- schema migrations are forward-tested with preserved fixtures.

## 8. Branch and pull-request decomposition

### Release A

Continue stabilization on `feature/production-vertical-slices`. Use reviewable
commits in this order:

1. `test(auth): define verification failure contracts`
2. `fix(auth): fail closed and remove duplicate password flow`
3. `test(firestore): deny client economy and anonymous shared writes`
4. `fix(firestore): enforce trusted economy boundaries`
5. `test(api): define request and capacity limits`
6. `fix(api): enforce bounded authenticated workloads`
7. `test(hf): define model and publishing integrity`
8. `fix(hf): pin model and restrict publishing`
9. `test(client): cover export import and android contracts`
10. `fix(client): harden boundaries and CI coverage`
11. `chore(stabilization): pass complete release gate`

Commit wording may be refined to match actual files, but commit scope and order
remain.

Before pushing, fetch and inspect the remote branch because the local and
remote histories may have diverged. The resulting pull request remains the
existing Release A integration request unless repository state requires a new
owner-approved request.

### Release B

After Release A merges, create `feature/associative-reading-loop` and use
vertical pull requests:

1. domain records and local repositories;
2. associative-memory vertical slice;
3. mixed-vocabulary reading loop;
4. AI and voice adapters with fallbacks;
5. adaptive scheduler;
6. consented research instrumentation.

Each pull request must be independently testable and must not expose an
unfinished feature except behind a default-off flag.

## 9. Explicitly deferred or out of scope

The following are not part of the first two releases:

- training or fine-tuning a new language or speech model;
- a production camera/object-recognition scanner;
- a full vocabulary knowledge graph;
- public sharing of personal associations;
- teacher/classroom dashboards and organization tenancy;
- multiplayer or social competition;
- additional language pairs;
- automatic diagnosis based only on opaque ML;
- public Hugging Face publication without owner approval;
- forced Built-in Kotlin migration before supported upstream versions exist;
- large Flutter package/import renaming unrelated to product behavior.

These items require separate designs and cannot be added by GLM as “helpful”
extras.

## 10. Long-term extension path

After Release B produces reliable evidence:

1. Build a word-relation graph from validated synonym, antonym, morphology,
   collocation, topic, and learner-confusion edges.
2. Use the graph and memory state to select transfer contexts, not to replace
   the deterministic scheduler.
3. Add teacher/research dashboards over pseudonymous aggregated events.
4. Evaluate adaptive ranking offline before controlled online experiments.
5. Add multimodal association only after consent, storage, model, and
   accessibility designs are approved.

Every extension must preserve versioned evidence, offline usability, privacy,
and a non-AI fallback.

## 11. Definition of done

### Release A is done when

- all A1–A6 acceptance criteria pass on the same reviewed commit;
- no unresolved high-severity security or dependency finding remains;
- optional services fail truthfully and safely;
- CI checks run automatically on the pull request;
- remote history is reconciled and the integration pull request is mergeable;
- operator and migration notes identify every required owner-supplied
  credential or Firebase configuration without embedding it.

### Release B is done when

- the learner can complete the six-stage loop offline with curated content;
- association privacy and cue fading are enforced;
- mixer and scheduler are deterministic and versioned;
- AI and voice improve the loop but are not required for it;
- research events distinguish learner performance from technical failure;
- all Flutter, domain, API, security, migration, and end-to-end tests pass;
- experiment behavior matches the consented protocol.

### Program completion is not inferred from token use

Token consumption is telemetry, not an acceptance criterion. The Cointh/GLM
budget may be used at maximum supported reasoning effort for productive,
bounded microtasks, reviews, adversarial test design, and diff refinement. A
task is complete only when its specified evidence passes under Codex control.

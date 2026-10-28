# LexiQuest Long-term Engineering Workflow Profiles Design

## Outcome

LexiQuest has one durable engineering workflow that future Codex Desktop and Codex CLI sessions can apply to feature work, bug fixes, refactors, database migrations, security checks, device validation, releases, and hotfixes without inventing a new process for every task.

The system does not predict future feature requirements. It standardizes how an unknown future task is classified, bounded, implemented, reviewed, verified, resumed, and completed. It prevents conflicting work packages, repeated unchanged tests, mixed-artifact evidence, and AI-generated instructions from bypassing local verification.

The architecture is layered:

1. **Project Runtime Foundation** securely exposes the bounded GPT analyst and AWS Lite independent reviewer across LexiQuest worktrees and new Codex sessions.
2. **Long-term Engineering Workflow Profiles** define deterministic lifecycle, gate, evidence, state, and completion policies for all engineering work.

The foundation must be implemented and accepted first. Workflow profiles depend on its stable health and analysis interfaces but remain usable with native Codex when the external analysis runtime is unavailable, except where a profile explicitly requires an independent review to complete.

## Scope

This design adds an engineering workflow control plane. It does not implement P8-H, P8-E, P8-F, P8-G, a future product feature, a database change, or a release by itself. Those become workflow instances governed by this system.

The system covers:

- new features;
- bug fixes;
- behavior-preserving refactors;
- database and persistent-state migrations;
- bounded security verification;
- physical-device validation;
- signed release and staged rollout;
- urgent production hotfixes.

UI/layout work is a normal feature or refactor workflow after the current system contracts are frozen. Product-specific acceptance criteria stay in the task's approved specification and implementation plan, not in the generic profile definitions.

## Architecture and Ownership

### Layer 1: Project Runtime Foundation

`tool/ai-analysis/` and its machine-local immutable runtime own:

- current-user DPAPI secret handling;
- MaxPlus transport and exact provider/model selection;
- deterministic effort routing;
- bounded source-context projection;
- analyst and reviewer requests;
- sanitized normalized review results;
- timeout, cancellation, one-attempt, no-retry, and no-fallback behavior.

Provider output is untrusted review data. It cannot execute a command, edit a file, change workflow state, waive a gate, or mark work complete.

### Layer 2: Engineering Workflow Profiles

A separate versioned package under `tool/engineering-workflows/` owns:

- profile schema and eight profile definitions;
- task classification and composition rules;
- lifecycle transition validation;
- work-package and shared-integration-area ownership;
- gate-key computation and unchanged-gate reuse;
- machine-local workflow state and append-only event ledger;
- sanitized evidence report projection;
- Desktop and CLI discovery documentation.

This package does not store or proxy inference keys and does not duplicate the AI transport. It calls the Project Runtime Foundation only through its stable launcher.

### Repository and Machine-local Data

Versioned repository data contains profile definitions, schema validation, adapters, tests, and documentation. Active task state is machine-local under:

`%LOCALAPPDATA%\LexiQuest\engineering-workflows\<project-id>\<workflow-id>\`

Each workflow has:

- `state.json`: the latest atomic snapshot;
- `ledger.ndjson`: append-only sanitized transition and gate events;
- `evidence-index.json`: hashes and references to evidence, never secret contents.

Human-readable reports may be projected to `build/engineering-workflows/<workflow-id>/`. The build directory is evidence output, not authoritative state and not a cross-device secret store.

Machine-local state is bound to the resolved LexiQuest Git common directory. Another repository cannot resume or update it. A workflow also records its current worktree, branch, base commit, and approved scope so a new chat can detect drift before continuing.

## Roles and Execution Model

Codex is the only inline implementer. It edits files, runs local commands, evaluates results, and owns the final technical decision.

The GPT Pro 20x Stable model is a bounded analyst. The AWS Lite Ultimate model is an independent read-only reviewer at profile checkpoints. Effort is selected by deterministic task risk: Low or Medium for routine bounded work, High through Max for cross-package, concurrency, migration, privacy, authentication, and release risk, and Ultra only for critical adjudication.

Analyst and reviewer calls are sequential. They never run concurrently with implementation, repository-wide analysis, or security verification. A reviewer receives only the approved bounded scope and normalized evidence. Its findings must be verified against local code or test output before action.

If the analysis runtime is unhealthy, the workflow records `externalReviewUnavailable` and Codex continues only through gates that permit native analysis. A required independent review remains pending; it is never silently waived or replaced by a lower-effort/provider fallback.

## Shared Lifecycle

Every workflow follows the same state machine:

`Intake -> Baseline -> Implement -> Focused Gate -> Review -> Integration Gate -> Evidence -> Complete`

`Blocked` is a terminal alternative when the task cannot make meaningful progress under the existing scope and authority.

### Intake

Record the task identifier, short non-secret summary, primary profile, required secondary profiles, approved scope, exclusions, risk level, worktree, branch, and starting commit. Confirm that the task is authorized and that any destructive or external action has explicit authority.

### Baseline

Capture the relevant existing behavior before editing. Depending on the profile, this is an approved feature specification, a reproducible bug, passing equivalence tests, legacy database fixtures, an immutable APK hash, or a release candidate record.

Baseline also assigns work-package ownership. Runtime bootstrap, dependency manifests, database schema, navigation, signing/release configuration, and other declared shared integration areas may have only one active owner. A second workflow touching the same area must wait or be explicitly combined with the first.

### Implement

Codex works inline from the approved specification and implementation plan. Changes remain inside the declared scope. An unplanned scope expansion returns to Intake for reclassification, profile composition, and approval before continuing.

### Focused Gate

Run the smallest deterministic verification that proves the changed behavior. A feature or bug fix starts with a failing behavioral test. A refactor starts from a passing behavior baseline. A migration uses explicit fresh and legacy fixtures. A device or release workflow uses a single immutable artifact hash.

### Review

Perform focused local diff review and the profile's independent read-only checkpoint. Findings are classified P0-P3. P0-P2 findings require resolution or an explicit blocker; P3 may be recorded for later work when it does not violate completion criteria.

### Integration Gate

After focused verification passes, run the package and cross-package gates required by the composed profile. Full suites and builds run only when source, dependency lock, schema, configuration, or artifact inputs relevant to them changed.

### Evidence

Project a sanitized record containing commit SHA, dependency-lock hash, artifact hash when relevant, gate identifiers, command signatures, results, UTC timestamps, and reviewer disposition. Owner-only, physical-device, signing, and rollout results are explicitly distinguished from automated results.

### Complete or Blocked

Complete requires every primary and secondary profile criterion to be satisfied with consistent evidence. Blocked requires the exact unresolved condition and the missing user authority, credential, device, artifact, or external state. Partial evidence cannot be reported as complete.

## Profile Model and Composition

Every workflow has exactly one primary profile. It may add one or more secondary profiles when the task crosses a risk boundary. For example, a feature that changes Drift schema uses `feature` as primary and `migration` as secondary. A production fix that changes authentication and needs an urgent build uses `hotfix` as primary with `security` and `release` requirements.

Composition takes the union of required gates, evidence, reviewers, and completion criteria. When policies conflict, the stricter requirement wins. A profile can never remove a gate required by another profile. Composition cycles, duplicate gate identifiers with different semantics, and unknown profiles are rejected before Baseline.

Each versioned profile definition contains data only:

- `schemaVersion` and stable `profileId`;
- purpose and allowed work classification;
- risk floor and escalation rules;
- required Intake and Baseline artifacts;
- focused, review, integration, and evidence gate identifiers;
- invalidation inputs for each gate;
- independent-review requirements;
- completion and blocker criteria.

Profile files never contain shell commands, code snippets, provider prompts, secrets, or executable expressions. Gate identifiers resolve through a reviewed adapter registry implemented in code. This prevents a modified profile file from becoming arbitrary command execution.

## The Eight Profiles

### 1. Feature

Use for new or materially changed product behavior.

Required flow:

- approved product/technical specification and implementation plan;
- explicit acceptance criteria and exclusions;
- failing behavior test before implementation where automation is feasible;
- focused package tests, affected integration tests, and regression checks;
- independent review at the package or integration checkpoint based on risk;
- user-facing, privacy, analytics, and migration impacts composed as secondary profiles when present.

Completion requires all specified behavior and composed gates to pass. “Code exists” is not completion.

### 2. Bugfix

Use when existing behavior is incorrect.

Required flow:

- minimal deterministic reproduction;
- root-cause statement supported by local evidence;
- failing regression test before the fix where automation is feasible;
- minimal scoped correction;
- regression test plus the smallest affected integration gate;
- confirmation that symptoms are not merely hidden or retried.

If the same normalized failure recurs three times, implementation stops and the workflow returns to architecture/root-cause review.

### 3. Refactor

Use for internal structural change intended to preserve behavior.

Required flow:

- passing pre-change behavior baseline;
- declared contracts that must remain stable;
- small reversible work packages;
- equivalence tests before and after each package;
- API/schema/output diff review;
- no opportunistic feature behavior or unrelated cleanup.

Any intended behavior change converts the work to a feature or bugfix composition before continuing.

### 4. Migration

Use for database schema, persistent preferences, secure-storage layout, file format, protocol, or durable state changes.

Required flow:

- source and destination schema/version contract;
- new-install and representative legacy fixtures;
- forward migration and idempotency tests;
- compatibility, rollback, or explicit irreversible-transition policy;
- data preservation and failure recovery checks;
- real upgrade-install validation when the migration affects shipped mobile state.

Data loss, silent default substitution, partial migration, or evidence from mismatched artifacts is a blocker.

### 5. Security

Use as a primary profile for security-only remediation or as a secondary profile for authentication, authorization, secrets, privacy, untrusted endpoints, policy, or dependency risk.

Required flow is bounded to the changed scope:

- threat boundary and protected assets;
- abuse/error cases and focused policy tests;
- Gitleaks, OSV Scanner, dependency audit, or manual diff review as relevant;
- validation that secrets and sensitive content do not enter logs, reports, arguments, environment variables, exports, or versioned state;
- independent review of the exact security-sensitive diff.

Codex Security, Security Scan, Deep Scan, repository-wide security workers, and historical references to those systems are excluded by repository guardrails.

### 6. Device

Use for real-device behavior, permissions, audio, lifecycle, performance, compatibility, App Check, account conversion, upgrade install, or device-matrix evidence.

Required flow:

- immutable signed or explicitly identified debug artifact hash;
- device tier, OS/API level, app version, journey set, network condition, and UTC time;
- sanitized device alias rather than a hardware serial or account identity;
- pass/fail evidence for every required journey;
- crash, ANR, data-loss, cancellation, persistence, and permission observations;
- owner attribution without storing credentials.

Evidence from different APK/app-bundle hashes cannot be combined into one matrix. A source change creates a new artifact and invalidates affected device gates; every device receives at least the defined cross-device smoke again.

### 7. Release

Use for release-candidate creation, signing, final acceptance, rollout, monitoring, rollback, and release closure.

Required flow:

- immutable source commit and signed artifact hash;
- signing-certificate compatibility and upgrade path;
- all upstream feature/migration/security/device gates complete for that artifact;
- owner smoke and approval;
- staged rollout evidence with version, commit, artifact, UTC time, metrics, and approver;
- explicit stop and rollback conditions.

No release is complete with partial device evidence, mixed hashes, missing signing authority, secret leakage, data loss, migration failure, or unreviewed critical findings.

### 8. Hotfix

Use for an urgent production correction where normal release lead time is unacceptable. Urgency narrows scope but does not waive safety gates.

Required flow:

- confirmed production impact and rollback decision;
- smallest viable diff with a failing regression test;
- focused security/migration composition when affected;
- expedited independent review;
- impacted package integration plus minimum real-device smoke;
- signed artifact, rollout/rollback evidence, and merge-back to the canonical development line.

Unrelated cleanup, feature additions, broad refactors, and silent schema changes are prohibited in a hotfix.

## Gate Ledger and Test-loop Prevention

Every gate execution has a deterministic key derived from:

- profile-set hash;
- gate identifier and adapter version;
- relevant source commit or scoped diff hash;
- dependency-lock hash;
- schema/configuration hash when relevant;
- artifact hash when relevant;
- normalized command signature and test selection;
- environment class for device or owner-run gates.

A prior PASS may be reused only when the complete key matches and the profile does not require a new time-bound owner/device/rollout observation. A changed relevant input invalidates only dependent gates. A full suite is not rerun merely because a chat restarted or a report was regenerated.

On failure:

1. Stop at the first failing gate.
2. Classify it as code, test, environment, credential, device, artifact, or external service.
3. Change the relevant input or record the blocker.
4. Rerun only the failed focused gate.
5. Rerun broader dependent gates only after the focused gate passes.

There is no automatic retry. A repeated-failure fingerprint contains the gate identifier, failure category, normalized non-secret error signature, and the locally confirmed root-cause identifier. Three recurrences of that fingerprint force architecture review before another implementation attempt, even if an attempted fix changed the commit.

## State, Resume, and Cross-chat Behavior

State changes use a machine-local write-ahead transaction record containing the previous-state hash, proposed-state hash, and sanitized event hash. The engine writes and flushes the proposed snapshot, validates it, appends and flushes the ledger event, atomically replaces `state.json`, and then removes the transaction record. On startup, an incomplete transaction is resolved by comparing those hashes: an unapplied proposal is discarded, an appended event with a missing state replacement is completed, and any inconsistent combination fails with `stateIntegrityFailure`. Recovery never invents or silently resets workflow state.

A new Codex Desktop or CLI session performs local-only workflow discovery:

1. resolve LexiQuest project binding;
2. list active workflows for the current branch/worktree;
3. show profile, lifecycle state, last successful gate, invalidated gates, and blocker category;
4. compare current commit, dependency lock, schema/configuration, and artifact inputs;
5. require explicit continuation of the matching workflow before mutation.

Starting a new chat never repeats provider smoke, effort certification, tests, builds, or device journeys when their gate keys remain valid. It never resumes an implementation command automatically.

## Privacy and Evidence Boundaries

Workflow state and projected reports must not contain:

- API keys, DPAPI plaintext, authorization headers, cookies, or signing passwords;
- full provider prompts or responses;
- source file contents or patches;
- chat transcripts;
- email, account ID, device serial, advertising identifier, or private research reference content;
- microphone transcript, AI tutor prompt/reply, or user learning content.

They may contain stable local workflow IDs, profile IDs, sanitized task labels, repository-relative paths, hashes, command signatures, normalized test summaries, device tier and alias, provider/model metadata, latency/token/cost metadata supplied by the analysis foundation, and reviewer finding dispositions.

Raw device screenshots, logs, signed artifacts, private references, and rollout dashboards stay in their owner-approved stores. The workflow ledger records only a hash and sanitized reference.

## Failure Taxonomy

The workflow layer uses stable categories:

- `workflowNotFound`;
- `projectMismatch`;
- `profileInvalid`;
- `profileCompositionConflict`;
- `scopeDrift`;
- `sharedAreaConflict`;
- `baselineMissing`;
- `gateFailed`;
- `gateEvidenceStale`;
- `artifactMismatch`;
- `externalReviewUnavailable`;
- `ownerEvidenceMissing`;
- `credentialRequired`;
- `deviceRequired`;
- `stateIntegrityFailure`;
- `stateWriteInterrupted`;
- `blocked`.

Failures do not trigger automatic retry, profile downgrade, gate waiver, provider fallback, state deletion, branch merge, or evidence substitution.

## Extensibility for Unknown Future Work

The eight profiles are the stable initial vocabulary. A future work type should first be represented by the closest primary profile plus secondary profiles. A ninth profile is added only when it introduces a genuinely different lifecycle or evidence contract.

Adding or changing a profile requires:

- a schema-version-compatible definition;
- validator tests and composition tests;
- explicit gate-adapter mapping;
- migration behavior for active workflows;
- documentation of new invalidation and completion rules;
- an independent review of the workflow-system change itself.

Unknown schema versions, profile IDs, gate IDs, or adapter versions fail closed. Existing completed workflow evidence remains readable under its original profile and adapter versions.

## Verification and Acceptance

The workflow-profile implementation is accepted only when focused tests prove:

- all eight profiles validate and unknown or executable profile data is rejected;
- composite profiles union gates and the stricter policy wins;
- shared integration areas cannot have two active owners;
- invalid lifecycle transitions and scope drift are rejected;
- gate keys change only for relevant source/dependency/schema/artifact/environment inputs;
- unchanged passing gates survive a new process, worktree session, Codex Desktop chat, and Codex CLI session;
- failed gates are not automatically retried and three repeated root-cause failures require architecture review;
- state writes are atomic and interrupted/corrupt state is detected without silent reset;
- workflow commands invoked from another repository reject the project binding before disclosing or mutating LexiQuest workflow state;
- reports and ledgers pass focused secret/privacy assertions;
- external reviewer output cannot execute actions or change completion state;
- mixed artifact hashes cannot satisfy device or release completion;
- each profile has at least one end-to-end fixture from Intake to Complete and one valid Blocked fixture;
- bounded tool tests, documentation tests, `git diff --check`, focused Gitleaks, and manual diff review pass.

After the generic engine passes, the current P8-H and P8-E/P8-F/P8-G work is enrolled as real workflow instances. Their product-specific gates remain defined by their approved plans and evidence requirements.

## Definition of Done

This workflow-system project is complete when:

- the Project Runtime Foundation is installed and accepted for Desktop and CLI discovery;
- the workflow engine and all eight versioned profiles pass their acceptance tests;
- AGENTS and operator documentation make new sessions discover and resume workflows safely;
- state, ledger, profile composition, gate reuse, and shared-area ownership work across registered LexiQuest worktrees;
- external analyst/reviewer findings remain bounded, read-only, and locally verified;
- no secret, prompt, response, private user content, or device/account identifier appears in workflow state or reports;
- one real current-system workflow demonstrates controlled resume, focused gates, independent review, integration evidence, and correct Complete or Blocked status.

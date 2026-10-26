# LexiQuest Agentic Development Life Cycle (ADLC)

Updated: 2026-10-18
Status: Active process for this checkout
Owner: LexiQuest engineering

## Purpose

ADLC replaces a document-heavy, phase-by-phase SDLC with a controlled execution loop for a human and coding agents. It keeps the existing LexiQuest safety, research, testing, and release rules. The change is operational: each task moves from intent to grounded context, bounded implementation, independent evidence, and feedback without waiting for a large phase handoff.

The core loop is:

`Intent → Ground → Plan → Execute → Review → Attest → Integrate → Learn`

No stage may infer production approval, research enrollment, deployment, publication, or permission to alter live data.

## Source patterns adopted

| Source | Pattern used in LexiQuest | Decision |
| --- | --- | --- |
| [Chainloop](https://github.com/chainloop-dev/chainloop/tree/aecbf71fadbfbd2a6be09683d16fbc99fc387c8d) | Contract-first evidence, signed provenance as a future option, report-only policy rollout before blocking gates | Adopt the evidence model now. Defer installation and cloud/self-host setup until a separate infrastructure decision. |
| [RepoBrain](https://github.com/study8677/repobrain/tree/064e6a1ee1a3364dbc34389c95bea5d8087f31e6) | Repository knowledge grouped by module, source-grounded answers, staged knowledge refresh | Adopt the grounding protocol now. Defer `rb-refresh` because it requires a clean committed worktree and incurs model/runtime cost. |
| [Autonomous Company](https://github.com/MaxMiksa/Autonomous-Company/tree/e0646ae4d007b307beaa8a0941e471adcf0d821e) | Durable consensus/checkpoints, bounded cycles, circuit breakers, visible recovery | Adopt checkpoints and bounded recovery. Do not run a continuous daemon or broad permission mode for this repository. |
| [Kander](https://github.com/dualface/kander/tree/a43059de49b4067b9bdfe7ac4efc44d224189c00) | Task cards, isolated worktrees, conflict-aware scheduling, independent review gates | Adopt task boundaries and review gates. Use parallel agents only when the user authorizes them and files/build outputs do not overlap. |

These repositories are references, not runtime dependencies. Their licenses and operational assumptions remain separate from LexiQuest.

## Lifecycle stages

### 0. Intent contract

**Input:** latest user request, approved product requirements, active plan, current branch/worktree.
**Work:** state the user-visible outcome, in-scope systems, exclusions, risk boundaries, and acceptance checks. Resolve only decisions that materially change data handling, cost, deployment, destructive actions, or product scope.
**Exit evidence:** a task card or plan section with:

- outcome and acceptance criteria;
- owner and affected modules;
- data/research/permission classification;
- expected files and checks;
- explicit release-only dependencies.

### 1. Grounded repository context

**Input:** intent contract.
**Work:** read the active plan, latest checkpoint, `AGENTS.md`, actual implementation, tests, schema ledger, and module boundaries. Use `rg --files` and focused reads. Record source paths for architecture conclusions.
**Exit evidence:** a small impact map listing source-of-truth files, call/data paths, constraints, and known dirty files.

Rules:

- Prefer current code over historical summaries.
- Never infer an API, schema, authority, or feature count from memory.
- Refresh only affected knowledge after committed changes; do not regenerate the whole repository by default.

### 2. Task graph and conflict forecast

**Input:** grounded impact map.
**Work:** split work into cards that each produce a reviewable result. Mark dependencies and write sets before parallel execution.
**Exit evidence:** ordered cards with `Ready`, `Running`, `Review`, `Blocked`, or `Done` state.

Each card must declare:

```text
ID / outcome
Scope and exclusions
Read set / write set
Acceptance checks
Risk and authority boundary
Required predecessor
Final evidence
```

Parallel execution is allowed only when authorized and when write sets, mutable build outputs, fixtures, and generators do not overlap. One writer owns each shared file.

### 3. Bounded implementation loop

**Input:** one ready card.
**Work:** run the smallest useful reproduction, implement the smallest complete change, and run the focused check. A failure feeds evidence into the next attempt.
**Exit evidence:** diff plus focused test/result.

Loop:

1. Observe the current state.
2. Form one falsifiable hypothesis or implementation step.
3. Change only the declared scope.
4. Run the smallest check that can disprove the step.
5. Reconcile the result and continue, recover, or stop the affected path under `AGENTS.md`.

Do not create artificial discussion-only cycles. Once scope is approved and evidence is sufficient, implement.

### 4. Review gate

**Input:** completed card and focused evidence.
**Work:** review behavior against acceptance criteria, then inspect safety, state transitions, data boundaries, accessibility, and unnecessary complexity. Review must read connected code, not only the diff.
**Exit evidence:** findings disposition:

- `must-fix`: correctness, data, authority, security, accessibility, or release-blocking issue;
- `follow-up`: useful improvement outside the card;
- `accepted`: verified with evidence;
- `not verified`: external or device evidence still missing.

For high-risk or cross-module changes, use an independent reviewer when user-authorized agent capacity is available. The implementer still integrates and verifies every returned change.

### 5. Evidence and policy gate

**Input:** reviewed source state.
**Work:** produce a deterministic evidence manifest for the change. Start new policies in report-only mode; promote a rule to blocking only after it has stable fixtures and no unexplained false positives.
**Exit evidence:** a checkpoint or release evidence record containing:

```json
{
  "intent": "task or approved plan reference",
  "source": {"branch": "...", "commit_or_dirty_state": "..."},
  "changes": ["paths"],
  "checks": [{"command": "...", "result": "pass|fail|not-run", "reason": "..."}],
  "review": [{"status": "accepted|must-fix|follow-up|not-verified", "note": "..."}],
  "release_dependencies": ["..."],
  "data_classification": "synthetic|local|production-disabled"
}
```

The manifest may later be mapped to Chainloop/in-toto attestations. Until that infrastructure is approved, repository checkpoints and CI artifacts remain the authority.

### 6. Integration and release decision

**Input:** accepted review and evidence manifest.
**Work:** run required subsystem and integration checks on a consistent source snapshot. Reconcile schema, export/deletion, sync/policy, localization, and feature catalog coverage when applicable.
**Exit evidence:** one of:

- `engineering-complete`: implementation and required local checks pass;
- `release-ready`: release checks pass and external prerequisites are present;
- `blocked`: the repeated blocking threshold in `AGENTS.md` is met;
- `paused`: explicitly requested by the user.

Engineering completion does not authorize deployment, public release, real participant enrollment, or research upload.

### 7. Learn and refresh context

**Input:** integrated outcome or material failure.
**Work:** update only durable knowledge: architecture decisions, module map, test commands, recurrent failure cause, or new guardrail. Remove stale statements when evidence disproves them.
**Exit evidence:** a concise checkpoint that lets the next session resume without reconstructing the task.

## Gate matrix

| Change type | Minimum gates |
| --- | --- |
| Documentation/design only | Intent → Ground → Execute → focused visual/diff review → checkpoint |
| Isolated UI behavior | Intent → Ground → focused test → implementation → accessibility/layout review → touched tests |
| Learning or reward authority | Domain tests → repository tests → review of evidence projection and idempotency → integration gate |
| Owner-scoped data/schema | Migration → repository/policy tests → export/deletion coverage → owner isolation review |
| Research collection/upload | Synthetic/emulator tests → signature/consent/withdrawal gates → before/after linkage → production remains disabled |
| Release/deployment | Full required verification → evidence manifest → explicit release/deployment authorization |

## Task board policy

The repository does not require a new orchestration service to use ADLC. Existing plans and checkpoints are the task board until a Kander pilot is explicitly approved.

- A plan item becomes a card when it has a concrete acceptance check.
- `Done` means the stated evidence exists on the current source snapshot.
- A failed check returns the card to `Running`; it does not create a new duplicate card.
- A dependency or permission gap sets `Blocked` only under the threshold defined in `AGENTS.md`.
- Cards involving the same Flutter build, generated output, schema, or fixture run serially.

## Adoption plan

1. **Now:** use this ADLC for new work; store task cards in plans and evidence in checkpoints.
2. **After the dirty worktree is reconciled:** evaluate RepoBrain in a throwaway or isolated worktree and compare answer accuracy, refresh cost, and maintenance burden.
3. **After CI ownership is decided:** pilot Chainloop-style contracts in report-only mode with existing test, dependency, and release artifacts. No cloud upload by default.
4. **When parallel backlog justifies it:** pilot Kander on disjoint cards; verify worktree isolation and two-stage review before adopting it as the task board.
5. **Do not adopt:** unattended continuous daemons or bypass-permission modes for LexiQuest without a separate explicit operational decision.

## Success measures

- Every completed card links intent, diff, checks, and remaining dependencies.
- Agents spend less time rediscovering module ownership and more time running focused checks.
- Parallel work introduces no overlapping writes or shared build-cache races.
- Review catches semantic/state errors before integration, and findings have explicit disposition.
- Release claims distinguish local engineering evidence from external device, authority, and research evidence.

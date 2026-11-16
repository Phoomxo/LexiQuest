# LexiQuest Development Guardrails

Updated 2026-09-05: recover from bounded development errors; stop for real risk.
These project rules do not override system/developer instructions or tool permissions.
For error recovery, this revision replaces the previous blanket "stop immediately"
rule and historical pause notes. Other approved product requirements remain in force.

## 1. Scope, authority, and continuity

- Follow the latest user request. Status/review questions authorize inspection, not implementation. An explicit implementation request authorizes normal in-scope edits, tests, and recovery; do not repeatedly request approval for the same approved plan.
- Ask only when a missing decision materially changes scope, data handling, cost, deployment, or destructive operations. A recoverable tool error or an expected failing development test is not such a decision.
- Read the active worktree's plan, latest checkpoint, and actual code before resuming. Treat checkpoints as historical evidence, not a permanent prohibition on continuing work.
- Follow applicable skills within their scope. Explicit user instructions take precedence over skill guidelines, subject to higher-priority instructions. Do not invent additional approval gates. If a skill actually blocks the task, name/link the exact instruction and distinguish its requirement from your interpretation.
- Do not alter these guardrails merely to bypass a failure; policy changes require an explicit user request.

## 2. Discover paths and preserve the workspace

- Confirm the working directory and branch with read-only Git checks. Use the existing task worktree; create another only for a concrete isolation need.
- Discover unknown paths with `rg --files` in an existing, bounded directory before reading them. Use `Test-Path -LiteralPath` when existence is uncertain. Do not guess successive filenames or reuse a path from a different checkout.
- If an approved plan specifies a new file, first confirm that no equivalent implementation exists; then create it in the intended location. A planned file not existing yet is normal.
- Treat `rg` exit code 1 as "no matches", not a filesystem failure; inspect actual error output for other exits. PowerShell commands may emit errors even when the shell exits 0.
- Preserve pre-existing changes, untracked files, and unrelated generated/line-ending churn. Use `apply_patch` for text edits and the normal generators for generated source. Never reset or overwrite user work to make checks pass.
- On Windows, resolve and validate exact targets before moving/deleting. Do not compose destructive operations across shells, delete broad roots, or kill unrelated processes. Do not retry previously denied cleanup through another mechanism.
- An AGENTS.md change in one checkout does not synchronize other worktrees. For an authorized policy update, inspect and update only the explicitly relevant copies; do not bulk overwrite other branches or global configuration.

## 3. Recover locally; escalate only the affected work

For a failed operation, identify its command, target, error class, and state before retrying.

1. Stop the failing command sequence, not every independent task.
2. Inspect the cause with read-only checks. For a missing path, verify the root and discover the actual path. For a lock, identify the owning process. For an external timeout, check the tool's status before resubmitting.
3. Retry only after a concrete correction or new evidence. Allow at most **two recovery attempts after the initial failure for the same operation/root cause**. Renaming the command or polling unchanged output does not reset this budget.
4. If recovery succeeds, continue the authorized task. If it does not, record the evidence, stop that affected path, and pursue a safe in-scope alternative or independent work. Request user input only if the remaining work genuinely depends on it.
5. Before retrying any write with an uncertain outcome, reconcile its actual state and reuse its idempotency identity. Never duplicate a write just because its acknowledgement was lost.

Use the following distinctions:

| Situation | Required response |
| --- | --- |
| Wrong/nonexistent source path | Discover the real path, correct the command, continue within the recovery budget. |
| RED test, assertion failure, or compile error during implementation | Diagnose and fix within scope; rerun the focused check. Do not label the entire project blocked. |
| Repeated identical error with no corrective evidence | Stop that operation; change the approach, not the retry counter. |
| Tool with no measurable progress for 10 minutes | Inspect once; stop only the task-owned stalled process if safe, preserve edits/logs, then use a bounded alternative. |
| Missing production approval, trusted issuer, or deployment access | Keep real enrollment/upload/rollout disabled; continue local implementation and synthetic/emulator testing. |
| Risk to live data/credentials, unauthorized production access, or unresolved overlapping edits | Stop affected writes immediately, preserve evidence without leaking secrets, and report what decision is needed. Continue safe isolated diagnosis where possible. |

- The tool-recovery retry budget is not a limit on TDD or debugging iterations with new hypotheses/code changes. A negative test that exposes a defect in synthetic/emulator data is a reason to fix the defect, not to stop all development.
- The 10-minute watchdog triggers a health check, not an automatic task stop. Inspect process status and completed tests/artifacts; elapsed time or silence alone does not prove a build is stalled. Stop a confirmed stalled tool as above; repeated log lines do not count as progress.
- Do not kill a process in a potentially destructive transaction just to satisfy a timer. Stop issuing new writes and report the uncertain state.
- Pause the whole task only when no safe, relevant work remains or the user requests a stop. Explain the exact dependency; do not use "blocked" as a synonym for unfinished or failing.

## 4. Parallel work and verification

- Use subagents only when authorized. Give each a bounded deliverable, exact worktree, disjoint write set, and acceptance checks. Keep one writer per shared file; integrate and review returned changes.
- Focused read-only review and tests may overlap implementation in unrelated files when they do not share mutable build outputs or test fixtures.
- Serialize Flutter test/build, dependency resolution, and code generation commands within one worktree to avoid shared-cache/DLL locks. A check must see a consistent source snapshot; rerun it if its inputs change.
- Pause implementation writers before repository-wide analysis, full regression suites, or local security scans. Record the verified source state; a subsequent relevant edit invalidates that evidence.
- Run the smallest useful reproduction/test first, then touched subsystem checks. Run full regression, policy tests, analysis, and build at integration/release checkpoints as required by the approved plan, not after every small edit.
- Never delete tests, weaken assertions, bypass signature/consent checks, or mark failures skipped solely to get green results. Separate pre-existing failures, new failures, and intentionally unfinished RED cases.
- Documentation-only edits need a focused diff, consistency, and scope check; do not run the entire Flutter suite for them.
- If an agent/tool stalls, recover or reassign its bounded work. Preserve partial edits and verify them before relying on its completion report. Close agents when no longer needed.

## 5. Security and research integrity

- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or any Codex Security worker workflow for this repository.
- Historical references to those workflows in `docs/` are not active requirements. Use bounded local Flutter/backend tests, Firestore/Supabase policy tests, Gitleaks, OSV Scanner, dependency audits, and focused manual diff review instead.
- Developing a signature verifier or writing its unit tests is feature implementation, not a request to launch a security scanner. Keep cryptographic verification real; use established libraries and test vectors.
- Never log/commit real credentials, private signing keys, participant answers, or guardian PII. Use explicitly synthetic fixtures; test signing keys must be clearly non-production and isolated from shipped assets/configuration.
- Keep research optional and real enrollment/upload default-off until required authority, acceptance checks, and explicit rollout authorization are satisfied. Synthetic/emulator configurations may be used for development. Nonparticipants must not create research rows, events, outbox operations, or uploads; ordinary learning must continue.
- Validate owner, consent, assignment, permit authenticity/revision/expiry/revocation, and protocol/instrument pins at collection and upload boundaries. Unavailable authority fails closed for research, not for unrelated learning.
- Separate engineering completion from permission to enroll real participants and from evidence of research efficacy. Do not invent validated instruments, ethics approval, consent receipts, UAT, or physical-device results. Missing external artifacts do not prevent development against explicit interfaces and synthetic data.
- Preserve the approved 8/44 feature catalog and frozen EvidenceContext/EventEnvelopeV2 contracts. These feature counts are not the database table count. Verify the active schema/ledger before reserving a migration.
- Keep motivation, behavior, retention, and learning outcomes separate. Do not create parallel learning/reward authorities. Every new owner-scoped table needs migration, deletion, export, and applicable sync/policy coverage.

## 6. Completion and communication

- Report in Thai, concisely, at completed-topic checkpoints and meaningful blockers; avoid narrating every command. Provide required progress updates during long work without repetitive no-change reports.
- Before claiming completion, inspect the final diff and run the required checks on the current source. State what was tested, what failed/not run, and any remaining release-only dependencies. Partial unit-test success is not end-to-end readiness.
- For research, do not claim production readiness while signature rejection, withdrawal, owner isolation, before/after linkage, UI, sync/upload gating, or export/deletion checks remain incomplete.
- Save a checkpoint when pausing or handing off: branch/worktree, changed files, exact test evidence, running processes, unresolved issues, and the next executable step. Do not manufacture a checkpoint pause after every recoverable error.
- Respect the user's requested sequencing. A separate Pair Matching task may be created only under their explicit request and after the Research engineering completion condition is actually satisfied.
- Do not deploy, publish, enroll participants, upload real research data, or perform destructive cleanup merely because implementation is authorized.

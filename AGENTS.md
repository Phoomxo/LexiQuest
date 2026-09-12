# LexiQuest working instructions

## Scope and safety
- Follow the latest user request. Approved implementation includes local edits,
  tests and bounded recovery; do not restart approval loops. Work on one major
  package at a time, in the existing task worktree, without background workers
  or subagents unless explicitly authorized.
- Preserve user changes and other worktrees. Never bulk stage, reset, clean,
  overwrite or kill unrelated processes. Discover paths before reading them.
  Use apply_patch for text edits and normal generators for generated files.
- No Codex Security, Security Scan, Deep Scan or worker workflow.
- Keep approved 8/44 and frozen EvidenceContext/EventEnvelopeV2 compatibility,
  canonical learning/reward authorities, historical truth and owner isolation.
  New owner storage requires migration, export/delete and applicable sync/policy.
- Research is optional; real enrollment/upload stays off. Nonparticipants create
  no research records/outbox/uploads. Research gates fail closed without blocking
  ordinary learning. Never expose credentials/PII or weaken consent/signature checks.
- No purchase, paid service, deployment, push, merge, real-data upload or
  destructive cleanup without applicable user authorization. Use explicit device
  serials; preserve app identity and data on authorized device tests.

## Execution and verification
- Read the active checkpoint, then only the current package requirements.
  Use regression-first changes and the smallest useful reproduction.
- Diagnose errors before retrying. At most two recovery attempts for one cause,
  with concrete corrective evidence. Repeated unchanged failures stop that
  operation; report and continue safe relevant work. After ten minutes without
  measurable progress, inspect the task-owned process; do not kill blindly.
- Serialize Flutter test/build/dependency/codegen operations in this worktree.
  Never run full Flutter/backend/Android/GPU gates concurrently.
- Use tool/cli/verify-scope.ps1 for bounded checks. Do not rerun a passed gate
  with unchanged relevant inputs. Full release verification requires a frozen
  PR/release SHA. No source writers during integration checks.
- Do not remove tests or weaken assertions to pass. Review current diff and
  actual results before claims/commits. Local checks do not prove human,
  physical, live-service, release or research acceptance.
- Report concisely in Thai. Maintain a short active checkpoint with source,
  results, unresolved work, process status and the next step.

## Context budget
- Keep full specs and logs on disk. Do not preload all packages or reread known
  documents. Search with rg, then read bounded relevant ranges.
- Default tool output budget: 1200 tokens; up to 3000 for a necessary source
  excerpt. Split a truncated read by headings; do not repeat the same broad read.
- Test output goes to per-command/source logs. Return exit status, count, log
  path and the first relevant failure; inspect a stack trace only when needed.
- Reuse observed paths and verified results. Poll only for a meaningful state
  change; do not dump repeated progress lines or full inventories.
- The active checkpoint is current state only, not an appended transcript.
  Preserve completed investigations in referenced history files.
- Extra plugins/skills, model settings and global instructions are not changed
  merely to reduce this task's context. Compaction is not a reason to stop work.
- Continue approved packages without asking the user to restart routine work.
  Keep a coupled debugging cycle in one task. At an accepted package boundary,
  use a fresh task with a compact handoff when accumulated context warrants it;
  do not fork full history or create a new task for every command. Never overlap
  source writers. Verify committed source or explicitly account for pending edits
  before a handoff; do not recreate completed work or import another worktree.
- Use the lightweight [package workflow](docs/development/r15-package-workflow.md).
  Do not claim token/credit savings from file-size changes; record actual usage
  only when available. Optimize cost per accepted package, not output brevity alone.

Detailed guardrails remain in
[the reference](docs/development/lexiquest-guardrails-reference.md).
Read only the applicable section: scope/continuity (1), filesystem (2),
recovery (3), verification (4), data/research (5), completion (6).
This routing summary does not waive those requirements. Latest user instructions
take precedence; historical checkpoint pauses are not permanent prohibitions.

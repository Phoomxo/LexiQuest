# R15 package workflow

Approved by the user: continuous solo development with efficient context use.
The R15 acceptance contract remains authoritative. No background implementers.

1. Read AGENTS.md and the active checkpoint once. Verify branch/HEAD/status.
   Read only the current requirement/acceptance section and relevant source.
2. Select the smallest next meaningful acceptance gap. Write/run a focused
   regression, fix the demonstrated cause, then verify its affected subsystem.
   Preserve existing passed evidence when its relevant source is unchanged.
3. Save full outputs under build/verification. Show one concise result containing
   status/count/time/source/log path. For failure read only the first relevant
   assertion and its stack. Never load an entire log merely to check status.
4. Capture only required UI states; review representative full-surface images,
   expand coverage for new concerns. One Android build at a source freeze can
   validate several accepted UI packages; avoid an APK rebuild per text edit.
5. Review the diff and requirement coverage, update current state, and commit
   only accepted package files. Keep incomplete/external cases explicit.
6. At a substantial accepted boundary, prefer a fresh task carrying only the
   compact checkpoint and exact source branch/commit when the present history
   is large. Stay in the current task for short, coupled work where reloading
   would cost more. Do not fork full history, spawn concurrent writers, or
   interrupt an unresolved operation for a context-percentage threshold.

## Handoff contract

The source task finishes writes before dispatch. The successor must verify its
actual checkout matches the accepted source; preserve pending work and existing
user branches. If a new worktree is created, start from the explicit accepted
branch/commit, never the default branch by assumption. No codex/ branch prefix.
Transfer only: objective/acceptance IDs, source identity, affected paths, verified
results/log pointers, unresolved cases and next step. Target at most one page.
No repeated full worktree inventory, skill bundle, historical transcript or all
eleven package specs. The successor continues the approved queue autonomously.

## Cost evidence

At package closure record actual gate commands, runtime, source fingerprint,
failures and reason for necessary reruns. Record model token/credit usage only
when the platform exposes it; otherwise mark unavailable. File bytes are not
token counts or credit estimates. Compare accepted outcomes and redundant work,
not just low context percentage. Do not weaken tests, change models blindly,
add an orchestration service, or uninstall plugins to chase an unmeasured saving.

Context compaction permits continuation. Keep the active checkpoint current and
consult original evidence on demand; compaction does not authorize a task pause.

# LexiQuest Development Guardrails

## Current Full-System authority — 2026-09-13 revision 3

- The user has authorized starting G0.1 and continuing sequentially through G8.9, one new Codex task per package. There are 9 phases and 64 package tasks; the previous pause-after-plan instruction is superseded. Use GPT-6 Astra (`gpt-6-astra`) with `medium` reasoning for each task.
- Read `docs/development/full-system-active-index.md`, `docs/development/full-system-package-workflow.md`, and `docs/development/2026-09-13-rule-supersession-register.md` before executing a Full-System package. Package labels G0.1–G8.9 map to the existing P0.1–P8.9 plan IDs; do not create C-prefixed IDs.
- The current Master Plan governs development scope. Legacy milestone-only limits, fixed UI/workaround choices, narrow write sets, and old no-successor instructions do not restrict this plan. Necessary UI, game rules, routes, dependencies, APIs, storage, and schema changes are allowed with a documented design, compatibility/migration decision, and meaningful acceptance coverage.
- The 44-feature catalog and 64-package list are the current coverage baseline, not a permanent product ceiling. Preserve historical catalog/evidence identity; version any actual contract expansion and assign it to the current master plan instead of silently rewriting past records.
- Keep one active package writer. A completed task may create exactly its next task after verification, an accepted source commit, a durable handoff, and writer release. Do not launch all 64 tasks together. Do not start background implementation workers or subagents.
- Use judgment to diagnose recoverable problems and adjust the current package without repeatedly asking for permission. Preserve data correctness, owner isolation, historical evidence/receipt interpretation, and truthful test results. These are acceptance properties, not a prohibition on refactoring or improving the architecture.
- Newer user pause/stop instructions always override automatic task succession. Old files remain historical evidence unless the active index identifies a still-applicable contract.

- Execute one major work package at a time. Do not start background implementation workers.
- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or a Codex Security worker workflow.
- Use `tool/cli/verify-scope.ps1` for bounded targeted and subsystem checks. Run the full release verifier only on a frozen PR or release SHA.
- Do not rerun a passed gate when its recorded source fingerprint is unchanged.
- Do not run full Flutter tests, full backend tests, Android builds, or GPU checks concurrently.
- Stop and report when the same command failure repeats, a filesystem error repeats, or a command makes no measurable progress for 10 minutes.
- Keep research activation, remote research synchronization, study assignment, statistical reporting, and unrelated document work outside the production-system work packages.

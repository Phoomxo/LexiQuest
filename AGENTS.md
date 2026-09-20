# LexiQuest Development Guardrails

## Ari task storage — user correction 2026-09-20

- All new LexiQuest tasks, including planning and documentation, belong to the saved LexiQuest project; do not create projectless tasks for this work.
- Start Ari work from `docs/development/ari/README.md` and follow `docs/development/ari-task-workflow.md`. Keep active reports, state and handoffs in this repository using relative paths. External visualization/task-output folders are historical evidence, not the active write location.
- Sidebar grouping does not change a legacy task's project binding. Preserve old task IDs and receipts; never claim grouping has moved their underlying project or create duplicate implementation tasks to conceal the mismatch.

## Mandatory recovery interpretation — user reaffirmed 2026-09-20

- Missing paths, invalid Windows wildcards, command failures and failing tests are recoverable engineering work. Their repetition NEVER by itself authorizes ending the task or releasing the writer as blocked.
- Stop the failed METHOD; discover real paths/symbols, inspect the cause, correct the approach, fix and retest, then continue the current scope automatically. `rg --files -g 'pattern' .` discovers paths; use `Test-Path -LiteralPath` before exact reads. A search with no matches is information, not a task-stopping condition.
- Before any blocked final response, check the latest user authorization and recovery policy. Stop only for an explicit user pause or a concrete indispensable external prerequisite with no useful authorized work remaining. Record that prerequisite and attempted alternatives. Never cite AGENTS.md as requiring a stop merely because errors repeated; it explicitly requires recovery.
- Preserve acceptance: no skipped defects, weakened assertions, fabricated PASS or false slice completion. Context handoffs must preserve unresolved work and exact checkpoints, not bypass gates.
- Every successor prompt must include this recovery interpretation and current implementation authorization; verify these are present before dispatch. Engineering Spec V3 implementation/succession is authorized in external post-g83-v3-implementation-authorization.json; historical analysis-only restrictions are superseded.

## Current Full-System authority — 2026-09-13 revision 4

- User branch policy: use `lexiquest/` only; never use codex/codeic in branch names. Inspect native worktree names and rename before source writes. Preserve accepted historical receipts; see external `branch-naming-policy.json`.

- Subsequent tasks use Standard/default only: no Fast/1.5x or fast/priority service tier. Keep GPT-6 Astra/medium. Follow external `speed-policy.json`, propagate in each prompt/handoff, and verify effective tier when supported. `create_thread` has no serviceTier field; prompt/config alone do not prove runtime enforcement. If Fast is observed, switch through a supported control or report the limitation before continuing.

- The latest user instruction after accepted G0.5 replaces one task per package with **one task per related-work bundle**. Preserve all9 phases/64 requirement packages and every acceptance criterion. G0.1–G0.5 are accepted history; the62 packages after G0.5 execute in21 bundles B01–B20 plus B11A. Use GPT-6 Astra (`gpt-6-astra`) / `medium`.
- Read `docs/development/full-system-active-index.md`, `docs/development/full-system-package-workflow.md`, and `docs/development/2026-09-13-rule-supersession-register.md`. G/P labels identify requirement units; B identifies a dispatch bundle. `nextPackage` is order only, never an instruction to create a task.
- Keep one application writer and execute packages sequentially inside the current bundle/task/worktree. Check and commit accepted sub-results without opening tasks per commit. Dispatch exactly one next bundle only after all current packages pass, durable accepted-source handoff exists, and writer is released. No subagents, parallel implementers or background implementation workers.
- Read each package brief only when reaching it. Maintain one concise updating Markdown report per bundle; detailed runs/defects/pins go into structured logs. Reuse unchanged passed evidence. Do not preload all briefs, rerun accepted G0.1–G0.5, or repeat command histories.
- Use accepted predecessor source and current revision from handoff. B01 receives the accepted orchestration commit descending from G0.5 `9125ae7b9ccff15bb44ebbab455b8b0251c8fcfe`; do not overwrite with seed7712. The master owns workflow coordination only and does not acquire application implementation scope.
- The current Master governs scope. Retired milestone limits, fixed UI/workarounds, narrow write sets and old dispatch rules cannot block it. Necessary UI/game/routes/dependency/API/storage/schema changes remain allowed with design, compatibility/migration and meaningful acceptance coverage.
- The44-feature catalog/64-package list is a coverage baseline, not a permanent product ceiling. Preserve historical catalog/evidence identity and version actual expansions. Preserve owner isolation, historical evidence/receipt meaning, data correctness and truthful results as acceptance properties.
- B18 freeze/whole-app review/fixes must pass before B19 System Test Plan/execution; B20 closes defects/final ledger. Bundling does not reduce tests or permit deployment/cost/research rollout.
- Use judgment for recoverable blockers without repeating prior approval questions. New user pause/stop overrides succession. Revision17's pause stopped old per-package dispatch and was superseded by explicit grouped-execution authorization.

- Execute one major work package at a time. Do not start background implementation workers.
- Do not invoke, install, resume, or recommend Codex Security, Security Scan, Deep Scan, or a Codex Security worker workflow.
- Use `tool/cli/verify-scope.ps1` for bounded targeted and subsystem checks. Run the full release verifier only on a frozen PR or release SHA.
- Do not rerun a passed gate when its recorded source fingerprint is unchanged.
- Do not run full Flutter tests, full backend tests, Android builds, or GPU checks concurrently.
- For repeated command or path failures, stop the failed method and follow the user recovery policy below; do not blind retry or skip acceptance.
- Keep research activation, remote research synchronization, study assignment, statistical reporting, and unrelated document work outside the production-system work packages.

- Recovery policy (user update 2026-09-13): stop a failed method, preserve evidence, diagnose, use a corrected bounded method and continue without repeated permission. Repeated failures or ten minutes without progress require a new diagnostic approach, not ending the task. Diagnose, fix and rerun affected tests autonomously until acceptance is proven. Stop only for a user pause or a concrete indispensable external blocker with no safe useful work remaining. Never skip/disable tests, weaken assertions or acceptance, hide errors, use noncompliant fallbacks, claim unproven PASS, or move unresolved defects to a successor to bypass a gate. Fixture corrections must preserve or strengthen real behavior checks and record the cause. Use `rg --files -g` for glob discovery and literal existing paths for reads; never put wildcards in Windows path arguments. Preserve gates and propagate external `recovery-policy.json` in every successor.

## Camera training amendment — 2026-09-14

Canonical revision `2026-09-14-camera-training-5`: คง64 requirement IDsเดิม เพิ่ม G5.3a–c รวม67packages/21bundles (B11Aเพิ่มหนึ่งbundle). ลำดับ B11 → B11A → B12 → B13…B20. ใช้ภาพอินเทอร์เน็ตสำหรับ train/development validation ตอนนี้ ไม่รอภาพจากผู้ใช้. เก็บภาพกล้องจริงตอน device testing ภายหลัง; ผลกล้องจริง pending จนทดสอบจริง ห้ามใช้คะแนนเว็บอ้างแทน. Fresh test ห้ามปรับ threshold/เทรน; หากนำภาพกล้องที่ดูแล้วมาแก้/ฝึกให้จัดเป็น development และใช้ชุดกล้อง held-out ใหม่ตรวจรับ. เก็บ unknown-object evaluation แยกชัดเจน. Trainingจริงเป็นrequired deliverable; baseline retentionหรือเอกสารไม่ปิดG5.3c. ใช้ source rights/actual compute และไม่เพิ่มค่าใช้จ่ายโดยอนุมาน.

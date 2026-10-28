# LexiQuest Safe Repository Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the 21 approved obsolete tracked artifacts and repair only
the references and verification scope made inaccurate by those removals.

**Architecture:** This is a single atomic cleanup task. Text files are removed
through patch-based edits, the binary screenshot is removed by one verified
exact-path operation, and one consolidated focused gate validates the complete
change.

**Tech Stack:** Git, PowerShell 5.1, Dart/Flutter tests, Markdown.

## Global Constraints

- Delete exactly the 21 paths listed in the approved cleanup specification.
- Never run `git clean`, delete a directory recursively, or delete build/APK
  output.
- Preserve all production source, current tests, platform directories,
  negative Supabase guardrails, Git history, and `baseline/2024-10`.
- The screenshot path must resolve beneath the isolated worktree before its
  exact file is removed.
- Run one consolidated verification gate after all cleanup edits.
- Do not invoke Codex Security workflows.
- Do not retry a repeated filesystem/tool failure.

---

### Task 1: Apply the approved cleanup atomically

**Files:**

- Delete: `docs/superpowers/plans/2026-07-23-flutter-toolchain-modernization.md`
- Delete: `docs/superpowers/plans/2026-07-23-omnivoice-backend-poc.md`
- Delete: `docs/superpowers/plans/2026-07-24-flutter-voice-integration.md`
- Delete: `docs/superpowers/plans/2026-07-26-learning-event-vertical-slice.md`
- Delete: `docs/superpowers/plans/2026-07-26-production-foundation-integration.md`
- Delete: `docs/superpowers/plans/2026-07-26-stabilization-gate.md`
- Delete: `docs/superpowers/plans/2026-07-27-runtime-modernization.md`
- Delete: `docs/superpowers/plans/2026-07-28-release-a-production-completion.md`
- Delete: `docs/superpowers/specs/2026-07-23-omnivoice-integration-design.md`
- Delete: `docs/superpowers/specs/2026-07-26-vertical-slice-integration-design.md`
- Delete: `docs/superpowers/specs/2026-07-27-runtime-modernization-design.md`
- Delete: `docs/superpowers/specs/2026-07-27-stabilization-to-associative-reading-program-design.md`
- Delete: `docs/superpowers/specs/2026-07-29-v0.1-complete-system-design.md`
- Delete: `docs/superpowers/notes/2026-07-27-built-in-kotlin-deferral.md`
- Delete: `docs/security/supabase-access-inventory.md`
- Delete: `docs/security/2026-07-26-stabilization-gate.md`
- Delete: `supabase/config.toml`
- Delete: `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`
- Delete: `test/security/supabase_migration_upgrade_contract_test.dart`
- Delete: `test/security/supabase_storage_contract.sql`
- Delete: `android_emulator_screenshot.png`
- Modify: `tool/cli/verify-scope.ps1`
- Modify: `tool/cli/tests/verify-scope.tests.ps1`
- Modify: `tool/cli/tests/firestore-rules-security.tests.ps1`
- Modify: `docs/security/progress-authority.md`
- Modify: `docs/superpowers/plans/2026-07-29-v0.1-release-foundation.md`
- Modify: `README.md`

**Interfaces:**

- Consumes: the approved deletion list in
  `docs/superpowers/specs/2026-07-30-safe-repository-cleanup-design.md`.
- Produces: a Firebase-only tracked repository whose active documentation
  points to the Real Local-First Prototype design and master plan.

- [ ] **Step 1: Add the failing scope contract**

Add this assertion immediately after the existing area-contract assertion in
`tool/cli/tests/verify-scope.tests.ps1`:

```powershell
Assert-NotContainsString `
    $scopeText `
    'supabase/' `
    'all-area fingerprint excludes the retired Supabase directory'
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
```

Expected: exit `1` because the `All` path pattern still includes
`supabase/`.

- [ ] **Step 3: Remove the retired scope entry**

In `tool/cli/verify-scope.ps1`, set the `All` pattern to:

```powershell
return '^(lib/|test/|backend/|tool/cli/|android/|firestore\.rules|storage\.rules|\.github/workflows/|pubspec\.(yaml|lock)|package(-lock)?\.json)'
```

- [ ] **Step 4: Repair active references**

Make these bounded documentation changes:

1. In `tool/cli/tests/firestore-rules-security.tests.ps1`, describe
   `docs/security/firestore-access-inventory.md` as the active least-privilege
   policy record.
2. In `docs/security/progress-authority.md`, replace the deleted stabilization
   report link with `docs/security/firestore-access-inventory.md`.
3. In `docs/superpowers/plans/2026-07-29-v0.1-release-foundation.md`, replace
   references to the deleted Supabase inventory with an explicit sentence
   that the artifact was removed by the 2026-07-30 safe cleanup and remains
   available in Git history.
4. In `README.md`, add this block after the overview:

```markdown
## Current prototype direction

Active implementation follows the
[Real Local-First Prototype design](docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md)
and its
[master plan](docs/superpowers/plans/2026-07-30-real-local-first-prototype-master-plan.md).
Older experimental plans are available from Git history rather than the active
documentation tree.
```

- [ ] **Step 5: Delete the 20 text artifacts**

Delete exactly the 20 text paths from the task file list. Do not delete parent
directories recursively. Confirm each path was tracked before applying its
deletion.

- [ ] **Step 6: Delete the screenshot by verified exact path**

Resolve `android_emulator_screenshot.png`, confirm its parent is the worktree
root, then remove only that file with `Remove-Item -LiteralPath`. Do not use a
glob or `-Recurse`.

- [ ] **Step 7: Run the consolidated cleanup gate**

Run once:

```powershell
git diff --check
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
flutter test test/config/flutter_dependency_surface_test.dart --reporter compact
```

Expected: every command exits `0`.

- [ ] **Step 8: Verify deletion and preservation boundaries**

Use exact tracked-path checks to prove all 21 deletion targets are absent.
Then prove these remain tracked:

```text
docs/superpowers/plans/2026-07-29-v0.1-release-foundation.md
docs/superpowers/plans/2026-07-29-v0.1-navigation-accounts.md
docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md
docs/superpowers/plans/2026-07-30-real-local-first-prototype-master-plan.md
docs/security/firestore-access-inventory.md
docs/security/progress-authority.md
tool/cli/tests/ci-workflow.tests.ps1
test/config/flutter_dependency_surface_test.dart
```

Expected: no deletion target is tracked or present, every preservation target
is tracked, and `git status --short` lists only this task's intended changes.

- [ ] **Step 9: Commit**

```powershell
git add --all
git commit -m "chore: remove superseded repository artifacts"
```

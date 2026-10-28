# LexiQuest Safe Repository Cleanup Design

**Date:** 2026-07-30

## 1. Objective

Reduce ambiguity for future implementation work by removing only tracked
artifacts that have been superseded, retired, or are unrelated to the active
Real Local-First Prototype. Preserve all application source, platform targets,
current release foundations, negative dependency guardrails, and recoverable
Git history.

## 2. Safety boundary

This cleanup is intentionally conservative:

- no `git clean`, recursive wildcard deletion, dependency-cache deletion, or
  build-output deletion;
- no feature source, active test, Firebase policy, Windows/Linux platform
  target, APK, user file, or baseline branch is removed;
- every deleted tracked file remains recoverable from Git commit `c343682` or
  earlier history;
- exact paths are verified inside the isolated worktree before deletion;
- the binary screenshot is deleted only by exact absolute path after its
  resolved path is confirmed to remain inside the worktree.

## 3. Files to remove

### 3.1 Superseded plans

1. `docs/superpowers/plans/2026-07-23-flutter-toolchain-modernization.md`
2. `docs/superpowers/plans/2026-07-23-omnivoice-backend-poc.md`
3. `docs/superpowers/plans/2026-07-24-flutter-voice-integration.md`
4. `docs/superpowers/plans/2026-07-26-learning-event-vertical-slice.md`
5. `docs/superpowers/plans/2026-07-26-production-foundation-integration.md`
6. `docs/superpowers/plans/2026-07-26-stabilization-gate.md`
7. `docs/superpowers/plans/2026-07-27-runtime-modernization.md`
8. `docs/superpowers/plans/2026-07-28-release-a-production-completion.md`

### 3.2 Superseded specifications and note

1. `docs/superpowers/specs/2026-07-23-omnivoice-integration-design.md`
2. `docs/superpowers/specs/2026-07-26-vertical-slice-integration-design.md`
3. `docs/superpowers/specs/2026-07-27-runtime-modernization-design.md`
4. `docs/superpowers/specs/2026-07-27-stabilization-to-associative-reading-program-design.md`
5. `docs/superpowers/specs/2026-07-29-v0.1-complete-system-design.md`
6. `docs/superpowers/notes/2026-07-27-built-in-kotlin-deferral.md`

### 3.3 Retired Supabase and stabilization artifacts

1. `docs/security/supabase-access-inventory.md`
2. `docs/security/2026-07-26-stabilization-gate.md`
3. `supabase/config.toml`
4. `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`
5. `test/security/supabase_migration_upgrade_contract_test.dart`
6. `test/security/supabase_storage_contract.sql`

The runtime already uses Firebase only. Negative assertions that prevent
Supabase from returning remain active.

### 3.4 Obsolete visual artifact

1. `android_emulator_screenshot.png`

## 4. Files to retain

- `docs/superpowers/plans/2026-07-29-v0.1-release-foundation.md`
- `docs/superpowers/plans/2026-07-29-v0.1-navigation-accounts.md`
- `docs/superpowers/specs/2026-07-30-real-local-first-prototype-design.md`
- `docs/superpowers/plans/2026-07-30-real-local-first-prototype-master-plan.md`
- `docs/security/firestore-access-inventory.md`
- `docs/security/progress-authority.md`
- Windows, Linux, Android, iOS, macOS, and web platform directories
- all production feature source and current test source
- CI and dependency tests that assert Supabase is absent
- `.gitleaksignore` entries needed to scan repository history
- Git history and `baseline/2024-10`

## 5. Supporting edits

The cleanup updates only references made inaccurate by the removals:

- remove `supabase/` from the `All` source-fingerprint pattern in
  `tool/cli/verify-scope.ps1`;
- add a focused contract assertion proving the retired directory is not part
  of that pattern;
- replace references to the deleted stabilization report with the active
  Firestore inventory or progress authority;
- mark the retained release-foundation plan as historical where it names the
  removed Supabase audit artifact;
- add a concise active-documentation section to `README.md` pointing at the
  current prototype design and master plan.

Historical mentions of Supabase that document its retirement may remain when
they do not point readers to a deleted active artifact.

## 6. Verification

Run one consolidated cleanup gate:

```powershell
git diff --check
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1
flutter test test/config/flutter_dependency_surface_test.dart --reporter compact
```

Then perform bounded exact-path checks:

- all 21 deletion targets are absent from the index and worktree;
- active documentation does not link to the deleted stabilization or Supabase
  inventory documents;
- current negative Supabase dependency and CI guardrails remain tracked;
- unrelated worktree files are unchanged.

## 7. Recovery

Every deleted file can be inspected or restored from commit `c343682` with a
path-specific Git command. The cleanup commit will contain no rewrite of Git
history and no deletion of untracked data.

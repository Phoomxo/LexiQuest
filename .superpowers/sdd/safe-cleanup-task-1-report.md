# Safe Cleanup Task 1 Report

## Implemented scope

Applied only the approved Task 1 cleanup list on `release/v0.1-complete-system`
from base commit `04c6780`. The `All` source-fingerprint scope now excludes the
retired `supabase/` directory. Active references now point to the Firestore
least-privilege inventory, the release-foundation plan records the retirement
of the Supabase inventory artifact, and the README identifies the active
local-first prototype design and master plan.

## TDD evidence

- RED: Added the required `Assert-NotContainsString $scopeText 'supabase/'`
  assertion immediately after the area-contract assertion. Running
  `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1`
  exited `1` with `all-area fingerprint excludes the retired Supabase directory`.
  The failure was caused by the existing `All` pattern containing `supabase/`.
- GREEN: Changed only the `All` pattern in `tool/cli/verify-scope.ps1` to the
  approved value. The focused contract then exited `0`: `44 passed, 0 failed`.

## Consolidated cleanup gate

The required single gate exited `0`:

- `git diff --check`
- `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-scope.tests.ps1` — 44 passed, 0 failed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/ci-workflow.tests.ps1` — 118 passed, 0 failed.
- `flutter test test/config/flutter_dependency_surface_test.dart --reporter compact` — 3 passed.

## Files changed and deleted

Modified:

- `tool/cli/verify-scope.ps1`
- `tool/cli/tests/verify-scope.tests.ps1`
- `tool/cli/tests/firestore-rules-security.tests.ps1`
- `docs/security/progress-authority.md`
- `docs/superpowers/plans/2026-07-29-v0.1-release-foundation.md`
- `README.md`

Deleted exactly these 21 approved artifacts:

- 8 obsolete plans under `docs/superpowers/plans/` dated 2026-07-23 through 2026-07-28.
- 5 obsolete specs under `docs/superpowers/specs/` dated 2026-07-23 through 2026-07-29.
- `docs/superpowers/notes/2026-07-27-built-in-kotlin-deferral.md`.
- `docs/security/supabase-access-inventory.md` and `docs/security/2026-07-26-stabilization-gate.md`.
- `supabase/config.toml` and `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`.
- `test/security/supabase_migration_upgrade_contract_test.dart` and `test/security/supabase_storage_contract.sql`.
- `android_emulator_screenshot.png`.

## Screenshot path-safety evidence

Before removal, the screenshot resolved to
`C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system\android_emulator_screenshot.png`.
Its parent resolved exactly to the worktree root
`C:\Users\Phet\Documents\LexiQuest\.worktrees\release-v0.1-complete-system`,
and `git ls-files --error-unmatch -- android_emulator_screenshot.png` confirmed
it was tracked. It was then removed with `Remove-Item -LiteralPath` only; no
glob or recursive deletion was used.

## Self-review and boundaries

All 20 text deletion targets were confirmed tracked before their `apply_patch`
deletions. No parent directory was deleted. The required preservation paths
were checked after staging, because Git continues to report a deleted file
as tracked until its deletion is staged: all 21 deletion targets were absent
and untracked, and all 8 preservation targets remained tracked. No build or `.dart_tool` tree was
enumerated, no `git clean` command was used, and no security-worker workflow
was invoked.

## Concerns

None. Git emitted only CRLF checkout warnings during the gate; `git diff --check`
exited successfully.

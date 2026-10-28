# Release A Verification Lane 3B — Security / Backend Policy Gates

- Candidate SHA: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`
- Base SHA for commit-scoped scanning: `f66d0316daff57c83ed972a11f6425cb326f482a`
- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-verify-security`
- Receipt timestamp: `2026-07-28T17:59:57.8615824Z`
- Scope: Task 4 security/backend policy gates only; no source edits, real cloud writes, or credentialed OmniVoice/Firebase smoke.

## Initial candidate assertions

Command:

```powershell
git rev-parse HEAD
git rev-parse --git-dir
git rev-parse --git-common-dir
git branch --show-current
git status --short --untracked-files=no
```

Result:

- Exit code: `0`
- `HEAD`: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675` (exact match)
- Linked worktree: yes (`.git\worktrees\release-a-verify-security` differs from common `.git`)
- Branch: empty; detached HEAD confirmed
- Initial tracked status entries: `0`

## Firestore emulator contract

Exact command:

```powershell
$env:NODE_PATH='C:\Users\Phet\Documents\LexiQuest\node_modules'
npm run test:rules
```

Result:

- Exit code: `0`
- Tests: `45`
- Suites: `6`
- Passed: `45`
- Failed: `0`
- Cancelled: `0`
- Skipped: `0`
- Todo: `0`
- Firebase emulator reported the test script exited successfully and shut down.

## Structural Firestore PowerShell contract

Exact command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\cli\tests\firestore-rules-security.tests.ps1
```

Result:

- Exit code: `0`
- Passed assertions: `21`
- Failed assertions: `0`
- Terminal result: `PASS`

## Commit-scoped Gitleaks

Exact command:

```powershell
gitleaks git --log-opts="f66d0316daff57c83ed972a11f6425cb326f482a..HEAD" --config .gitleaks.toml --redact --no-banner --exit-code 1
```

Result:

- Exit code: `0`
- Commits scanned: `12`
- Bytes scanned: `139853` (`139.85 KB`)
- Leaks found: `0`

## OSV policy scan

Exact command:

```powershell
osv-scanner scan source --config osv-scanner.toml `
  --lockfile package-lock.json `
  --lockfile pubspec.lock `
  --lockfile backend/ai_api/uv.lock `
  --lockfile backend/voice_api/uv.lock `
  --lockfile backend/lexiquest_lm/uv.lock `
  --lockfile backend/lexiquest_lm/deploy/hf_space/requirements.txt
```

Result:

- Exit code: `0`
- Inputs scanned: `6`
- Packages found:
  - `package-lock.json`: `242`
  - `pubspec.lock`: `122`
  - `backend/ai_api/uv.lock`: `63`
  - `backend/voice_api/uv.lock`: `143`
  - `backend/lexiquest_lm/uv.lock`: `85`
  - `backend/lexiquest_lm/deploy/hf_space/requirements.txt`: `8`
- Total package observations: `663`
- Filtered vulnerabilities: `2`
  - `GHSA-mh99-v99m-4gvg` (`1` alias), filtered by the repository policy.
  - `GHSA-w5hq-g745-h8pq` (`2` aliases), filtered by the repository policy.
- Unignored issues: `0`
- Terminal result: `No issues found`

## Local Supabase policy contract

Exact commands, run fail-fast inside `try` with `supabase stop --no-backup` in `finally`:

```powershell
supabase db start
supabase db reset --local --no-seed
supabase db lint --local --level warning
supabase db advisors --local --type security --level warn --fail-on error
Get-Content -Raw test/security/supabase_storage_contract.sql |
  docker exec -i supabase_db_lexiquest-local `
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f -
supabase stop --no-backup
```

Result:

- `supabase db start`: exit `0`
- `supabase db reset --local --no-seed`: exit `0`; migration `20260727000000_image_bucket_public_readonly.sql` applied
- `supabase db lint --local --level warning`: exit `0`; `0` schema errors
- `supabase db advisors --local --type security --level warn --fail-on error`: exit `0`; `0` issues
- SQL storage contract: exit `0`; transaction reached `ROLLBACK`, leaving no persistent probe data
- `supabase stop --no-backup`: exit `0`
- Running `supabase_*lexiquest-local` containers after cleanup: `0`
- Overall Supabase gate exit: `0`

## Final candidate assertions

- Receipt ignore rule: `.git/info/exclude:7:.superpowers/sdd/`
- Final `HEAD`: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675` (exact match)
- Final `git status --short --untracked-files=no`: exit `0`, `0` tracked entries
- Final `git status --short`: exit `0`, `0` visible entries (the receipt is ignored)

## Gate summary

All requested local security/backend policy gates returned exit code `0`. The credentialed OmniVoice/Firebase smoke and all deployed/cloud policy writes were intentionally not run, per lane scope.

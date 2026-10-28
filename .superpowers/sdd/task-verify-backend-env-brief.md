# Task: Make full verification reproducible in a clean worktree

## Base

`57e12ca940c88cb64fb2843f6ba60fa85d9e1675`

## Root cause

`uv run --frozen --no-sync --group dev` creates an empty project `.venv` in a
fresh worktree and intentionally installs nothing. The three backend phases
therefore cannot spawn `pytest`. Existing warm worktrees concealed the defect.
All three lockfiles resolve correctly and include the dev test dependencies.

## Authorized tracked files

- Modify: `tool/cli/verify.ps1`
- Create: `tool/cli/tests/verify-backend-environments.tests.ps1`
- Modify: `docs/runbooks/android-lan-development.md`

Do not modify dependency manifests or lockfiles.

## TDD contract

Write the structural PowerShell regression test first and run it against the
base implementation. RED must show that all three backend phases still use
`--no-sync` and do not express the explicit optional-group exclusions.

The test must prove:

- Voice, AI, and Local LM phases use `--frozen` and `--group dev`.
- None uses `--no-sync` or `--all-groups`.
- Voice explicitly excludes `gpu`.
- AI explicitly excludes `llm`.
- Local LM explicitly excludes `train`.
- The new regression test is included in the phase 02.1 contract test list.

## Minimal implementation

For the three backend `uv run` calls:

- remove `--no-sync`;
- retain `--frozen --group dev`;
- add `--no-group gpu`, `--no-group llm`, or `--no-group train` for the
  corresponding project.

Update the script description and Android runbook so they state that frozen
CPU/dev environments are provisioned while optional GPU/training/LLM groups
remain excluded. Do not claim offline/no-sync behavior.

## Verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\tool\cli\tests\verify-backend-environments.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\tool\cli\tests\ci-workflow.tests.ps1
uv lock --check --project backend/voice_api
uv lock --check --project backend/ai_api
uv lock --check --project backend/lexiquest_lm
uv run --project backend/voice_api --frozen --group dev --no-group gpu `
  pytest backend/voice_api/tests -q --ignore=backend/voice_api/tests/integration
uv run --project backend/ai_api --frozen --group dev --no-group llm `
  pytest backend/ai_api/tests -q
uv run --project backend/lexiquest_lm --frozen --group dev --no-group train `
  pytest backend/lexiquest_lm/tests -q
git diff --check
```

Do not run the entire verification script in the implementation worktree; the
detached verification lane will rerun it from a fresh environment after
independent review.

## Commit

Commit exactly the three authorized tracked files as:

`fix(verify): provision backend dev environments`

Write the ignored RED/GREEN receipt to:

`.superpowers/sdd/task-verify-backend-env-report.md`

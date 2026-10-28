# Backend environment verification TDD receipt

- Base SHA: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`
- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-economy-lockdown`
- Scope: `tool/cli/verify.ps1`,
  `tool/cli/tests/verify-backend-environments.tests.ps1`, and
  `docs/runbooks/android-lan-development.md`

## RED

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\tool\cli\tests\verify-backend-environments.tests.ps1
```

Result: exit `1`; `19 passed, 7 failed (of 26)`.

The seven expected failures proved that phase 02.1 did not include the new
contract test, all three backend phases still used `--no-sync`, and none
explicitly excluded its optional `gpu`, `llm`, or `train` group.

## GREEN

The same command after the minimal production change returned exit `0`:
`26 passed, 0 failed (of 26)`.

## Focused verification

- CI workflow contract: exit `0`; `62 passed, 0 failed (of 62)`.
- `uv lock --check --project backend/voice_api`: exit `0`.
- `uv lock --check --project backend/ai_api`: exit `0`.
- `uv lock --check --project backend/lexiquest_lm`: exit `0`.
- Voice API frozen dev environment with `--no-group gpu`: exit `0`;
  `55 passed`.
- AI API frozen dev environment with `--no-group llm`: exit `0`;
  `76 passed`.
- Local LM frozen dev environment with `--no-group train`: exit `0`;
  `75 passed`.
- `git diff --check`: exit `0`.

Each backend command started without a project `.venv`, provisioned the
environment from its frozen lockfile, and completed its CPU test suite.
The full `tool/cli/verify.ps1` was intentionally not run in this implementation
worktree because the task brief reserves that check for the detached
verification lane.

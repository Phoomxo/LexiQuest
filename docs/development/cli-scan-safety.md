# CLI Scan Safety

## Incident

A PowerShell `Get-ChildItem -Recurse` command was started at the repository
root while multiple linked Git worktrees were present under `.worktrees/`.
Those worktrees contain active and stale build directories. Some nested Android
transform directories disappeared while PowerShell was enumerating them, so
the command emitted repeated `DirectoryNotFoundException` errors.

The repository and Git worktree metadata were intact. The failure was caused by
an overly broad filesystem scan, not by Drift code generation or source-file
loss.

## Required Search Pattern

Search source with `rg` and an explicit target:

```powershell
rg --files lib/data/local test/data/local
rg -n "pattern" lib test
```

Inspect a known directory without recursion:

```powershell
Get-ChildItem -LiteralPath lib\data\local -File
```

If PowerShell recursion is unavoidable, scope it to one source directory and
exclude build/cache directories before descending. Do not recursively enumerate
the repository root.

## Prohibited Pattern

Do not run:

```powershell
Get-ChildItem -Recurse
```

from the LexiQuest repository root. It crosses `.worktrees/`, nested virtual
environments, generated Android transforms, and other independently changing
trees.

## Worktree Checks

Use Git metadata instead of filesystem recursion:

```powershell
git worktree list --porcelain
git status --short
```

`.worktrees/` is already excluded by `.gitignore`. No worktree is deleted or
pruned as part of feature development unless the owner explicitly requests it.

## Failure Rule

When a filesystem command reports the same path error repeatedly:

1. stop the command;
2. do not retry the same traversal;
3. identify the directory boundary that was too broad;
4. replace it with a scoped `rg` or literal-path command;
5. verify `git status` before continuing.

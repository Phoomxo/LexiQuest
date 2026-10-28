# Release A mobile/full-repository verification receipt

- Candidate SHA: `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`
- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-verify-mobile`
- Scope: Task 4, Step 3 from `docs/superpowers/plans/2026-07-28-release-a-production-completion.md`
- Source policy: read-only; no source fixes, normalization, revert, or commit performed

## Initial candidate assertions

- `git rev-parse HEAD`: exit `0`; output exactly `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`
- `git status --porcelain=v1 --untracked-files=no`: exit `0`; no output, so the initial tracked tree was clean

## Required command

Executed exactly once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\cli\verify.ps1
```

- Outer command exit: `1`
- Wall time reported by the command runner: `121 seconds`
- Verification-script result: `FAIL`

## Phase evidence

| Phase | Check | Outcome | Count / duration evidence |
|---|---|---|---|
| 01 | Protected runtime probe tests | PASS | `49 passed, 0 failed (of 49)` |
| 02 | Android command construction tests | PASS | `35 passed, 0 failed (of 35)` |
| 02.1 | CI/CD contract tests | PASS | `156 passed, 0 failed` in aggregate: CI workflow 62; Dependabot 11; OSV PR 9; OSV scheduled 8; OSV config 6; Firebase seed security 8; Firestore rules security 21; model-loading security 5; Android manifest security 6; Android release-signing 20 |
| 03 | Flutter dependency resolution | PASS | `Got dependencies!`; advisory only: 8 packages have newer versions incompatible with constraints |
| 04 | Dart format check (tracked sources only) | PASS | 264 files checked, 0 changed; batch times `0.21`, `0.57`, `0.12`, `0.18`, `0.14`, `0.08`, and `0.19` seconds (1.49 seconds total) |
| 05 | Flutter static analysis | PASS | `No issues found!`; 8.8 seconds |
| 06 | Flutter unit and widget tests | PASS | `622` passed, `0` failed; test-runner elapsed `01:17` |
| 07 | Voice API CPU-only tests | FAIL, phase exit `2` | Used CPython 3.11.15, created `backend\voice_api\.venv`, then `Failed to spawn: pytest` because `program not found` |
| 08 | AI API CPU-only tests | NOT RUN | Fail-fast after phase 07 |
| 09 | Local LM CPU-only tests | NOT RUN | Fail-fast after phase 07 |
| 10 | Android debug APK build | NOT RUN | Fail-fast after phase 07 |
| 11 | Read-only live GPU doctor | NOT RUN | Fail-fast after phase 07 |

## APK evidence

No APK was produced by this verification run because phase 10 was not reached. Therefore the script provided no APK output path or hash.

## Blocker

The frozen/no-sync Voice API environment did not contain a runnable `pytest` program. The verification script stopped at phase 07 as designed, so the full-repository gate is **failed** for this candidate SHA.

## Final tracked status

`HEAD` remained `57e12ca940c88cb64fb2843f6ba60fa85d9e1675`.

`git status --porcelain=v1 --untracked-files=no` reported:

```text
 M linux/flutter/generated_plugin_registrant.cc
 M linux/flutter/generated_plugin_registrant.h
 M linux/flutter/generated_plugins.cmake
 M macos/Flutter/GeneratedPluginRegistrant.swift
 M windows/flutter/generated_plugin_registrant.cc
 M windows/flutter/generated_plugin_registrant.h
 M windows/flutter/generated_plugins.cmake
```

These seven tracked generated files show line-ending/stat dirt after dependency resolution. Both `git diff --numstat` and `git diff --raw` emitted no content diff, while Git warned for each file that LF would be replaced by CRLF the next time Git touches it. Per the verification-lane instructions, they were identified but not normalized or reverted.

This receipt is ignored by `C:/Users/Phet/Documents/LexiQuest/.git/info/exclude` rule `.superpowers/sdd/`.

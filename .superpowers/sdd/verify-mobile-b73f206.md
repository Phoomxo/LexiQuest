# Mobile verification evidence — b73f206

- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-verify-mobile-b73f206`
- Requested commit: `b73f206b94b217101836007d92e8444faa3e69da`
- Verification recorded: `2026-07-29T01:26:13.2699616+07:00`
- Source edits/fixes/commits by verifier: none

## Initial preflight

- `git rev-parse --show-toplevel`: `C:/Users/Phet/Documents/LexiQuest/.worktrees/release-a-verify-mobile-b73f206`
- `git rev-parse HEAD`: `b73f206b94b217101836007d92e8444faa3e69da`
- HEAD state: detached (`git symbolic-ref -q HEAD` did not resolve)
- `git status --porcelain=v1 --untracked-files=no`: 0 lines
- Precondition result: exact SHA and clean tracked tree confirmed.

## Verification invocation

The following command was invoked exactly once:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\cli\verify.ps1
```

- Process exit code: `0`
- Observed wall time: `303.6 s`
- Script conclusion: `LexiQuest verification: PASS`

## Phase results and counts

| Phase | Result | Exact count/evidence |
|---|---:|---|
| 01. Protected runtime probe tests | PASS | 49 passed, 0 failed (49 total); training detection, GPU snapshot, and runtime guard all passed |
| 02. Android command construction tests | PASS | 35 passed, 0 failed (35 total) |
| 02.1. CI/CD contract tests | PASS | 182 passed, 0 failed across 11 suites; detailed below |
| 03. Flutter dependency resolution | PASS | Dependencies resolved; 8 packages reported newer versions incompatible with current constraints |
| 04. Dart format check (tracked sources only) | PASS | 7 batches (`40 + 40 + 40 + 40 + 40 + 40 + 24 = 264` tracked Dart files checked), 0 changed |
| 05. Flutter static analysis | PASS | `No issues found!` (7.3 s), 0 issues |
| 06. Flutter unit and widget tests | PASS | 622 passed, 0 failed |
| 07. Voice API CPU-only tests | PASS | 55 passed, 0 failed (0.86 s) |
| 08. AI API CPU-only tests | PASS | 76 passed, 0 failed (0.83 s) |
| 09. Local LM CPU-only tests | PASS | 75 passed, 0 failed (0.53 s) |
| 10. Android debug APK build (emulator loopback) | PASS | Gradle `assembleDebug` completed in 156.5 s; APK built |
| 11. Read-only live GPU doctor | PASS | Repository/tools/GPU ready; no training active; inference permitted |

Explicit test-case aggregate: **1,094 passed, 0 failed** (`49 + 35 + 182 + 622 + 55 + 76 + 75`).

### Phase 02.1 suite detail

| Contract suite | Passed | Failed |
|---|---:|---:|
| CI workflow | 62 | 0 |
| Backend environment | 26 | 0 |
| Dependabot | 11 | 0 |
| OSV PR workflow | 9 | 0 |
| OSV scheduled workflow | 8 | 0 |
| OSV config | 6 | 0 |
| Firebase seed security | 8 | 0 |
| Firestore rules security | 21 | 0 |
| Model loading security | 5 | 0 |
| Android manifest security | 6 | 0 |
| Android release signing | 20 | 0 |
| **Total** | **182** | **0** |

## APK evidence

- Path: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-verify-mobile-b73f206\build\app\outputs\flutter-apk\app-debug.apk`
- Size: `163466858` bytes
- SHA-256: `f3b649827d68a9ab7d1b5dbf8aab37057715e54b251a7391b77053eca84cd9fb`

## GPU doctor evidence

Exact JSON emitted by phase 11:

```json
{"RepositoryReady":true,"RequiredToolsReady":true,"MissingRequiredTools":[],"TrainingActive":false,"TrainingProcessIds":[],"GpuAvailable":true,"GpuName":"NVIDIA GeForce RTX 3050","UsedMemoryMiB":1687,"MemoryTotalMiB":8192,"UtilizationPercent":19,"TemperatureCelsius":34,"MayStartGpuInference":true}
```

## Generated line-ending/stat-only effects

Immediately after verification, `git status --porcelain=v1 --untracked-files=no` reported these 7 unstaged generated files:

```text
 M linux/flutter/generated_plugin_registrant.cc
 M linux/flutter/generated_plugin_registrant.h
 M linux/flutter/generated_plugins.cmake
 M macos/Flutter/GeneratedPluginRegistrant.swift
 M windows/flutter/generated_plugin_registrant.cc
 M windows/flutter/generated_plugin_registrant.h
 M windows/flutter/generated_plugins.cmake
```

These flags contain no source-content delta:

- `git diff --raw`, `git diff --numstat`, and `git diff --ignore-cr-at-eol --name-status` returned no entries.
- `git ls-files --eol` reported `i/lf w/lf` for all seven files.
- `core.autocrlf=true`.
- For every file, the HEAD blob, raw worktree blob, and filtered worktree blob are identical:

| File | Identical HEAD/raw/filtered blob |
|---|---|
| `linux/flutter/generated_plugin_registrant.cc` | `fb283e0dc327a73d309d71a6c7c871e1cd3c668f` |
| `linux/flutter/generated_plugin_registrant.h` | `e0f0a47bc08f30b550b47b01de4c9206b6824dd9` |
| `linux/flutter/generated_plugins.cmake` | `18303b296641ec275666126b7d118a3e7b3d1135` |
| `macos/Flutter/GeneratedPluginRegistrant.swift` | `a56042c79388ae1a8a3a7507ec881d426ffadcf1` |
| `windows/flutter/generated_plugin_registrant.cc` | `1c964ab198153ffc4a2e326aadb41de47041ce93` |
| `windows/flutter/generated_plugin_registrant.h` | `dc139d85a93101cc0f6e9db03a3e1a9f68e8dd7e` |
| `windows/flutter/generated_plugins.cmake` | `52dd74d106818027277b9f80e0a92e424115da03` |

Interpretation: Flutter tooling rewrote/touched generated registrants under Windows checkout line-ending rules; Git status retained worktree flags, but there is no semantic or blob-level change. No cleanup or source patch was performed.

## Non-failing warnings

- `jni 1.0.1` is retracted; eight packages have newer versions outside current dependency constraints.
- Flutter warned that Android Gradle Plugin `8.9.1` will soon be unsupported and recommends at least `8.11.1`.
- Flutter warned that Kotlin `2.1.0` will soon be unsupported and recommends at least `2.2.20`.
- Android tooling warned that it understands SDK XML through version 3 but encountered version 4.
- Java compilation emitted unchecked/unsafe, deprecated, and overridden-API notes.

## Final state

- HEAD remained `b73f206b94b217101836007d92e8444faa3e69da`.
- HEAD remained detached.
- Staged changes: 0.
- Semantic/content diffs: 0.
- Tracked status flags: 7 generated line-ending/stat-only entries listed above.
- This report is ignored by `C:/Users/Phet/Documents/LexiQuest/.git/info/exclude` rule `.superpowers/sdd/`.

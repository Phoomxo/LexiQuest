# LexiQuest Local AI Analysis Orchestrator

This Windows-only developer tool sends a bounded, secret-scanned set of LexiQuest source excerpts directly to MaxPlus for read-only analysis. GPT is the primary analyst and Claude is an independent reviewer when the task policy requires one.

Configured providers:

- GPT Pro 20x Stable — `gpt-5.6-sol`
- AWS Lite Ultimate routine reviewer — `claude-sonnet-5`
- AWS Lite Ultimate deep reviewer — `claude-opus-5`

The models cannot mutate files and cannot execute tools, shell commands, Git operations, or patches. Their output is parsed as data and is never executed.

## Secret locations

Inference keys are entered through a Windows secure prompt. Never put a key in a command argument, environment file, repository file, report, or chat message.

- `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\gpt-stable.dpapi`
- `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi`

The blobs are encrypted with Windows DPAPI for the current user. ACL inheritance is disabled and access is limited to the current Windows user and `SYSTEM`.

## Install the project runtime once

Install an immutable, hash-verified runtime from a clean reviewed commit:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/install-project-runtime.ps1
```

The stable launcher is `%LOCALAPPDATA%\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1`. It is bound to the LexiQuest Git common directory, so the canonical checkout and registered worktrees can share it while another repository is rejected.

Initialize both encrypted keys through the stable secure prompt:

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path
```

Check local runtime, manifest, project binding, DPAPI blobs, and ACLs without a provider request:

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Health -ProjectRoot (Get-Location).Path
```

Run bounded analysis through the same launcher:

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Analyze -ProjectRoot (Get-Location).Path -Task 'Review provider cancellation' -ChangedFiles
```

## Initialize or rotate keys

From the repository root, initialize both keys interactively:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/initialize-secrets.ps1
```

To rotate one provider, rerun initialization for that provider:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/initialize-secrets.ps1 -Provider GptStable
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/initialize-secrets.ps1 -Provider ClaudeReviewer
```

After runtime installation, rotate through the stable launcher:

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path -Provider GptStable
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path -Provider ClaudeReviewer
```

Initialization validates the `ccsk-` inference-key shape, active account, positive credit, optional spend-cap state, and exact configured models before atomically replacing the previous blob. The Claude key must expose both `claude-sonnet-5` and `claude-opus-5` in one authenticated catalog. MaxPlus `limit_usd: null` is accepted as an unlimited key; an exhausted finite cap is rejected. A failed validation or probe leaves the previous key unchanged. `ccmk-` management tokens are rejected locally.

## Run analysis

Analyze changed tracked files, which is also the default scope:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/invoke-analysis.ps1 -Task "Review provider cancellation" -ChangedFiles
```

Analyze explicit files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/invoke-analysis.ps1 -Task "Review account conversion" -Path lib/features/account/application/account_use_cases.dart,test/features/account/account_use_cases_test.dart
```

Keep the result in process output without creating a report:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/invoke-analysis.ps1 -Task "Summarize focused tests" -ChangedFiles -NoReport
```

Automatic effort routing uses the task risk and file count. Manual values are `Low`, `Medium`, `High`, `XHigh`, `ExtraHigh`, `ExtendedHigh`, `Max`, and critical-adjudication-only `Ultra`. Unsupported effort or model values stop the run. There is no automatic retry and no automatic fallback, silent downgrade, model substitution, or third-provider call.

| Classification | Claude reviewer |
|---|---|
| `simple` | None |
| `focusedPackage`, `failedOrMultiFile` | `claude-sonnet-5` |
| `architectureSensitive`, `releaseBlocker`, `criticalDisagreement` | `claude-opus-5` |

Manual `XHigh` or `Max` upgrades a routine review to Opus. A manual value cannot lower architecture, database, security, authentication, credential, secret, migration, privacy, release, or critical-disagreement safety floors. Model selection occurs before the request; provider failure never switches models.

`-NoReviewer` is rejected for architecture, concurrency, database, security, authentication, credential, secret, migration, privacy, critical disagreement, and release-blocker work. Requests are bounded to 20 files, 96,000 characters, and 256 KiB per file. The denylist and embedded-key scan always win over explicit paths.

## Run the bounded provider smoke

The smoke sends only the fixed non-project prompt defined in the tool. It performs GPT Low, Sonnet Low, and Opus High generation, with one Claude account check and one model discovery covering both reviewer models. Every operation has zero retries:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/test-provider-smoke.ps1
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Smoke -ProjectRoot (Get-Location).Path
```

After smoke passes, certify GPT efforts plus Sonnet Low/Medium/High and Opus High/XHigh/Max with the same fixed prompt and one request per model/effort:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/test-provider-smoke.ps1 -CertifyEfforts
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command CertifyEfforts -ProjectRoot (Get-Location).Path
```

The support matrix records each value as `supported` or `unsupportedEffort`. Certification never retries or downgrades. An unsupported effort stops later probes for that exact model without stopping the other model's independent sequence.

Smoke evidence under `build/ai-analysis/smoke/` contains provider, model, effort, latency, token counts, provider-reported cost when present, outcome, and UTC time only. It never contains prompts, responses, source, identity, authorization headers, API keys, or DPAPI blobs.

## Reports and retention

Successful analyses write allowlisted, redacted reports under `build/ai-analysis/`. Raw provider responses and source excerpts are never persisted. Valid run directories expire after 14 days. `-NoReport` creates no run directory.

## Remove keys and revoke remote access

Remove both local encrypted blobs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/remove-secrets.ps1 -Provider All
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Remove -ProjectRoot (Get-Location).Path -Provider All
```

Deleting a local DPAPI blob does not revoke the remote key. Revoke or rotate the remote key separately in MaxPlus. Local removal never deletes the parent directory or any unknown file.

## Privacy and failure behavior

Prompts go directly to the selected MaxPlus pool. The tool sends only the bounded context shown by its scope rules. Every HTTP operation makes one attempt. Redirects, non-MaxPlus hosts, unsafe paths, malformed responses, invalid credentials, quota, rate limits, timeouts, cancellation, unavailable providers, unsupported models, and unsupported effort values stop immediately without a partial report.

## Update, rollback, and new sessions

To update, review and check out the desired commit, then rerun `install-project-runtime.ps1`. The installer copies only its fixed allowlist, verifies SHA-256 hashes, and atomically activates that immutable commit.

To rollback, check out the prior reviewed commit and rerun the same installer. The prior immutable runtime remains available and the active manifest is replaced atomically.

A new chat or Codex CLI session runs only `-Command Health`. It never repeats provider smoke or effort certification merely because a session restarted. Real smoke and certification are explicit owner-cost gates.

# Local AI Analysis Orchestrator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows-only, developer-facing, read-only analysis orchestrator that uses MaxPlus GPT Pro 20x Stable as primary analyst and routes AWS Lite Ultimate Claude Sonnet 5 or Opus 5 as the independent reviewer while keeping both inference keys DPAPI-encrypted outside Git.

**Architecture:** A small set of dot-sourced PowerShell 5.1 libraries owns configuration, effort policy, DPAPI storage, bounded context construction, provider HTTP calls, review/adjudication, and redacted report persistence. The command entry points compose those pure boundaries and inject HTTP transports in tests, so the normal test suite never needs a real key or network access. External models receive text-only bounded context and never receive filesystem, shell, Git, or patch tools.

**Tech Stack:** Windows PowerShell 5.1, Windows DPAPI via `ConvertFrom-SecureString`, .NET `HttpClient`, JSON configuration, dependency-free PowerShell test scripts, Git, Gitleaks.

## Global Constraints

- This feature is developer tooling only; it must not change Flutter runtime code, application dependencies, database schema, release evidence schema, or generated Flutter files.
- Primary pool is `GPT Pro 20x Stable`, base URL is exactly `https://api.maxplus-ai.cc/gpt-pro-20x-stable`, model is exactly `gpt-5.6-sol`, and generation uses `/v1/responses` with `stream: true` and `store: false`.
- Reviewer pool is `AWS Lite Ultimate`, base URL is exactly `https://api.maxplus-ai.cc/aws-lite-ultimate`, routine model is exactly `claude-sonnet-5`, deep/high-risk model is exactly `claude-opus-5`, and generation uses `/v1/messages` with adaptive thinking and `output_config.effort`.
- Only `ccsk-` inference keys matching `^ccsk-[a-f0-9]{64}$` are accepted. `ccmk-` management tokens are rejected before network access.
- Secrets live only under `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\` and are encrypted for the current Windows user with DPAPI. They never appear in Git, logs, reports, exception text, or process arguments.
- There is no automatic retry, automatic fallback, silent effort downgrade, silent model substitution, or third-provider call.
- Default source scope is changed tracked files. Explicit paths must remain inside the repository. Maximum scope is 20 files, 96,000 UTF-8 characters, and 256 KiB per file.
- The denylist in the approved specification always wins over explicit paths. Embedded MaxPlus, OpenAI, Anthropic, and Gemini key shapes block the request.
- GPT effort levels are `low`, `medium`, `high`, `xhigh`, `max`, and `ultra`; Claude effort levels are `low`, `medium`, `high`, `xhigh`, and `max`.
- Every non-default effort must be proven by a bounded request or reported as `unsupportedEffort`; never downgrade automatically.
- Raw provider responses stay in memory. Persisted reports contain only redacted findings and metadata and expire after 14 days.
- All automated tests use fake keys and injected HTTP transports. Real-provider smoke is a separate explicit command with fixed non-project text and exactly one request per operation.
- Work in the existing isolated worktree `C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture`; stage only files named in the current task because the worktree contains unrelated P8-H changes.
- Do not use Codex Security or repository-wide automated analysis. Verification is bounded to this tool, its docs, Gitleaks, and manual diff review.

---

## File Map

| Path | Responsibility |
|---|---|
| `tool/ai-analysis/config.json` | Non-secret provider, limit, denylist, extension, retention, and effort configuration |
| `tool/ai-analysis/lib/config.ps1` | Load and validate immutable configuration |
| `tool/ai-analysis/lib/effort-router.ps1` | Deterministic task classification, effort floors, output limits, and reviewer policy |
| `tool/ai-analysis/lib/secret-store.ps1` | SecureString validation, DPAPI read/write/remove, atomic replacement, and ACL restriction |
| `tool/ai-analysis/lib/context-builder.ps1` | Repository confinement, changed-file discovery, denylist checks, text limits, line numbering, and embedded-secret scanning |
| `tool/ai-analysis/lib/maxplus-client.ps1` | Exact-host HTTP transport, `/v1/me`, model discovery, GPT Responses, Claude Messages, response normalization, errors, timeout, and cancellation |
| `tool/ai-analysis/lib/reviewer.ps1` | Structured prompts, primary/reviewer sequencing, agreement check, and one-shot critical adjudication |
| `tool/ai-analysis/lib/report-writer.ps1` | Redaction, metadata projection, run-directory naming, atomic report writes, and 14-day cleanup |
| `tool/ai-analysis/initialize-secrets.ps1` | Interactive validate/probe/atomic-save workflow for both keys |
| `tool/ai-analysis/remove-secrets.ps1` | Explicit local blob removal with remote-revocation warning |
| `tool/ai-analysis/invoke-analysis.ps1` | Public analysis command and composition root |
| `tool/ai-analysis/test-provider-smoke.ps1` | Explicit, bounded real-provider smoke with fixed non-project text and metadata-only evidence |
| `tool/ai-analysis/README.md` | Setup, operation, effort policy, privacy boundary, smoke procedure, and troubleshooting |
| `tool/ai-analysis/tests/test-helpers.ps1` | Dependency-free assertions, temp-directory helper, fake SecureString helper, and test runner bookkeeping |
| `tool/ai-analysis/tests/effort-router.tests.ps1` | Policy and override coverage |
| `tool/ai-analysis/tests/secret-store.tests.ps1` | Key validation, current-user DPAPI round-trip, replacement, and removal coverage |
| `tool/ai-analysis/tests/context-builder.tests.ps1` | Scope, traversal, denylist, binary, size, count, character, and secret-pattern coverage |
| `tool/ai-analysis/tests/maxplus-client.tests.ps1` | Request shape, host, account caps, model validation, error taxonomy, no-retry, and response normalization |
| `tool/ai-analysis/tests/orchestrator.tests.ps1` | Reviewer policy, cancellation, disagreement, adjudication, and mutation-boundary coverage |
| `tool/ai-analysis/tests/report-writer.tests.ps1` | Redaction, permitted fields, retention, atomic output, and `-NoReport` coverage |
| `tool/ai-analysis/tests/run-tests.ps1` | Runs every local test exactly once and propagates the first failure |

## Stable Interfaces

The implementation must preserve these signatures across tasks:

```powershell
Get-AiAnalysisConfig -ConfigPath <string> -> PSCustomObject
Resolve-AiAnalysisPolicy -Task <string> -FileCount <int> -RequestedEffort <Auto|Low|Medium|High|XHigh|ExtraHigh|ExtendedHigh|Max|Ultra> -NoReviewer:<bool> -> PSCustomObject
Test-AiAnalysisInferenceKey -SecureKey <SecureString> -> bool
Get-AiAnalysisSecretPath -SecretId <gpt-stable|claude-reviewer> -> string
Save-AiAnalysisSecret -SecretId <string> -SecureKey <SecureString> -DestinationRoot <string> -> void
Read-AiAnalysisSecret -SecretId <string> -DestinationRoot <string> -> SecureString
Remove-AiAnalysisSecret -SecretId <string> -DestinationRoot <string> -> bool
New-AiAnalysisContext -RepositoryRoot <string> -Config <object> -Paths <string[]> -ChangedFiles:<bool> -> PSCustomObject
Invoke-MaxPlusRequest -Provider <object> -Route <string> -Method <string> -SecureKey <SecureString> -Body <object> -TimeoutSeconds <int> -CancellationToken <CancellationToken> -Transport <scriptblock> -> object
Test-MaxPlusCredential -Provider <object> -SecureKey <SecureString> -TimeoutSeconds <int> -Transport <scriptblock> -> PSCustomObject
Invoke-GptAnalysis -Provider <object> -SecureKey <SecureString> -Prompt <string> -Effort <string> -MaxOutputTokens <int> -TimeoutSeconds <int> -Transport <scriptblock> -> PSCustomObject
Invoke-ClaudeReview -Provider <object> -SecureKey <SecureString> -Prompt <string> -Effort <string> -MaxOutputTokens <int> -TimeoutSeconds <int> -Transport <scriptblock> -> PSCustomObject
Invoke-AiAnalysisReview -Task <string> -Context <object> -Policy <object> -PrimaryInvoker <scriptblock> -ReviewerInvoker <scriptblock> -AdjudicatorInvoker <scriptblock> -> PSCustomObject
Write-AiAnalysisReport -Result <object> -Scope <object> -RepositoryRoot <string> -OutputRoot <string> -RetentionDays <int> -NoReport:<bool> -> PSCustomObject
```

### Task 1: Configuration and deterministic effort routing

**Files:**
- Create: `tool/ai-analysis/config.json`
- Create: `tool/ai-analysis/lib/config.ps1`
- Create: `tool/ai-analysis/lib/effort-router.ps1`
- Create: `tool/ai-analysis/tests/test-helpers.ps1`
- Create: `tool/ai-analysis/tests/effort-router.tests.ps1`
- Create: `tool/ai-analysis/tests/run-tests.ps1`

**Interfaces:**
- Consumes: No earlier feature interfaces.
- Produces: `Get-AiAnalysisConfig`, `Resolve-AiAnalysisPolicy`, and the shared dependency-free test harness.

- [ ] **Step 1: Write the failing routing tests**

Create tests that assert the six task classes and their exact provider policies, including the forbidden reviewer bypass:

```powershell
$release = Resolve-AiAnalysisPolicy -Task 'Release blocker: migration data loss' -FileCount 3 -RequestedEffort Auto
Assert-Equal 'releaseBlocker' $release.Classification 'release classification'
Assert-Equal 'max' $release.GptEffort 'release GPT effort'
Assert-Equal 'xhigh' $release.ClaudeEffort 'release reviewer effort'
Assert-True $release.ReviewerRequired 'release reviewer required'
Assert-Throws { Resolve-AiAnalysisPolicy -Task 'Privacy architecture review' -FileCount 2 -RequestedEffort Low -NoReviewer } 'reviewerRequired'
$simple = Resolve-AiAnalysisPolicy -Task 'Summarize these test names' -FileCount 1 -RequestedEffort Auto
Assert-Equal 'low' $simple.GptEffort 'simple GPT effort'
Assert-False $simple.ReviewerRequired 'simple skips reviewer'
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1`

Expected: non-zero exit with `Resolve-AiAnalysisPolicy is not recognized`.

- [ ] **Step 3: Add validated non-secret configuration**

`config.json` must declare the two exact providers, their auth style and routes, `store: false`, exact effort/output-token maps, 20/96000/262144 context limits, allowed source extensions, the hard denylist, 14-day retention, and timeout defaults. `Get-AiAnalysisConfig` must reject any provider whose URI is not HTTPS or whose host is not exactly `api.maxplus-ai.cc`:

```powershell
function Get-AiAnalysisConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ConfigPath)
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding utf8 | ConvertFrom-Json
    foreach ($provider in @($config.providers.gptStable, $config.providers.claudeReviewer)) {
        $uri = [Uri]$provider.baseUrl
        if ($uri.Scheme -ne 'https' -or $uri.Host -cne 'api.maxplus-ai.cc' -or -not [string]::IsNullOrEmpty($uri.Query)) {
            throw 'unsafeEndpoint'
        }
    }
    return $config
}
```

- [ ] **Step 4: Implement policy classification and override validation**

Use ordered classification (`releaseBlocker`, `architectureSensitive`, `failedOrMultiFile`, `focusedPackage`, `simple`) and return a policy object containing `Classification`, `GptEffort`, `ClaudeEffort`, `ClaudeModel`, `ReviewerRequired`, `GptMaxOutputTokens`, and `ClaudeMaxOutputTokens`. `FileCount -ge 2` classifies as `failedOrMultiFile` unless a higher-risk task keyword wins. `focusedPackage` and `failedOrMultiFile` use `claude-sonnet-5`; architecture, database, security, authentication, credential, secret, migration, privacy, release, and critical-disagreement work use `claude-opus-5`. Manual XHigh/Max upgrades routine work to Opus, but no manual effort may lower a sensitive safety floor. `-NoReviewer` must throw `reviewerRequired` for sensitive work. Normalize `XHigh`, `ExtraHigh`, and `ExtendedHigh` to API value `xhigh`; display that rank as `ExtraHigh` for GPT and `ExtendedHigh` for Claude. `Ultra` is legal only for a critical disagreement/adjudication task and pairs GPT `ultra` with Claude `max`.

- [ ] **Step 5: Add the fail-fast test runner and confirm GREEN**

The runner must sort `*.tests.ps1`, exclude itself and `test-helpers.ps1`, execute one file at a time, and stop on the first non-zero exit.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1`

Expected: `Effort router tests: ... passed, 0 failed` and exit 0.

- [ ] **Step 6: Commit only Task 1 files**

```powershell
git add -- tool/ai-analysis/config.json tool/ai-analysis/lib/config.ps1 tool/ai-analysis/lib/effort-router.ps1 tool/ai-analysis/tests/test-helpers.ps1 tool/ai-analysis/tests/effort-router.tests.ps1 tool/ai-analysis/tests/run-tests.ps1
git commit -m "feat(ai-analysis): add provider config and effort routing"
```

### Task 2: Current-user DPAPI secret store

**Files:**
- Create: `tool/ai-analysis/lib/secret-store.ps1`
- Create: `tool/ai-analysis/remove-secrets.ps1`
- Create: `tool/ai-analysis/tests/secret-store.tests.ps1`

**Interfaces:**
- Consumes: Secret IDs from `config.json`.
- Produces: `Test-AiAnalysisInferenceKey`, `Get-AiAnalysisSecretPath`, `Save-AiAnalysisSecret`, `Read-AiAnalysisSecret`, and `Remove-AiAnalysisSecret`.

- [ ] **Step 1: Write failing DPAPI and validation tests**

Use a unique temp directory and fake `ccsk-` value. Assert a round trip returns an equivalent SecureString, `ccmk-` and malformed keys fail before any probe, an atomic replacement changes the decrypted value, and removal returns true once then false:

```powershell
$first = ConvertTo-SecureString ('ccsk-' + ('a' * 64)) -AsPlainText -Force
$second = ConvertTo-SecureString ('ccsk-' + ('b' * 64)) -AsPlainText -Force
Assert-True (Test-AiAnalysisInferenceKey -SecureKey $first) 'valid inference key'
Assert-False (Test-AiAnalysisInferenceKey -SecureKey (ConvertTo-SecureString ('ccmk-' + ('a' * 64)) -AsPlainText -Force)) 'management token rejected'
Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $first -DestinationRoot $tempRoot
Assert-SecureStringEqual $first (Read-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot) 'DPAPI round trip'
Save-AiAnalysisSecret -SecretId gpt-stable -SecureKey $second -DestinationRoot $tempRoot
Assert-SecureStringEqual $second (Read-AiAnalysisSecret -SecretId gpt-stable -DestinationRoot $tempRoot) 'atomic replacement'
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/secret-store.tests.ps1`

Expected: non-zero exit because `secret-store.ps1` does not exist.

- [ ] **Step 3: Implement key validation with bounded plaintext lifetime**

Convert the SecureString through a BSTR only inside `try/finally`, match `^ccsk-[a-f0-9]{64}$`, never return the plaintext, and always call `ZeroFreeBSTR`:

```powershell
function Test-AiAnalysisInferenceKey {
    param([Parameter(Mandatory)][Security.SecureString]$SecureKey)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) -cmatch '^ccsk-[a-f0-9]{64}$'
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}
```

- [ ] **Step 4: Implement DPAPI persistence, ACLs, and atomic replacement**

Default the root to `Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis\secrets'`; accept only the two known IDs; serialize via `ConvertFrom-SecureString`; write a same-directory temporary file; restrict inheritance and allow only the current user SID and `S-1-5-18` (`SYSTEM`); use `File.Replace` when the destination exists and `File.Move` otherwise; clean temporary and backup files in `finally`. Reading must use `ConvertTo-SecureString` and must never echo the blob.

- [ ] **Step 5: Add explicit removal command**

`remove-secrets.ps1` must accept `-Provider All|GptStable|ClaudeReviewer`, delete only resolved known blob paths, and print: `Local DPAPI blob removed; revoke or rotate the remote key in MaxPlus separately.` It must not recurse or delete the parent directory.

- [ ] **Step 6: Run focused tests and confirm GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/secret-store.tests.ps1`

Expected: DPAPI tests pass with zero failures and neither fake key nor DPAPI blob is printed.

- [ ] **Step 7: Commit only Task 2 files**

```powershell
git add -- tool/ai-analysis/lib/secret-store.ps1 tool/ai-analysis/remove-secrets.ps1 tool/ai-analysis/tests/secret-store.tests.ps1
git commit -m "feat(ai-analysis): add DPAPI secret storage"
```

### Task 3: Bounded and secret-scanned repository context

**Files:**
- Create: `tool/ai-analysis/lib/context-builder.ps1`
- Create: `tool/ai-analysis/tests/context-builder.tests.ps1`

**Interfaces:**
- Consumes: `context` and `secretPatterns` from `config.json`.
- Produces: `New-AiAnalysisContext` returning `Files`, `Text`, `CharacterCount`, and `Mode`.

- [ ] **Step 1: Write failing confinement and secret-scan tests**

Create a temporary Git repository containing allowed source files, a denylisted `.env`, a 256-KiB-plus file, a binary file, and a source file containing each configured key signature. Assert explicit outside paths, `..` traversal, denied names, binaries, oversized files, more than 20 files, more than 96,000 characters, and embedded secrets fail with stable category names. Assert changed-file mode excludes untracked files and line-numbers accepted excerpts.

```powershell
$context = New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/sample.dart')
Assert-Equal @('lib/sample.dart') $context.Files 'explicit source file'
Assert-Match '^--- FILE: lib/sample\.dart ---\r?\n\s*1 \| ' $context.Text 'line numbered excerpt'
Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('..\outside.txt') } 'outsideRepository'
Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('.env') } 'denylistedPath'
Assert-Throws { New-AiAnalysisContext -RepositoryRoot $repo -Config $config -Paths @('lib/leak.dart') } 'embeddedSecret'
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/context-builder.tests.ps1`

Expected: non-zero exit because `New-AiAnalysisContext` is missing.

- [ ] **Step 3: Implement canonical path confinement and file expansion**

Resolve the repository root and every candidate with `GetFullPath`; require the candidate to start with the root plus directory separator using `OrdinalIgnoreCase`; directories expand recursively only over configured extensions; normalize report paths to `/`; sort and deduplicate. For `-ChangedFiles`, run `git -C <root> diff --name-only --diff-filter=ACMRTUXB HEAD --`, which includes staged and unstaged tracked changes and excludes untracked files.

- [ ] **Step 4: Enforce denylist and content limits before prompt creation**

Apply denylist patterns before reading. Reject file size above 262,144 bytes. Detect binary files by a NUL byte in the first 8 KiB. Decode UTF-8 strictly. Stop before exceeding 20 files or 96,000 characters. Scan content with named rules for MaxPlus `ccsk-`, MaxPlus management `ccmk-`, OpenAI `sk-`, Anthropic `sk-ant-`, and Gemini `AIza`; errors contain only the relative path and rule ID, never the matching value.

- [ ] **Step 5: Build deterministic line-numbered context and confirm GREEN**

Each accepted file starts with `--- FILE: <relative-path> ---`; each content line is formatted as `<line-number padded to 6> | <text>`. No raw absolute paths are included.

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/context-builder.tests.ps1`

Expected: all context tests pass and no fixture secret value appears in output.

- [ ] **Step 6: Commit only Task 3 files**

```powershell
git add -- tool/ai-analysis/lib/context-builder.ps1 tool/ai-analysis/tests/context-builder.tests.ps1
git commit -m "feat(ai-analysis): add bounded project context"
```

### Task 4: Exact-host MaxPlus client and interactive key initialization

**Files:**
- Create: `tool/ai-analysis/lib/maxplus-client.ps1`
- Create: `tool/ai-analysis/initialize-secrets.ps1`
- Create: `tool/ai-analysis/tests/maxplus-client.tests.ps1`

**Interfaces:**
- Consumes: Validated provider objects from `Get-AiAnalysisConfig` and SecureStrings from `secret-store.ps1`.
- Produces: `Invoke-MaxPlusRequest`, `Test-MaxPlusCredential`, `Invoke-GptAnalysis`, and `Invoke-ClaudeReview`.

- [ ] **Step 1: Write failing HTTP-contract tests with an injected transport**

The fake transport records every request and returns fixture JSON. Cover exact host and scheme rejection, `/v1/me` cap checks, `/v1/models` exact model presence, GPT `store: false`, GPT reasoning effort/output cap, Claude adaptive thinking/effort/output cap, auth header style, normalized token/cost metadata, timeout, cancellation, rate limit, invalid key, quota, malformed response, unavailable provider, unsupported model, unsupported effort, and exactly one transport invocation on failure.

```powershell
$result = Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort high -MaxOutputTokens 8192 -TimeoutSeconds 30 -Transport $transport
Assert-Equal 1 $requests.Count 'one GPT request'
Assert-False $requests[0].Body.store 'Responses storage disabled'
Assert-True $requests[0].Body.stream 'Responses streaming required by MaxPlus'
Assert-Equal 'high' $requests[0].Body.reasoning.effort 'GPT effort'
Assert-Equal 8192 $requests[0].Body.max_output_tokens 'GPT output cap'

$review = Invoke-ClaudeReview -Provider $config.providers.claudeReviewer -SecureKey $fakeKey -Prompt 'fixed' -Effort xhigh -MaxOutputTokens 65536 -TimeoutSeconds 30 -Transport $transport
Assert-Equal 'adaptive' $requests[1].Body.thinking.type 'adaptive thinking'
Assert-Equal 'xhigh' $requests[1].Body.output_config.effort 'Claude effort'
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/maxplus-client.tests.ps1`

Expected: non-zero exit because the client functions are missing.

- [ ] **Step 3: Implement one-shot request transport and error taxonomy**

`Invoke-MaxPlusRequest` must reconstruct and validate the route URI from the configured base URL, accept only the exact host and HTTPS, create the auth header inside a bounded BSTR `try/finally`, and call the injected transport once. The default transport uses one `HttpClient.SendAsync` call with a linked cancellation-token source and timeout; it disposes request, response, client, content, and token sources in `finally`, then clears header/key variables. Map status 400 effort errors to `unsupportedEffort`, 400 model errors to `unsupportedModel`, 401/403 to `invalidKey`, 408 or an expired timeout token to `timeout`, 429 rate-limit versus quota payloads to `rateLimit` or `quota`, 5xx to `unavailable`, caller cancellation to `cancelled`, and invalid JSON/shape to `malformedResponse`.

- [ ] **Step 4: Implement startup account and model gates**

`Test-MaxPlusCredential` makes exactly one `/v1/me` call and one `/v1/models` call. It discards identity fields immediately, rejects inactive keys, non-positive credit, malformed cap data, or an exhausted finite daily/lifetime cap, accepts the documented `limit_usd: null` state as unlimited, and requires an exact configured model ID. It returns only `Active`, `CreditPositive`, `CapKind`, `CapRemaining`, and `ModelAvailable`.

- [ ] **Step 5: Implement provider-specific generation and normalization**

GPT sends a Responses-compatible body with `model`, structured `input`, `stream = $true`, `store = $false`, `reasoning.effort`, and `max_output_tokens`, then projects only the single `response.completed.response` envelope from the SSE stream. Claude sends an Anthropic Messages-compatible body with `model`, `messages`, `thinking.type = 'adaptive'`, `output_config.effort`, and `max_tokens`. Both parsers return only:

```powershell
[pscustomobject]@{
    Conclusion = [string]$parsed.conclusion
    Findings = @($parsed.findings)
    Usage = [pscustomobject]@{
        InputTokens = <nullable int>
        OutputTokens = <nullable int>
        TotalTokens = <nullable int>
        CachedTokens = <nullable int>
        ProviderReportedCost = <number or 'unknown'>
    }
}
```

The prompts require strict JSON with finding fields `id`, `severity`, `category`, `message`, `file`, `line`, and `evidence`. Free text or missing required fields returns `malformedResponse`.

- [ ] **Step 6: Implement interactive validate-before-write initialization**

`initialize-secrets.ps1` accepts no key parameter. For each selected provider it prompts with `Read-Host -AsSecureString`, validates shape locally, calls `Test-MaxPlusCredential`, then calls `Save-AiAnalysisSecret`. A failed shape, account gate, or model probe leaves the previous blob unchanged. It prints provider/model success only, never credit, cap, identity, key, auth headers, or blobs.

- [ ] **Step 7: Run focused tests and confirm GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/maxplus-client.tests.ps1`

Expected: all mocked client tests pass, request counts prove zero retries, and no fake key appears in captured console output.

- [ ] **Step 8: Commit only Task 4 files**

```powershell
git add -- tool/ai-analysis/lib/maxplus-client.ps1 tool/ai-analysis/initialize-secrets.ps1 tool/ai-analysis/tests/maxplus-client.tests.ps1
git commit -m "feat(ai-analysis): add bounded MaxPlus client"
```

### Task 5: Primary analysis, independent review, and one-shot adjudication

**Files:**
- Create: `tool/ai-analysis/lib/reviewer.ps1`
- Create: `tool/ai-analysis/tests/orchestrator.tests.ps1`

**Interfaces:**
- Consumes: `New-AiAnalysisContext`, `Resolve-AiAnalysisPolicy`, `Invoke-GptAnalysis`, and `Invoke-ClaudeReview` through injected invokers.
- Produces: `Invoke-AiAnalysisReview` and its structured workflow result.

- [ ] **Step 1: Write failing call-sequencing tests**

Test simple work calls GPT once and Claude zero times; focused source behavior calls each once; architecture/release always calls both; `-NoReviewer` cannot bypass mandatory review; provider failures stop immediately; cancellation writes nothing; agreement does not adjudicate; a critical disagreement invokes GPT adjudicator exactly once with only the two conclusions and cited references; noncritical disagreement remains visible without adjudication.

```powershell
$result = Invoke-AiAnalysisReview -Task 'Review race condition' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator
Assert-Equal 1 $calls.Primary 'one primary call'
Assert-Equal 1 $calls.Reviewer 'one reviewer call'
Assert-Equal 1 $calls.Adjudicator 'one critical adjudication'
Assert-NotMatch 'source body sentinel' $capturedAdjudicationPrompt 'adjudication excludes source context'
Assert-Match 'lib/sample.dart:12' $capturedAdjudicationPrompt 'adjudication keeps cited reference'
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1`

Expected: non-zero exit because `Invoke-AiAnalysisReview` is missing.

- [ ] **Step 3: Implement immutable prompts and structured findings**

The primary system instruction states: analyze only supplied excerpts, do not request tools, do not emit commands or patches, cite only supplied paths/lines, and return strict JSON. The reviewer receives the same bounded context plus the primary conclusion/findings and must return `agreement`, `conclusion`, and structured findings. Reject any finding that cites a file not present in `Context.Files` or a non-positive line number.

- [ ] **Step 4: Implement deterministic agreement and critical-conflict rules**

Treat the review as agreed only when reviewer `agreement` is `agree` and there is no reviewer finding with severity `critical` or `high` contradicting a primary finding ID. Trigger adjudication only for a `critical` contradiction. The adjudication prompt contains provider conclusions and `file:line` references only; it never contains source excerpts. Call adjudication once with GPT `ultra` and never fall back if it fails.

- [ ] **Step 5: Preserve the mutation boundary**

Reject structured results containing tool calls, shell requests, patch blocks, or instructions to stage/commit/push as `unsafeModelOutput`. Do not interpret any provider string as executable input. Return a plain result object with `Outcome`, `Agreement`, `Primary`, `Review`, `Adjudication`, and `ProviderCalls`.

- [ ] **Step 6: Run focused tests and confirm GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1`

Expected: all sequencing and mutation-boundary tests pass with exact call counts and no retry.

- [ ] **Step 7: Commit only Task 5 files**

```powershell
git add -- tool/ai-analysis/lib/reviewer.ps1 tool/ai-analysis/tests/orchestrator.tests.ps1
git commit -m "feat(ai-analysis): add independent review pipeline"
```

### Task 6: Redacted reporting and retention

**Files:**
- Create: `tool/ai-analysis/lib/report-writer.ps1`
- Create: `tool/ai-analysis/tests/report-writer.tests.ps1`

**Interfaces:**
- Consumes: Structured workflow result and scope objects only; never raw provider responses.
- Produces: `Write-AiAnalysisReport` and `Remove-ExpiredAiAnalysisReports`.

- [ ] **Step 1: Write failing projection, redaction, and retention tests**

Use a result fixture containing fake keys, an authorization header, a DPAPI blob, raw source, raw response, identity fields, and permitted findings. Assert the forbidden values and property names never appear in `report.md` or `metadata.json`; provider/model/effort/latency/token/provider-reported-cost metadata does appear; absent cost is exactly `unknown`; `-NoReport` creates no directory; expired valid run directories are deleted while unrelated directories remain.

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/report-writer.tests.ps1`

Expected: non-zero exit because `Write-AiAnalysisReport` is missing.

- [ ] **Step 3: Implement allowlist-only report projection and redaction**

Construct new report/metadata objects field by field. Never serialize the input result wholesale. Allowed metadata fields are task, relative scope paths, commit SHA, dirty flag, provider, model, effort, latency, token counts, provider-reported cost or `unknown`, agreement, outcome, and UTC timestamps. Allowed report fields are task, scope paths, redacted structured findings, agreement, and final conclusion. Replace any detected key shape with `[REDACTED:<rule>]` and reject authorization/DPAPI/source/raw properties before writing.

- [ ] **Step 4: Implement atomic output and 14-day retention**

Generate names as `<yyyyMMddTHHmmssZ>-<8 lowercase hex>`, write `report.md.tmp` and `metadata.json.tmp`, then move both into the run directory. On failure, remove only that newly created run directory. Cleanup considers only directories matching `^\d{8}T\d{6}Z-[a-f0-9]{8}$` and removes those older than the configured UTC cutoff.

- [ ] **Step 5: Run focused tests and confirm GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/report-writer.tests.ps1`

Expected: report tests pass, forbidden fixture values are absent, and retention does not touch unrelated directories.

- [ ] **Step 6: Commit only Task 6 files**

```powershell
git add -- tool/ai-analysis/lib/report-writer.ps1 tool/ai-analysis/tests/report-writer.tests.ps1
git commit -m "feat(ai-analysis): add redacted local reports"
```

### Task 7: Composition root and bounded real-provider smoke

**Files:**
- Create: `tool/ai-analysis/invoke-analysis.ps1`
- Create: `tool/ai-analysis/test-provider-smoke.ps1`
- Modify: `tool/ai-analysis/tests/orchestrator.tests.ps1`

**Interfaces:**
- Consumes: Every stable library interface.
- Produces: The two supported public execution commands.

- [ ] **Step 1: Add failing command-contract tests**

Parse both scripts and assert the public parameter sets. Execute `invoke-analysis.ps1` with injected fake transports in a temp Git repository and assert changed-file and explicit-path modes, effort override, `-NoReviewer` enforcement, `-NoReport`, timeout propagation, first-failure stop, and report creation only after success. Assert `test-provider-smoke.ps1` uses fixed non-project prompt text and cannot accept `-Task` or `-Path`.

- [ ] **Step 2: Run orchestrator tests and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1`

Expected: non-zero exit because the entry-point scripts are missing.

- [ ] **Step 3: Implement `invoke-analysis.ps1` as the only composition root**

Expose:

```powershell
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Task,
    [string[]]$Path = @(),
    [switch]$ChangedFiles,
    [ValidateSet('Auto','Low','Medium','High','XHigh','ExtraHigh','ExtendedHigh','Max','Ultra')][string]$Effort = 'Auto',
    [switch]$NoReviewer,
    [switch]$NoReport,
    [ValidateRange(5,600)][int]$TimeoutSeconds = 120
)
```

Reject using `-Path` and `-ChangedFiles` together. With neither, use changed tracked files. Load config, clean expired reports, build/scan context, resolve policy using `Context.Files.Count`, decrypt only required keys, run account/model gates, execute review, write an allowlisted report, clean expired reports again, and clear SecureString references in `finally`. Stop at the first failure category and never create a partial report.

- [ ] **Step 4: Implement explicit real-provider smoke**

The smoke command loads both DPAPI blobs, performs one account gate and one model discovery per key, one GPT Low generation, and one Claude Low generation using the literal prompt `Return JSON with conclusion "ok" and an empty findings array.` It performs zero retries, sends no repository content, and persists only provider/model/effort/latency/token/cost/outcome metadata under `build/ai-analysis/smoke/`.

- [ ] **Step 5: Run all mocked tests and confirm GREEN**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1`

Expected: every test file runs once, all tests pass, no network connection occurs, and no fake key is printed or persisted.

- [ ] **Step 6: Commit only Task 7 files**

```powershell
git add -- tool/ai-analysis/invoke-analysis.ps1 tool/ai-analysis/test-provider-smoke.ps1 tool/ai-analysis/tests/orchestrator.tests.ps1
git commit -m "feat(ai-analysis): add analysis entry points"
```

### Task 8: Operator documentation and bounded acceptance gate

**Files:**
- Create: `tool/ai-analysis/README.md`
- Modify only if needed: `.gitignore`
- Modify: `tool/ai-analysis/tests/run-tests.ps1`

**Interfaces:**
- Consumes: Final command behavior.
- Produces: Owner-operable setup/rotation/removal/smoke workflow and one bounded verification command.

- [ ] **Step 1: Write README contract checks before documentation**

Extend the runner with a documentation test that requires the README to contain both external DPAPI paths, both pool/model pairs, initialization, rotation, removal, normal analysis, explicit path analysis, `-NoReport`, smoke, no-retry/no-fallback, local-versus-remote revocation, report retention, and the warning that models cannot mutate files or execute tools.

- [ ] **Step 2: Run the documentation test and confirm RED**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1`

Expected: non-zero exit reporting missing `tool/ai-analysis/README.md`.

- [ ] **Step 3: Write the operator README**

Document these exact safe commands without embedding a key:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/initialize-secrets.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/invoke-analysis.ps1 -Task "Review provider cancellation" -ChangedFiles
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/invoke-analysis.ps1 -Task "Review account conversion" -Path lib/features/account/application/account_use_cases.dart -Path test/features/account/account_use_cases_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/test-provider-smoke.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/remove-secrets.ps1 -Provider All
```

Explain that prompts are sent directly to the selected MaxPlus pool; report files are ignored under `build/`; deleting blobs does not revoke remote keys; initialization replaces a key only after successful validation/probe; and unsupported effort/model stops without downgrade.

- [ ] **Step 4: Confirm generated output is ignored**

Run: `git check-ignore -v build/ai-analysis/probe/report.md`

Expected: the existing `/build/` rule matches. Do not modify `.gitignore` if it already matches; if it does not, add only `/build/ai-analysis/`.

- [ ] **Step 5: Run the full bounded tool gate**

Run in this order and stop on the first failure:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1
git diff --check -- tool/ai-analysis .gitignore docs/superpowers/specs/2026-08-01-local-ai-analysis-orchestrator-design.md docs/superpowers/plans/2026-08-01-local-ai-analysis-orchestrator-implementation.md
gitleaks dir tool/ai-analysis --redact --no-banner
git diff --name-only HEAD~8..HEAD --
```

Expected: tests pass; diff check is empty; Gitleaks reports no leaks; changed implementation paths are limited to `tool/ai-analysis/`, this spec/plan, and `.gitignore` only if required. Because unrelated P8-H files were already dirty, do not use a repository-wide clean-worktree assertion.

- [ ] **Step 6: Perform manual safety review**

Confirm every HTTP call has one attempt, every secret conversion has a `finally`, every provider URL is exact-host HTTPS, no command accepts a key string, report serialization is allowlist-only, no model output is executed, and no Flutter/runtime file is part of this feature diff.

- [ ] **Step 7: Commit only Task 8 files**

```powershell
git add -- tool/ai-analysis/README.md tool/ai-analysis/tests/run-tests.ps1
git add -- .gitignore
git commit -m "docs(ai-analysis): add secure operator workflow"
```

Omit `git add -- .gitignore` when the existing `/build/` rule already covers reports.

### Task 9: Owner-entered keys and real smoke evidence

**Files:**
- External secrets created interactively: `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\gpt-stable.dpapi`
- External secrets created interactively: `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi`
- Generated ignored evidence: `build/ai-analysis/smoke/<run-id>/metadata.json`

**Interfaces:**
- Consumes: Owner-provided `ccsk-` inference keys entered only into secure prompts.
- Produces: Authenticated model-discovery and bounded generation evidence without secret or project content.

- [ ] **Step 1: Initialize the two secrets interactively**

Run locally in an interactive terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/initialize-secrets.ps1
```

Expected: each selected model is discovered and each encrypted blob is created outside the repository. The console contains no key, authorization header, account identity, or DPAPI blob.

- [ ] **Step 2: Verify secret locations without reading their contents**

Run:

```powershell
Get-Item "$env:LOCALAPPDATA\LexiQuest\ai-analysis\secrets\gpt-stable.dpapi", "$env:LOCALAPPDATA\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi" | Select-Object Name,Length,LastWriteTimeUtc
```

Expected: exactly two non-empty files. Do not use `Get-Content`.

- [ ] **Step 3: Run one bounded smoke**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/test-provider-smoke.ps1`

Expected: GPT Low and Claude Low both return valid structured `ok` results; exactly one generation request per provider; no repository source sent; metadata-only evidence written.

- [ ] **Step 4: Inspect evidence keys, not values from secrets**

Run:

```powershell
$latest = Get-ChildItem build/ai-analysis/smoke -Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
Get-Content (Join-Path $latest.FullName 'metadata.json') -Raw | ConvertFrom-Json | Select-Object outcome,providers,recordedAtUtc
```

Expected: `outcome` is `pass`, both configured providers/models are present, and the JSON contains no prompt, response, source, identity, authorization, key, or DPAPI fields.

- [ ] **Step 5: Record unsupported effort results without fallback**

Probe each non-default effort with the fixed smoke prompt and the configured output cap. Record a support matrix in metadata. If any value returns `unsupportedEffort`, preserve that result and stop certification of that effort; do not retry with a lower value. This is an environment/provider certification step and does not require a source commit.

## Completion Gate

The feature is complete only when all of the following are true:

- Every mocked test passes in one fail-fast run.
- Gitleaks reports no secret in `tool/ai-analysis/`.
- Both encrypted blobs exist only outside the repository and their ACL is limited to the current user and `SYSTEM`.
- Both configured model IDs pass authenticated discovery.
- GPT Low and Claude Low bounded generation smoke passes with metadata-only evidence.
- Every non-default effort is either proven supported or explicitly recorded as `unsupportedEffort`, with no silent downgrade.
- A normal changed-file analysis produces a redacted report, while `-NoReport` leaves no run directory.
- No provider request is retried, no third provider is called, and no provider output can mutate the workspace or execute a command.
- The feature diff contains no Flutter runtime, database, dependency, release-evidence, or generated-plugin change.

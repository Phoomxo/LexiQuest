# Hybrid Claude Reviewer Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route routine LexiQuest AI-analysis reviews to `claude-sonnet-5`, route high-risk reviews to `claude-opus-5`, and create one validated DPAPI Claude key usable by both models.

**Architecture:** Keep task classification as the primary authority and add an explicit model plus non-downgradable effort floor to its policy result. Store two immutable model IDs in the AWS Lite Ultimate configuration, create a request-local single-model provider descriptor, validate both models at secret enrollment, and make exactly one selected-model call during an analysis. Smoke and certification exercise the two models separately without fallback or retry.

**Tech Stack:** Windows PowerShell 5.1, MaxPlus HTTPS API, Windows DPAPI, Git worktrees, custom PowerShell test harness, Gitleaks.

## Global Constraints

- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture` on `feature/p8a-voice-architecture`.
- Preserve unrelated dirty P8-H, generated, field, and release files; stage only paths named by the active task.
- Use the exact AWS Lite Ultimate base URL `https://api.maxplus-ai.cc/aws-lite-ultimate` and exact models `claude-sonnet-5` and `claude-opus-5`.
- Use one DPAPI blob at `C:\Users\Phet\AppData\Local\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi` for both models.
- Never put a key in source, Git, a command argument, environment variable, shell profile, log, report, evidence, or chat.
- Never create an empty secret placeholder; save atomically only after account and both-model validation.
- Select one model before the provider request. Never retry, fall back, substitute a model, or call both models for one review.
- Manual effort may raise capability but may not lower architecture, security, migration, release, or critical-disagreement safety floors.
- Do not invoke Codex Security or a repository-wide security worker. Use only bounded local tests, diff checks, Gitleaks, and read-only checkpoint review.
- Do not run a reviewer concurrently with implementation or bounded security checks.

---

### Task 1: Freeze the dual-model configuration and request-local provider projection

**Files:**
- Modify: `tool/ai-analysis/config.json`
- Modify: `tool/ai-analysis/lib/config.ps1`
- Modify: `tool/ai-analysis/tests/effort-router.tests.ps1`
- Modify: `tool/ai-analysis/tests/maxplus-client.tests.ps1`

**Interfaces:**
- Consumes: `Get-AiAnalysisConfig -ConfigPath <path>`.
- Produces: `$config.providers.claudeReviewer.models.routine`, `$config.providers.claudeReviewer.models.deep`, and `New-AiAnalysisClaudeProvider -ClaudeConfig <object> -Model <string>`.

- [ ] **Step 1: Write failing configuration and projection tests**

Require the exact two-entry model map, reject missing/extra/substituted entries, and prove the provider projection does not mutate shared configuration:

```powershell
Assert-Equal 'claude-sonnet-5' $config.providers.claudeReviewer.models.routine 'routine Claude model'
Assert-Equal 'claude-opus-5' $config.providers.claudeReviewer.models.deep 'deep Claude model'
Assert-False ($config.providers.claudeReviewer.PSObject.Properties.Name -contains 'model') 'shared config has no selected model'

$provider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-sonnet-5'
Assert-Equal 'claude-sonnet-5' $provider.model 'request-local model'
Assert-False ($config.providers.claudeReviewer.PSObject.Properties.Name -contains 'model') 'shared config remains unchanged'

Assert-ConfigMutationRejected { param($candidate) $candidate.providers.claudeReviewer.models.routine = 'substitute-model' }
Assert-ConfigMutationRejected {
    param($candidate)
    $candidate.providers.claudeReviewer.models |
        Add-Member -NotePropertyName extra -NotePropertyValue 'claude-fable-5'
}
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1
```

Expected: non-zero exit because `models.routine`, `models.deep`, or `New-AiAnalysisClaudeProvider` is missing.

- [ ] **Step 3: Implement the exact configuration map and provider factory**

Replace the single Claude `model` value with:

```json
"models": {
  "routine": "claude-sonnet-5",
  "deep": "claude-opus-5"
}
```

In `Get-AiAnalysisConfig`, require exactly the two names and values. Add:

```powershell
$modelNames = @($claude.models.PSObject.Properties.Name)
Assert-AiAnalysisConfigInvariant (Test-AiAnalysisConfigSequence $modelNames @('routine', 'deep'))
Assert-AiAnalysisConfigInvariant ($claude.models.routine -ceq 'claude-sonnet-5')
Assert-AiAnalysisConfigInvariant ($claude.models.deep -ceq 'claude-opus-5')

function New-AiAnalysisClaudeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ClaudeConfig,
        [Parameter(Mandatory)]
        [ValidateSet('claude-sonnet-5', 'claude-opus-5')]
        [string]$Model
    )

    $provider = $ClaudeConfig.PSObject.Copy()
    $provider | Add-Member -NotePropertyName model -NotePropertyValue $Model -Force
    return $provider
}
```

Do not mutate `$ClaudeConfig` and do not add arbitrary-model support.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/maxplus-client.tests.ps1
```

Expected: both suites pass.

- [ ] **Step 5: Commit Task 1**

```powershell
git add -- tool/ai-analysis/config.json tool/ai-analysis/lib/config.ps1 tool/ai-analysis/tests/effort-router.tests.ps1 tool/ai-analysis/tests/maxplus-client.tests.ps1
git diff --cached --check
git commit -m "refactor(ai-analysis): define dual Claude reviewer models"
```

---

### Task 2: Add deterministic hybrid model and effort routing

**Files:**
- Modify: `tool/ai-analysis/lib/effort-router.ps1`
- Modify: `tool/ai-analysis/tests/effort-router.tests.ps1`

**Interfaces:**
- Consumes: `Resolve-AiAnalysisPolicy -Task <string> -FileCount <int> -RequestedEffort <value> [-NoReviewer]`.
- Produces: policy property `ClaudeModel`, equal to `$null`, `claude-sonnet-5`, or `claude-opus-5`.

- [ ] **Step 1: Write the failing routing-matrix tests**

Add table-driven assertions:

```powershell
$cases = @(
    @{ Task='Summarize test output'; Files=1; Classification='simple'; Model=$null; Effort=$null },
    @{ Task='Review provider behavior'; Files=1; Classification='focusedPackage'; Model='claude-sonnet-5'; Effort='low' },
    @{ Task='Review regression'; Files=2; Classification='failedOrMultiFile'; Model='claude-sonnet-5'; Effort='medium' },
    @{ Task='Security credential review'; Files=1; Classification='architectureSensitive'; Model='claude-opus-5'; Effort='high' },
    @{ Task='Database migration review'; Files=1; Classification='architectureSensitive'; Model='claude-opus-5'; Effort='high' },
    @{ Task='Release blocker in signing'; Files=1; Classification='releaseBlocker'; Model='claude-opus-5'; Effort='xhigh' },
    @{ Task='Critical disagreement adjudication'; Files=1; Classification='criticalDisagreement'; Model='claude-opus-5'; Effort='max' }
)
```

Add manual-policy tests requiring routine `High` to remain Sonnet, routine `XHigh`/`Max` to upgrade to Opus, and requested `Low` not to reduce architecture High, release XHigh, or critical Max reviewer floors.

- [ ] **Step 2: Run the focused test and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1
```

Expected: non-zero exit because `ClaudeModel` is absent and sensitive manual effort can currently be lowered.

- [ ] **Step 3: Implement safety-floor and model selection logic**

Extend the architecture-sensitive pattern to include `database`, `schema`, `security`, `auth`, `credential`, and `secret`. Use a rank map to take the maximum of requested and required effort for high-risk classifications:

```powershell
$rank = @{ low=0; medium=1; high=2; xhigh=3; max=4; ultra=5 }

if ($classification -in @('architectureSensitive','releaseBlocker','criticalDisagreement')) {
    if ($rank[$requested] -gt $rank[$gptEffort]) { $gptEffort = $requested }
    $requestedClaude = if ($requested -eq 'ultra') { 'max' } else { $requested }
    if ($rank[$requestedClaude] -gt $rank[$claudeEffort]) { $claudeEffort = $requestedClaude }
} else {
    $gptEffort = $requested
    if ($reviewerRequired) { $claudeEffort = $requested }
}
```

Resolve the model only after effort and reviewer-bypass logic:

```powershell
$claudeModel = if (-not $reviewerRequired) {
    $null
} elseif ($classification -in @('architectureSensitive','releaseBlocker','criticalDisagreement') -or
          $claudeEffort -in @('xhigh','max')) {
    'claude-opus-5'
} else {
    'claude-sonnet-5'
}
```

Add `ClaudeModel = $claudeModel` to the returned policy.

- [ ] **Step 4: Run the focused test and verify GREEN**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/effort-router.tests.ps1
```

Expected: all configuration and routing cases pass.

- [ ] **Step 5: Commit Task 2**

```powershell
git add -- tool/ai-analysis/lib/effort-router.ps1 tool/ai-analysis/tests/effort-router.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): route Claude reviewer by task risk"
```

---

### Task 3: Validate both models at enrollment and use one selected model per analysis

**Files:**
- Modify: `tool/ai-analysis/lib/maxplus-client.ps1`
- Modify: `tool/ai-analysis/initialize-secrets.ps1`
- Modify: `tool/ai-analysis/lib/analysis-command.ps1`
- Modify: `tool/ai-analysis/tests/maxplus-client.tests.ps1`
- Modify: `tool/ai-analysis/tests/orchestrator.tests.ps1`

**Interfaces:**
- Consumes: `Test-MaxPlusCredential`, `New-AiAnalysisClaudeProvider`, and policy `ClaudeModel`.
- Produces: `Test-MaxPlusCredential -RequiredModels <string[]>` and request-local selected Claude provider use throughout one command.

- [ ] **Step 1: Write failing credential-enrollment tests**

Require one account and one catalog call to validate both exact Claude models:

```powershell
$gate = Test-MaxPlusCredential `
    -Provider $config.providers.claudeReviewer `
    -RequiredModels @('claude-sonnet-5','claude-opus-5') `
    -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport

Assert-Equal 2 $requests.Count 'one account and one model request'
Assert-True $gate.ModelAvailable 'both required models discovered'
```

For two separate fixtures, omit Sonnet and omit Opus. Each must throw `unsupportedModel:<missing-id>`, make exactly two requests, and never call a save operation. Preserve the existing unlimited-cap regression.

Add a static initializer assertion requiring both values under `models` to be passed through `-RequiredModels` before `Save-AiAnalysisSecret`.

- [ ] **Step 2: Write failing analysis-composition tests**

Capture Claude generation bodies for a focused task and a security task. Assert exactly one Claude generation per command, Sonnet for focused and Opus for security. After each command assert the shared config has no selected `model` property. Make a Sonnet generation return `503` and assert there is no Opus request and no report.

- [ ] **Step 3: Run focused tests and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/maxplus-client.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1
```

Expected: non-zero exit because multi-model validation and policy-selected provider projection are not integrated.

- [ ] **Step 4: Implement multi-model credential validation**

Add an optional required-model parameter while preserving the single-model GPT call:

```powershell
[string[]]$RequiredModels = @()

if (@($RequiredModels).Count -eq 0) {
    $RequiredModels = @([string]$Provider.model)
}
```

Build an ordinal hash set from `models.data[].id`, reject malformed or duplicate-empty IDs, and require every exact ID once. Throw `unsupportedModel:<id>` for the first missing approved ID. Return the existing identity-free gate shape and clear catalog references before returning.

```powershell
$required = @($RequiredModels | ForEach-Object { [string]$_ })
$available = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($model in $modelData) {
    $modelId = Get-AiAnalysisObjectProperty -Object $model -Name 'id'
    if ($modelId -isnot [string] -or [string]::IsNullOrWhiteSpace($modelId)) { throw 'malformedResponse' }
    [void]$available.Add($modelId)
}
foreach ($requiredModel in $required) {
    if (-not $available.Contains($requiredModel)) { throw "unsupportedModel:$requiredModel" }
}
```

In `initialize-secrets.ps1`, pass the one GPT model or both configured Claude models. Keep validation before the single atomic save.

- [ ] **Step 5: Implement request-local analysis provider selection**

After policy resolution and before reading the Claude key:

```powershell
$claudeProvider = $null
if ($policy.ReviewerRequired) {
    $claudeProvider = New-AiAnalysisClaudeProvider `
        -ClaudeConfig $config.providers.claudeReviewer `
        -Model ([string]$policy.ClaudeModel)
}
```

Use `$claudeProvider` for the selected-model credential gate and `Invoke-ClaudeReview`. Never loop over the model map. Clear `$claudeProvider` in `finally`.

- [ ] **Step 6: Run focused tests and verify GREEN**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/maxplus-client.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/secret-store.tests.ps1
```

Expected: all three suites pass; request counts prove no retry or fallback.

- [ ] **Step 7: Commit Task 3**

```powershell
git add -- tool/ai-analysis/lib/maxplus-client.ps1 tool/ai-analysis/initialize-secrets.ps1 tool/ai-analysis/lib/analysis-command.ps1 tool/ai-analysis/tests/maxplus-client.tests.ps1 tool/ai-analysis/tests/orchestrator.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): validate and invoke selected Claude model"
```

- [ ] **Step 8: Run independent checkpoint A**

Ask the existing read-only reviewer to inspect Tasks 1-3 for routing safety floors, shared-state mutation, multi-model validation, atomic secret replacement, and zero fallback. Do not run implementation or security checks concurrently. Resolve every P0-P2 with a failing test before continuing.

---

### Task 4: Split smoke and certification evidence by Claude model

**Files:**
- Modify: `tool/ai-analysis/lib/smoke-command.ps1`
- Modify: `tool/ai-analysis/tests/orchestrator.tests.ps1`

**Interfaces:**
- Consumes: the dual-model config and `New-AiAnalysisClaudeProvider`.
- Produces: smoke metadata with three provider/model entries and model-specific effort-support rows.

- [ ] **Step 1: Write failing smoke tests**

For ordinary smoke, require one GPT Low, one Sonnet Low, and one Opus High generation. Account/model discovery remains one request per key/provider route, and Claude validation sees both model IDs in one catalog response:

```powershell
Assert-Equal 3 $gptRequests.Count 'GPT account model generation calls'
Assert-Equal 4 $claudeRequests.Count 'Claude account model and two generation calls'
Assert-Equal @('claude-sonnet-5','claude-opus-5') @($claudeGenerationModels) 'both smoke models exactly once'
Assert-Equal @('low','high') @($claudeGenerationEfforts) 'lowest routed efforts'
```

For certification, require model/effort pairs:

```text
claude-sonnet-5: low, medium, high
claude-opus-5: high, xhigh, max
```

Assert 12 total effort-support rows: six GPT and six Claude. Make one Opus effort return `unsupportedEffort` and prove no Sonnet substitution.

- [ ] **Step 2: Run the orchestrator suite and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1
```

Expected: non-zero exit because smoke currently creates one Claude provider and one Claude generation.

- [ ] **Step 3: Implement the two-model smoke**

Create request-local Sonnet and Opus descriptors. Validate the Claude key once with both required IDs, then invoke Sonnet Low and Opus High exactly once. Reject an unexpected result from either. Store all three normalized provider metadata records.

```powershell
$sonnetProvider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-sonnet-5'
$opusProvider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-opus-5'
$requiredClaudeModels = @($config.providers.claudeReviewer.models.routine, $config.providers.claudeReviewer.models.deep)
$null = Test-MaxPlusCredential -Provider $config.providers.claudeReviewer -RequiredModels $requiredClaudeModels -SecureKey $claudeKey -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
$sonnet = Invoke-ClaudeReview -Provider $sonnetProvider -SecureKey $claudeKey -Prompt $prompt -Effort low -MaxOutputTokens 4096 -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
$opus = Invoke-ClaudeReview -Provider $opusProvider -SecureKey $claudeKey -Prompt $prompt -Effort high -MaxOutputTokens 16384 -TimeoutSeconds $TimeoutSeconds -Transport $ClaudeTransport
```

When `-CertifyEfforts` is set, probe only Sonnet Medium/High and Opus XHigh/Max because Sonnet Low and Opus High were already proven by smoke. Record the exact model in every row. Keep the existing one-attempt `unsupportedEffort` handling and remove no evidence on a supported response.

```powershell
$claudeProbes = @(
    [pscustomobject]@{ Provider=$sonnetProvider; Effort='medium' },
    [pscustomobject]@{ Provider=$sonnetProvider; Effort='high' },
    [pscustomobject]@{ Provider=$opusProvider; Effort='xhigh' },
    [pscustomobject]@{ Provider=$opusProvider; Effort='max' }
)
```

- [ ] **Step 4: Run focused suites and verify GREEN**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/report-writer.tests.ps1
```

Expected: both suites pass with three smoke provider records and twelve certification rows.

- [ ] **Step 5: Commit Task 4**

```powershell
git add -- tool/ai-analysis/lib/smoke-command.ps1 tool/ai-analysis/tests/orchestrator.tests.ps1 tool/ai-analysis/tests/report-writer.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): certify Sonnet and Opus reviewer routes"
```

- [ ] **Step 6: Run independent checkpoint B**

Request read-only review of smoke cost bounds, exact request counts, metadata privacy, model-specific certification, and no retry/substitution. Resolve every P0-P2 with a failing test.

---

### Task 5: Align documentation, install the immutable runtime, and enroll the Claude key

**Files:**
- Modify: `tool/ai-analysis/README.md`
- Modify: `tool/ai-analysis/tests/documentation.tests.ps1`
- Modify: `docs/superpowers/specs/2026-08-01-local-ai-analysis-orchestrator-design.md`
- Modify: `docs/superpowers/plans/2026-08-01-local-ai-analysis-orchestrator-implementation.md`
- Modify: `docs/superpowers/plans/2026-08-01-long-term-engineering-workflow-profiles-implementation.md`

**Interfaces:**
- Consumes: the committed source runtime and stable launcher.
- Produces: installed immutable runtime, protected Claude DPAPI blob, local health evidence, and explicit real-provider smoke evidence.

- [ ] **Step 1: Write failing documentation assertions**

Require README and workflow documentation to contain both exact model IDs, the routing matrix terms `focusedPackage`, `architectureSensitive`, and `releaseBlocker`, the shared Claude DPAPI path, and the phrases `no fallback` and `no retry`. Reject the obsolete pool-prefixed model value.

- [ ] **Step 2: Run documentation tests and verify RED**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/documentation.tests.ps1
```

Expected: non-zero exit until all runtime and future-workflow documents describe the dual-model contract.

- [ ] **Step 3: Update documentation and future workflow contracts**

Document that Sonnet is routine, Opus is deep/high-risk, both share one Claude DPAPI key, model selection precedes requests, and failure never causes fallback or retry. Update future external-review acceptance from one fixed model to the exact model allowed by the workflow classification.

```markdown
| Classification | Claude reviewer |
|---|---|
| focusedPackage / failedOrMultiFile | claude-sonnet-5 |
| architectureSensitive / releaseBlocker / criticalDisagreement | claude-opus-5 |

Both routes use `%LOCALAPPDATA%\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi`.
Selection occurs before the request. Provider failure causes no retry and no fallback.
```

- [ ] **Step 4: Run the final source gate**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1
git diff --check -- tool/ai-analysis docs/superpowers/specs docs/superpowers/plans AGENTS.md
gitleaks detect --no-banner --redact --no-git --source tool/ai-analysis
```

Expected: all AI-analysis suites pass, diff check exits zero, and Gitleaks reports no leaks.

- [ ] **Step 5: Commit Task 5 source and documentation**

Stage only the Task 5 paths plus any focused regression fix approved at checkpoints:

```powershell
git add -- tool/ai-analysis/README.md tool/ai-analysis/tests/documentation.tests.ps1 docs/superpowers/specs/2026-08-01-local-ai-analysis-orchestrator-design.md docs/superpowers/plans/2026-08-01-local-ai-analysis-orchestrator-implementation.md docs/superpowers/plans/2026-08-01-long-term-engineering-workflow-profiles-implementation.md
git diff --cached --check
git commit -m "docs(ai-analysis): align hybrid reviewer workflow"
```

- [ ] **Step 6: Install the committed runtime**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/install-project-runtime.ps1 -ProjectRoot (Get-Location).Path
```

Expected: `active-runtime.json` names the new commit and the runtime path is `%LOCALAPPDATA%\LexiQuest\ai-analysis\runtime\<commit>`.

- [ ] **Step 7: Enroll only the Claude key through the stable secure prompt**

Open a visible interactive PowerShell window with:

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path -Provider ClaudeReviewer
```

Expected: the owner enters the AWS Lite Ultimate inference key once; the runtime validates active account, positive credit, optional cap state, `claude-sonnet-5`, and `claude-opus-5`, then atomically creates `C:\Users\Phet\AppData\Local\LexiQuest\ai-analysis\secrets\claude-reviewer.dpapi`. Do not retry automatically if validation fails.

- [ ] **Step 8: Run local health and explicit real-provider smoke**

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Health -ProjectRoot (Get-Location).Path
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Smoke -ProjectRoot (Get-Location).Path
```

Expected: health passes without network use; smoke performs one GPT Low, one Sonnet Low, and one Opus High generation with zero retry and writes metadata only.

- [ ] **Step 9: Verify canonical/worktree and fresh CLI discovery**

Run Health from the canonical checkout and the linked worktree. Start a fresh Codex CLI task in the worktree and confirm it can discover the stable launcher and run Health without reading or printing keys. Do not repeat smoke merely because the session is new.

- [ ] **Step 10: Run final independent acceptance review**

Give the reviewer the committed diff, focused/full test outputs, Gitleaks result, active runtime commit, health result, DPAPI filename/ACL metadata, and redacted smoke metadata. Require no unresolved P0-P2. The reviewer must not receive prompts, source payloads, account identity, raw provider responses, API keys, or DPAPI bytes.

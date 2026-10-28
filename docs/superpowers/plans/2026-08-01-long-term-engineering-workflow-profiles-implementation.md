# Long-term Engineering Workflow Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic, project-bound workflow control plane that future LexiQuest Codex Desktop and CLI sessions use for feature, bugfix, refactor, migration, security, device, release, and hotfix work without repeating unchanged gates or mixing incompatible evidence.

**Architecture:** Add a PowerShell 5.1 package under `tool/engineering-workflows` that validates data-only profiles, composes stricter requirements, persists transactional local state under `%LOCALAPPDATA%`, records content-addressed gate evidence, and exposes explicit CLI commands. It consumes the accepted Project Runtime Foundation only through its stable launcher for bounded analyst/reviewer calls; provider output is read-only evidence and can never mutate workflow state.

**Tech Stack:** Windows PowerShell 5.1, .NET Git/JSON/SHA-256/file APIs, Git CLI, existing LexiQuest AI-analysis runtime, line-oriented JSON ledger, current-user `%LOCALAPPDATA%`, existing Flutter/backend/device/release commands selected by approved task plans.

## Global Constraints

- Execute `docs/superpowers/plans/2026-08-01-project-scoped-ai-analysis-bootstrap-implementation.md` and pass its acceptance gate before this plan.
- Execute implementation inline. Use one independent read-only reviewer only at Checkpoints A, B, and Final Acceptance; never let a reviewer edit files or execute provider-suggested commands.
- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture` on `feature/p8a-voice-architecture` unless the owner explicitly changes the canonical branch.
- Preserve all unrelated dirty P8-H, generated, field-evidence, and release-runbook changes. Stage only the exact files listed in the active task.
- Do not modify or reuse the uncommitted `tool/cli/lib/gate-ledger.ps1`, `tool/cli/record-gate-result.ps1`, `tool/cli/tests/gate-ledger.tests.ps1`, or `docs/field/gate-ledger-template.json`; migration of those owner changes is a separate reviewed workflow after this engine is accepted.
- Keep workflow source under `tool/engineering-workflows/`; keep authoritative active state only under `%LOCALAPPDATA%\LexiQuest\engineering-workflows\lexiquest\`.
- Support Windows PowerShell 5.1. Do not add a PowerShell Gallery, Node, Python, Dart, or cloud-service dependency.
- Bind every command to the resolved LexiQuest Git common directory. Never authorize by worktree path prefix.
- Profiles are inert JSON data. Reject unknown properties, schema versions, profile IDs, gate IDs, adapter IDs, invalidation inputs, completion rules, and executable-looking fields.
- Profile composition takes the union of requirements; the higher risk, stronger review requirement, and non-reusable evidence policy win.
- Codex is the only implementer. GPT is a bounded analyst and AWS Lite Ultimate is a sequential independent reviewer. Provider output is untrusted and cannot execute, edit, transition, waive, retry, or complete anything.
- Never store keys, plaintext DPAPI values, headers, cookies, signing passwords, provider prompts/responses, chat transcripts, source contents/patches, private reference contents, account IDs, device serials, or user learning content.
- Never retry a gate or provider automatically. Stop on the first failure and rerun only after a relevant input changes or a blocker is recorded.
- Three occurrences of the same failure fingerprint require architecture review before another implementation attempt.
- Never combine device/release evidence from different application artifact hashes.
- Do not invoke Codex Security, Security Scan, Deep Scan, repository-wide security analysis, or concurrent security/multi-agent work. Use focused Gitleaks, OSV/dependency checks when relevant, and manual diff review.
- Run focused tests after each task. Run the workflow full suite only at Checkpoints A, B, the Task 8 integration gate, and Final Acceptance when relevant inputs changed.
- Public failures use only these stable categories: `workflowNotFound`, `projectMismatch`, `profileInvalid`, `profileCompositionConflict`, `scopeDrift`, `sharedAreaConflict`, `baselineMissing`, `gateFailed`, `gateEvidenceStale`, `artifactMismatch`, `externalReviewUnavailable`, `ownerEvidenceMissing`, `credentialRequired`, `deviceRequired`, `stateIntegrityFailure`, `stateWriteInterrupted`, and `blocked`.

## File Map and Ownership

- `tool/engineering-workflows/config/profiles.v1.json`: eight data-only profile definitions.
- `tool/engineering-workflows/lib/hash.ps1`: UTF-8 SHA-256 and canonical ordered-object helpers.
- `tool/engineering-workflows/lib/profile-registry.ps1`: strict profile validation and deterministic composition.
- `tool/engineering-workflows/lib/project-binding.ps1`: Git common-directory/worktree/branch/commit resolution.
- `tool/engineering-workflows/lib/state-store.ps1`: local paths, write-ahead transaction, ledger append, recovery, and state reads.
- `tool/engineering-workflows/lib/lifecycle.ps1`: lifecycle transitions, scope checks, workflow creation, and shared-area ownership.
- `tool/engineering-workflows/lib/gate-ledger.ps1`: gate-key calculation, reuse, invalidation, and failure fingerprints.
- `tool/engineering-workflows/lib/evidence.ps1`: privacy validation, gate/review evidence, artifact consistency, reports, and completion checks.
- `tool/engineering-workflows/lib/reviewer-adapter.ps1`: exact stable-launcher invocation and sanitized review projection.
- `tool/engineering-workflows/invoke-workflow.ps1`: explicit public command dispatcher; no command strings or remaining arguments.
- `tool/engineering-workflows/README.md`: operator workflow for Desktop, CLI, recovery, and profile extension.
- `tool/engineering-workflows/tests/test-helpers.ps1`: isolated assertions and temporary Git/local-state fixtures.
- `tool/engineering-workflows/tests/profile-registry.tests.ps1`: schema, composition, and executable-data rejection.
- `tool/engineering-workflows/tests/state-store.tests.ps1`: project binding, transactions, crash recovery, and isolation.
- `tool/engineering-workflows/tests/lifecycle.tests.ps1`: transitions, scope drift, and shared ownership.
- `tool/engineering-workflows/tests/gate-ledger.tests.ps1`: content keys, reuse, invalidation, and three-failure stop.
- `tool/engineering-workflows/tests/evidence.tests.ps1`: privacy, review, completion, and artifact consistency.
- `tool/engineering-workflows/tests/reviewer-adapter.tests.ps1`: local-health boundary, exact arguments, and untrusted output.
- `tool/engineering-workflows/tests/command.tests.ps1`: explicit CLI projection and mutation safety.
- `tool/engineering-workflows/tests/profile-e2e.tests.ps1`: Complete and Blocked fixtures for all eight profiles.
- `tool/engineering-workflows/tests/documentation.tests.ps1`: AGENTS and README discovery contract.
- `tool/engineering-workflows/tests/run-tests.ps1`: deterministic stop-on-first-failing-suite runner.
- `AGENTS.md`: append workflow discovery rules after preserving the Project Runtime Foundation and repository guardrails.

---

### Task 1: Create the Strict Profile Registry and Composition Contract

**Files:**
- Create: `tool/engineering-workflows/config/profiles.v1.json`
- Create: `tool/engineering-workflows/lib/hash.ps1`
- Create: `tool/engineering-workflows/lib/profile-registry.ps1`
- Create: `tool/engineering-workflows/tests/test-helpers.ps1`
- Create: `tool/engineering-workflows/tests/profile-registry.tests.ps1`
- Create: `tool/engineering-workflows/tests/run-tests.ps1`

**Interfaces:**
- Consumes: repository-owned UTF-8 JSON and PowerShell 5.1.
- Produces: `Get-WorkflowSha256 -Text <string> -> lowercase hex`; `Import-WorkflowProfileRegistry -Path <string> -> hashtable`; `Merge-WorkflowProfiles -Registry <hashtable> -PrimaryProfile <string> -SecondaryProfiles <string[]> -> composed profile object`.

- [ ] **Step 1: Add the isolated test harness and failing registry tests**

Create the test helper with `Invoke-WorkflowTest`, `Assert-True`, `Assert-False`, `Assert-Equal`, `Assert-Throws`, and `Complete-WorkflowTests`. Use JSON comparison with `ConvertTo-Json -Compress -Depth 50`, matching the existing AI-analysis harness but separate counters and suite names.

Add these exact behavioral assertions to `profile-registry.tests.ps1`:

```powershell
$registry = Import-WorkflowProfileRegistry -Path $profilePath
Assert-Equal @('bugfix','device','feature','hotfix','migration','refactor','release','security') @($registry.Keys | Sort-Object) 'eight profiles'
Assert-Throws { Import-WorkflowProfileRegistry -Path (New-MutatedProfileFile -Property 'command' -Value 'powershell -File x.ps1') } 'profileInvalid'
Assert-Throws { Import-WorkflowProfileRegistry -Path (New-MutatedProfileFile -Property 'schemaVersion' -Value 2) } 'profileInvalid'
Assert-Throws { Merge-WorkflowProfiles -Registry $registry -PrimaryProfile 'unknown' } 'profileInvalid'

$composed = Merge-WorkflowProfiles -Registry $registry -PrimaryProfile 'feature' -SecondaryProfiles @('migration','security')
Assert-Equal @('feature','migration','security') @($composed.ProfileIds) 'stable profile order'
Assert-Equal 'High' $composed.RiskFloor 'highest risk wins'
Assert-True $composed.IndependentReview.Required 'strict review wins'
Assert-Equal 'High' $composed.IndependentReview.MinimumEffort 'highest review effort'
Assert-True ('legacyMigration' -cin @($composed.Gates.gateId)) 'migration gates retained'
Assert-True ('secretScan' -cin @($composed.Gates.gateId)) 'security gates retained'
Assert-Equal 64 $composed.ProfileSetHash.Length 'profile hash'
```

Define `New-MutatedProfileFile` in the test file. It reads the canonical JSON, changes only root `schemaVersion` when that property is requested, otherwise adds the requested property to the first profile with `Add-Member -Force`, writes UTF-8 JSON to the suite's temporary directory, and returns that path. Delete the temporary directory in `finally`.

- [ ] **Step 2: Run the registry test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/profile-registry.tests.ps1
```

Expected: FAIL because `lib/profile-registry.ps1` and `config/profiles.v1.json` do not exist.

- [ ] **Step 3: Add the exact data-only profile vocabulary**

Create `profiles.v1.json` with schema version 1 and these exact policies. JSON objects may be formatted across lines, but the identifiers and arrays are normative:

```json
{
  "schemaVersion": 1,
  "profiles": [
    {"profileId":"feature","riskFloor":"Medium","requiredArtifacts":["approvedSpec","implementationPlan","acceptanceCriteria"],"gates":[["behaviorRed","Baseline","behavior-baseline-v1",["source"]],["behaviorGreen","FocusedGate","focused-test-v1",["source","dependency"]],["affectedIntegration","IntegrationGate","integration-test-v1",["source","dependency","schema","configuration"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"Medium"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied"],"blockerCategories":["credentialRequired","externalService","ownerEvidenceMissing"]},
    {"profileId":"bugfix","riskFloor":"Medium","requiredArtifacts":["reproduction","rootCause","regressionTest"],"gates":[["reproductionRed","Baseline","behavior-baseline-v1",["source"]],["regressionGreen","FocusedGate","focused-test-v1",["source","dependency"]],["affectedIntegration","IntegrationGate","integration-test-v1",["source","dependency","schema","configuration"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"Medium"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","architectureReviewCleared"],"blockerCategories":["environment","externalService","credentialRequired"]},
    {"profileId":"refactor","riskFloor":"Medium","requiredArtifacts":["behaviorBaseline","stableContracts"],"gates":[["behaviorBaseline","Baseline","focused-test-v1",["source","dependency"]],["equivalence","FocusedGate","focused-test-v1",["source","dependency"]],["contractDiff","IntegrationGate","manual-evidence-v1",["source","schema","configuration"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"Medium"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","noBehaviorDrift"],"blockerCategories":["scopeDrift","environment"]},
    {"profileId":"migration","riskFloor":"High","requiredArtifacts":["sourceSchema","destinationSchema","legacyFixtures","rollbackPolicy"],"gates":[["freshMigration","FocusedGate","migration-test-v1",["source","dependency","schema"]],["legacyMigration","FocusedGate","migration-test-v1",["source","dependency","schema"]],["migrationIdempotency","FocusedGate","migration-test-v1",["source","schema"]],["upgradeInstall","IntegrationGate","device-journey-v1",["source","dependency","schema","artifact","environment"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"High"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","singleArtifact","dataPreserved"],"blockerCategories":["artifactMismatch","deviceRequired","ownerEvidenceMissing"]},
    {"profileId":"security","riskFloor":"High","requiredArtifacts":["threatBoundary","protectedAssets"],"gates":[["focusedPolicy","FocusedGate","security-check-v1",["source","dependency","configuration"]],["secretScan","IntegrationGate","security-check-v1",["source","configuration"]],["dependencyAudit","IntegrationGate","security-check-v1",["dependency"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"High"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","noSecretLeak"],"blockerCategories":["credentialRequired","externalService","ownerEvidenceMissing"]},
    {"profileId":"device","riskFloor":"High","requiredArtifacts":["artifactIdentity","deviceMatrix","journeySet"],"gates":[["artifactIdentity","Baseline","artifact-check-v1",["artifact"]],["deviceJourneys","FocusedGate","device-journey-v1",["artifact","environment"]],["lifecycleSmoke","FocusedGate","device-journey-v1",["artifact","environment"]],["deviceDataIntegrity","IntegrationGate","device-journey-v1",["artifact","environment","schema"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"High"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","singleArtifact","ownerEvidenceSatisfied"],"blockerCategories":["deviceRequired","artifactMismatch","ownerEvidenceMissing"]},
    {"profileId":"release","riskFloor":"Max","requiredArtifacts":["signedArtifact","upstreamEvidence","rolloutPlan","rollbackPlan"],"gates":[["signedArtifact","Baseline","artifact-check-v1",["artifact"]],["upstreamEvidence","FocusedGate","manual-evidence-v1",["source","dependency","schema","artifact","environment"]],["ownerSmoke","IntegrationGate","device-journey-v1",["artifact","environment"]],["rollbackReady","IntegrationGate","artifact-check-v1",["artifact","schema"]],["stagedRollout","Evidence","rollout-v1",["artifact","environment"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"Max"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","singleArtifact","ownerEvidenceSatisfied","rolloutSatisfied"],"blockerCategories":["credentialRequired","deviceRequired","artifactMismatch","ownerEvidenceMissing"]},
    {"profileId":"hotfix","riskFloor":"High","requiredArtifacts":["productionImpact","rollbackDecision","regressionTest"],"gates":[["hotfixRed","Baseline","focused-test-v1",["source"]],["hotfixGreen","FocusedGate","focused-test-v1",["source","dependency"]],["hotfixDeviceSmoke","IntegrationGate","device-journey-v1",["artifact","environment"]],["signedHotfix","IntegrationGate","artifact-check-v1",["artifact"]],["mergeBack","Evidence","manual-evidence-v1",["source"]]],"independentReview":{"required":true,"phase":"Review","minimumEffort":"High"},"completionRules":["allRequiredGatesPassed","noOpenP0P2","reviewSatisfied","singleArtifact","ownerEvidenceSatisfied","architectureReviewCleared"],"blockerCategories":["artifactMismatch","deviceRequired","ownerEvidenceMissing"]}
  ]
}
```

The registry converts each four-item gate tuple into an object with `GateId`, `Phase`, `AdapterId`, `InvalidationInputs`, `Required = $true`, and `TimeBound = $true` only for `rollout-v1`. Device observations remain reusable across chats only while artifact and environment hashes match.

`behavior-baseline-v1` accepts either a failing automated test reference or, when automation is not feasible, a hashed reproducible manual-observation reference plus the reason automation is infeasible. It never accepts a blank exemption or a post-fix-only observation.

- [ ] **Step 4: Implement deterministic hashing, validation, and composition**

Implement these public contracts and fixed allowlists:

```powershell
$script:WorkflowProfileIds = @('feature','bugfix','refactor','migration','security','device','release','hotfix')
$script:WorkflowRiskOrder = @('Low','Medium','High','Max','Ultra')
$script:WorkflowPhases = @('Intake','Baseline','Implement','FocusedGate','Review','IntegrationGate','Evidence','Complete','Blocked')
$script:WorkflowAdapterIds = @('behavior-baseline-v1','focused-test-v1','integration-test-v1','migration-test-v1','security-check-v1','device-journey-v1','artifact-check-v1','manual-evidence-v1','rollout-v1')
$script:WorkflowInvalidationInputs = @('source','dependency','schema','configuration','artifact','environment')
$script:WorkflowCompletionRules = @('allRequiredGatesPassed','noOpenP0P2','reviewSatisfied','architectureReviewCleared','noBehaviorDrift','singleArtifact','dataPreserved','noSecretLeak','ownerEvidenceSatisfied','rolloutSatisfied')

function Get-WorkflowSha256 {
    param([Parameter(Mandatory)][string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $sha.Dispose() }
}

function Import-WorkflowProfileRegistry {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw 'profileInvalid' }
    try { $root = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { throw 'profileInvalid' }
    Assert-ExactProperties $root @('schemaVersion','profiles')
    if ([int]$root.schemaVersion -ne 1 -or @($root.profiles).Count -ne 8) { throw 'profileInvalid' }
    $registry = @{}
    foreach ($profile in @($root.profiles)) {
        Assert-WorkflowProfile -Profile $profile
        if ($registry.ContainsKey([string]$profile.profileId)) { throw 'profileInvalid' }
        $registry[[string]$profile.profileId] = ConvertTo-ValidatedWorkflowProfile $profile
    }
    if (@($registry.Keys | Sort-Object) -cne @($script:WorkflowProfileIds | Sort-Object)) { throw 'profileInvalid' }
    return $registry
}
```

`Assert-ExactProperties` compares sorted property names exactly. `Assert-WorkflowProfile` validates every enum, tuple length, nonempty unique identifier, and exact object property set; no `command`, `script`, `prompt`, or unknown field survives. `Merge-WorkflowProfiles` keeps primary first, sorts/deduplicates secondary IDs, rejects the primary as secondary, unions artifacts/gates/rules/blockers, rejects a duplicate `gateId` with different phase/adapter/invalidation semantics, chooses the highest risk and review effort, and hashes one compact ordered projection of the composed object.

Create `run-tests.ps1` with this exact stop-on-first-failure runner:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tests = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.tests.ps1' -File | Sort-Object Name)
foreach ($test in $tests) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $test.FullName
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
Write-Host "Engineering workflow tests: $($tests.Count) files passed"
```

- [ ] **Step 5: Run the focused test and commit Task 1**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/profile-registry.tests.ps1
git diff --check -- tool/engineering-workflows
```

Expected: registry suite reports at least 10 passed and 0 failed; diff check has no output.

Commit only:

```powershell
git add -- tool/engineering-workflows/config/profiles.v1.json tool/engineering-workflows/lib/hash.ps1 tool/engineering-workflows/lib/profile-registry.ps1 tool/engineering-workflows/tests/test-helpers.ps1 tool/engineering-workflows/tests/profile-registry.tests.ps1 tool/engineering-workflows/tests/run-tests.ps1
git commit -m "feat(workflow): add strict engineering profiles"
```

---

### Task 2: Add Project Binding and Transactional Local State

**Files:**
- Create: `tool/engineering-workflows/lib/project-binding.ps1`
- Create: `tool/engineering-workflows/lib/state-store.ps1`
- Create: `tool/engineering-workflows/tests/state-store.tests.ps1`

**Interfaces:**
- Consumes: Git CLI, `%LOCALAPPDATA%`, Task 1 hashing.
- Produces: `Resolve-WorkflowProjectBinding`; `Get-WorkflowStoreRoot`; `Write-WorkflowStateTransaction`; `Get-WorkflowState`; `Get-WorkflowStateSummaries`; `Repair-WorkflowInterruptedTransaction`.

- [ ] **Step 1: Write failing binding, transaction, recovery, and privacy tests**

Use two temporary Git repositories and one linked worktree. Add these assertions:

```powershell
$canonical = Resolve-WorkflowProjectBinding -WorkingDirectory $repoRoot
$linked = Resolve-WorkflowProjectBinding -WorkingDirectory $worktreeRoot
Assert-Equal $canonical.GitCommonDirectory $linked.GitCommonDirectory 'registered worktree accepted'
Assert-False ($canonical.GitCommonDirectory -ceq (Resolve-WorkflowProjectBinding -WorkingDirectory $otherRepo).GitCommonDirectory) 'other repository differs'

$store = Get-WorkflowStoreRoot -LocalAppData $localRoot -Binding $canonical
Write-WorkflowStateTransaction -StoreRoot $store -WorkflowId 'wf-001' -PreviousState $null -ProposedState $state -Event $created
Assert-Equal 'Intake' (Get-WorkflowState -StoreRoot $store -WorkflowId 'wf-001').Phase 'state persisted'
Assert-Equal 1 @(Get-Content -LiteralPath (Join-Path $store 'wf-001\ledger.ndjson')).Count 'one event'

New-InterruptedWorkflowTransaction -Mode BeforeLedger -StoreRoot $store -WorkflowId 'wf-before' -State $state
Repair-WorkflowInterruptedTransaction -StoreRoot $store -WorkflowId 'wf-before'
Assert-False (Test-Path (Join-Path $store 'wf-before\transaction.json')) 'unapplied proposal discarded'

New-InterruptedWorkflowTransaction -Mode AfterLedger -StoreRoot $store -WorkflowId 'wf-after' -State $state
Repair-WorkflowInterruptedTransaction -StoreRoot $store -WorkflowId 'wf-after'
Assert-Equal 'Intake' (Get-WorkflowState -StoreRoot $store -WorkflowId 'wf-after').Phase 'ledger-backed proposal completed'

Assert-Throws { Get-WorkflowState -StoreRoot $store -WorkflowId '..\escape' } 'workflowNotFound'
Assert-Throws { Get-WorkflowState -StoreRoot $store -WorkflowId 'wf-corrupt' } 'stateIntegrityFailure'
Assert-NotMatch '(?i)api.?key|authorization|prompt|response|deviceSerial|accountId' (Get-Content -Raw (Join-Path $store 'wf-001\state.json')) 'sanitized state'
```

- [ ] **Step 2: Run the state-store test and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/state-store.tests.ps1`.

Expected: FAIL because `lib/project-binding.ps1` and `lib/state-store.ps1` do not exist.

- [ ] **Step 3: Implement exact Git binding and safe local paths**

`Resolve-WorkflowProjectBinding` must use argument-array Git calls, require zero exit codes, resolve absolute paths, and return only:

```powershell
[pscustomobject][ordered]@{
    ProjectId = 'lexiquest'
    GitCommonDirectory = $resolvedCommonDirectory
    Worktree = $resolvedTopLevel
    Branch = $branch.Trim()
    HeadCommit = $commit.Trim().ToLowerInvariant()
}
```

Reject detached/invalid branch and non-40-character commit as `projectMismatch`. `Get-WorkflowStoreRoot` resolves `<LocalAppData>\LexiQuest\engineering-workflows\lexiquest`, creates it when explicitly requested, and stores `project-binding.json` containing the exact common-directory hash plus canonical path. An existing different common directory throws `projectMismatch`; string-prefix matching is prohibited.

Validate workflow IDs with `^[a-z0-9][a-z0-9-]{2,63}$` before joining paths. Resolve the final directory and require its parent to equal the exact store root.

- [ ] **Step 4: Implement the write-ahead state transaction**

Use UTF-8 without BOM, `FileStream.Flush($true)`, and this order:

```powershell
$previousHash = if ($null -eq $PreviousState) { '' } else { Get-WorkflowSha256 (ConvertTo-WorkflowJson $PreviousState) }
$proposedJson = ConvertTo-WorkflowJson $ProposedState
$eventJson = ConvertTo-WorkflowJson $Event
$transaction = [pscustomobject][ordered]@{
    schemaVersion = 1
    previousStateHash = $previousHash
    proposedStateHash = Get-WorkflowSha256 $proposedJson
    eventHash = Get-WorkflowSha256 $eventJson
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
}
Write-FlushedUtf8File -Path $proposedPath -Text $proposedJson
Write-FlushedUtf8File -Path $transactionPath -Text (ConvertTo-WorkflowJson $transaction)
Append-FlushedLedgerLine -Path $ledgerPath -Text $eventJson
Replace-WorkflowFileAtomically -Source $proposedPath -Destination $statePath
[IO.File]::Delete($transactionPath)
```

Define the internal file primitives exactly at this boundary:

```powershell
function ConvertTo-WorkflowJson {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 50 -Compress)
}

function Write-FlushedUtf8File {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($Text)
    $stream = New-Object System.IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Append-FlushedLedgerLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Text)
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($Text + "`n")
    $stream = New-Object System.IO.FileStream($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) }
    finally { $stream.Dispose() }
}

function Replace-WorkflowFileAtomically {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Destination)
    if ([IO.File]::Exists($Destination)) {
        $backup = $Destination + '.backup'
        [IO.File]::Replace($Source, $Destination, $backup, $true)
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    } else {
        [IO.File]::Move($Source, $Destination)
    }
}
```

Every temporary filename includes a new GUID and is resolved beneath the exact workflow directory before creation. Tests construct interrupted states by calling these primitives in the same production order and intentionally stopping before ledger append or before state replacement; production code exposes no crash-injection parameter.

Recovery compares the current state hash, proposed hash, and final valid ledger-line hash. If no matching ledger event exists and current state equals the previous hash, delete only the proposed file and transaction. If the ledger event matches and current state equals the previous hash, finish the atomic replacement. If current state already equals the proposed hash, delete the transaction. Every other combination throws `stateIntegrityFailure`. A partial or invalid NDJSON line also throws; never truncate or reset the ledger automatically.

- [ ] **Step 5: Run tests and commit Task 2**

Run the state-store and registry suites. Expected: both report 0 failures.

```powershell
git add -- tool/engineering-workflows/lib/project-binding.ps1 tool/engineering-workflows/lib/state-store.ps1 tool/engineering-workflows/tests/state-store.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): persist project-bound workflow state"
```

---

### Task 3: Enforce Lifecycle, Scope, and Shared Integration Ownership

**Files:**
- Create: `tool/engineering-workflows/lib/lifecycle.ps1`
- Create: `tool/engineering-workflows/tests/lifecycle.tests.ps1`

**Interfaces:**
- Consumes: composed profile, project binding, Task 2 state transactions.
- Produces: `Start-EngineeringWorkflow`; `Move-EngineeringWorkflowPhase`; `Assert-WorkflowScope`; `Claim-WorkflowSharedAreas`; `Release-WorkflowSharedAreas`.

- [ ] **Step 1: Write failing lifecycle and collision tests**

Cover the only normal transition path and terminal alternatives:

```powershell
$expected = @('Intake','Baseline','Implement','FocusedGate','Review','IntegrationGate','Evidence','Complete')
$workflow = Start-EngineeringWorkflow -WorkflowId 'p8h-engine' -Label 'P8-H provider runtime' -ComposedProfile $composed -Binding $binding -ApprovedScope @('lib/features/ai_tutor','test/features/ai_tutor') -SharedAreas @('runtimeBootstrap','databaseSchema') -StoreRoot $store
foreach ($phase in $expected[1..($expected.Count - 1)]) {
    $workflow = Move-EngineeringWorkflowPhase -State $workflow -TargetPhase $phase -EvidenceRef "e-$phase" -StoreRoot $store
}
Assert-Equal 'Complete' $workflow.Phase 'normal lifecycle'
Assert-Throws { Move-EngineeringWorkflowPhase -State $workflow -TargetPhase 'Implement' -EvidenceRef 'back' -StoreRoot $store } 'profileInvalid'

Assert-Throws { Start-EngineeringWorkflow -WorkflowId 'collision' -Label 'collision' -ComposedProfile $composed -Binding $binding -ApprovedScope @('lib/runtime') -SharedAreas @('runtimeBootstrap') -StoreRoot $store } 'sharedAreaConflict'
Assert-Throws { Assert-WorkflowScope -ApprovedScope @('lib/features/ai_tutor') -ChangedPaths @('lib/runtime/app_bootstrap.dart') -RepositoryRoot $binding.Worktree } 'scopeDrift'
Assert-True (Assert-WorkflowScope -ApprovedScope @('lib/features/ai_tutor') -ChangedPaths @('lib/features/ai_tutor/data/x.dart') -RepositoryRoot $binding.Worktree) 'nested scope allowed'
```

Also test that `Complete` and `Blocked` release shared areas, that another workflow cannot release ownership it does not hold, and that branch/worktree/commit drift is reported before mutation.

- [ ] **Step 2: Run the lifecycle test and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/lifecycle.tests.ps1`.

Expected: FAIL because `lib/lifecycle.ps1` does not exist.

- [ ] **Step 3: Implement the explicit transition map and state shape**

Use this map and no reverse/skip transitions:

```powershell
$script:WorkflowTransitions = @{
    Intake = @('Baseline','Blocked')
    Baseline = @('Implement','Blocked')
    Implement = @('FocusedGate','Blocked')
    FocusedGate = @('Review','Blocked')
    Review = @('IntegrationGate','Blocked')
    IntegrationGate = @('Evidence','Blocked')
    Evidence = @('Complete','Blocked')
    Complete = @()
    Blocked = @()
}
```

`Start-EngineeringWorkflow` creates an ordered state with `SchemaVersion`, `WorkflowId`, sanitized `Label`, `ProfileIds`, `ProfileSetHash`, `RiskFloor`, `RequiredArtifacts`, empty `Artifacts`, normalized `ApprovedScope`, `SharedAreas`, `ProjectBindingHash`, `Worktree`, `Branch`, `BaseCommit`, `CurrentCommit`, `Phase = 'Intake'`, empty `GateResults`, `Reviews`, `FailureFingerprints`, `OpenFindings`, and UTC timestamps. The stored composed gates and completion rules are immutable snapshots so completed evidence remains readable after a future registry version.

Before every transition, assert the current binding, phase edge, nonblank sanitized evidence reference, and profile phase prerequisites. Only `Move-EngineeringWorkflowPhase` writes state. Helper functions return proposed state objects and never write independently.

- [ ] **Step 4: Implement exact-scope and shared-area ownership**

Normalize approved scope and changed paths as repository-relative forward-slash paths. Reject absolute paths, `..`, `.git`, `.worktrees`, `build`, `%LOCALAPPDATA%`, empty roots, and path-confusion prefixes. A changed path is allowed only if it equals an approved path or begins with `<approved>/` using ordinal-ignore-case comparison on Windows.

Use a project-level `shared-areas.json` with these initial IDs:

```powershell
@('runtimeBootstrap','dependencyManifest','databaseSchema','navigation','signingRelease','appCheck','privacyPolicy','workflowInfrastructure')
```

Ownership records contain only `AreaId`, `WorkflowId`, `WorktreeHash`, and `ClaimedAtUtc`. Claim all requested areas in one atomic transaction or claim none. `Complete` and `Blocked` release only records owned by that workflow.

- [ ] **Step 5: Run focused suites and commit Task 3**

Run lifecycle, state-store, and profile-registry suites. Expected: all pass with 0 failures.

```powershell
git add -- tool/engineering-workflows/lib/lifecycle.ps1 tool/engineering-workflows/tests/lifecycle.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): enforce lifecycle and scope ownership"
```

- [ ] **Checkpoint A: Independent read-only state/architecture review**

Review only Tasks 1-3 and their tests. Inspect profile command-injection resistance, exact Git binding, path traversal, transaction crash windows, partial ledger handling, cross-worktree behavior, transition bypass, and all-or-nothing shared ownership. Do not run repository-wide analysis. Resolve every verified P0-P2 finding with a focused failing test and exact-file fix commit before Task 4.

Run `tool/engineering-workflows/tests/run-tests.ps1` once after fixes. Record the commit and suite result; do not persist reviewer prompts/responses.

---

### Task 4: Add Content-addressed Gate Reuse and Failure-loop Stops

**Files:**
- Create: `tool/engineering-workflows/lib/gate-ledger.ps1`
- Create: `tool/engineering-workflows/tests/gate-ledger.tests.ps1`

**Interfaces:**
- Consumes: composed gate definition and caller-supplied input hashes.
- Produces: `New-WorkflowGateKey`; `Find-ReusableWorkflowGate`; `New-WorkflowFailureFingerprint`; `Register-WorkflowGateFailure`.

- [ ] **Step 1: Write failing relevant-input, reuse, and loop tests**

```powershell
$inputs = @{ source='s1'; dependency='d1'; schema='db1'; configuration='c1'; artifact='a1'; environment='mid-vivo' }
$key1 = New-WorkflowGateKey -ProfileSetHash $profileHash -Gate $gate -AdapterVersion '1.0.0' -InputHashes $inputs -CommandSignature 'flutter-test:ai-tutor'
$inputs.environment = 'high-pixel'
$key2 = New-WorkflowGateKey -ProfileSetHash $profileHash -Gate $gate -AdapterVersion '1.0.0' -InputHashes $inputs -CommandSignature 'flutter-test:ai-tutor'
Assert-Equal $key1 $key2 'irrelevant environment ignored'
$inputs.source = 's2'
Assert-False ($key1 -ceq (New-WorkflowGateKey -ProfileSetHash $profileHash -Gate $gate -AdapterVersion '1.0.0' -InputHashes $inputs -CommandSignature 'flutter-test:ai-tutor')) 'relevant source invalidates'

Assert-True (Find-ReusableWorkflowGate -GateKey $key1 -Results @([pscustomobject]@{ GateKey=$key1; Status='Pass'; TimeBound=$false })) 'exact pass reused'
Assert-False (Find-ReusableWorkflowGate -GateKey $key1 -Results @([pscustomobject]@{ GateKey=$key1; Status='Fail'; TimeBound=$false })) 'failure never reused'
Assert-False (Find-ReusableWorkflowGate -GateKey $key1 -Results @([pscustomobject]@{ GateKey=$key1; Status='Pass'; TimeBound=$true; ValidUntilUtc='2026-07-31T00:00:00Z' }) -NowUtc ([datetime]'2026-08-01T00:00:00Z')) 'expired observation not reused'
Assert-True (Find-ReusableWorkflowGate -GateKey $key1 -Results @([pscustomobject]@{ GateKey=$key1; Status='Pass'; TimeBound=$true; ValidUntilUtc='2026-08-02T00:00:00Z' }) -NowUtc ([datetime]'2026-08-01T00:00:00Z')) 'unexpired observation reused'

$state = Register-WorkflowGateFailure -State $state -GateId 'regressionGreen' -Category 'code' -ErrorSignature 'expected true actual false' -RootCauseId 'cancel-race'
$state = Register-WorkflowGateFailure -State $state -GateId 'regressionGreen' -Category 'code' -ErrorSignature 'expected true actual false' -RootCauseId 'cancel-race'
$state = Register-WorkflowGateFailure -State $state -GateId 'regressionGreen' -Category 'code' -ErrorSignature 'expected true actual false' -RootCauseId 'cancel-race'
Assert-True $state.ArchitectureReviewRequired 'three failures stop implementation'
```

- [ ] **Step 2: Run the gate-ledger test and verify RED**

Expected: FAIL because `lib/gate-ledger.ps1` does not exist.

- [ ] **Step 3: Implement deterministic keys and reuse rules**

`New-WorkflowGateKey` requires all invalidation inputs named by the gate, rejects unknown/missing/blank hashes, normalizes the command signature to a reviewed logical ID rather than a raw shell command, and hashes this ordered object:

```powershell
[pscustomobject][ordered]@{
    schemaVersion = 1
    profileSetHash = $ProfileSetHash
    gateId = $Gate.GateId
    adapterId = $Gate.AdapterId
    adapterVersion = $AdapterVersion
    inputs = [pscustomobject]$orderedRelevantInputs
    commandSignature = $CommandSignature
}
```

`Find-ReusableWorkflowGate` returns only an exact prior PASS. A non-time-bound PASS is reusable while the key matches. A time-bound PASS additionally requires a valid `ValidUntilUtc` later than `NowUtc`; a missing or expired value is not reusable. It never executes a gate and never changes state.

Normalize failure signatures by lowercasing, replacing paths/line numbers/timestamps/hex hashes with fixed tokens, removing secret-like values, and limiting to 512 characters. Hash `GateId|Category|NormalizedSignature|RootCauseId`. Count occurrences across commits. At count 3 set `ArchitectureReviewRequired = $true`; only explicit evidence with gate ID `architectureReviewCleared` can clear it.

- [ ] **Step 4: Run focused suites and commit Task 4**

Run gate-ledger and lifecycle suites. Expected: 0 failures.

```powershell
git add -- tool/engineering-workflows/lib/gate-ledger.ps1 tool/engineering-workflows/tests/gate-ledger.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): prevent unchanged gate loops"
```

---

### Task 5: Add Sanitized Evidence, Artifact Integrity, and Completion Rules

**Files:**
- Create: `tool/engineering-workflows/lib/evidence.ps1`
- Create: `tool/engineering-workflows/tests/evidence.tests.ps1`

**Interfaces:**
- Consumes: state, gate keys/results, review disposition, content hashes.
- Produces: `Add-WorkflowRequiredArtifact`; `Add-WorkflowGateEvidence`; `Add-WorkflowReviewEvidence`; `Add-WorkflowArtifactReference`; `Test-WorkflowCompletion`; `Export-WorkflowReport`.

- [ ] **Step 1: Write failing privacy, mixed-artifact, and completion tests**

```powershell
Assert-Throws { Add-WorkflowGateEvidence -State $state -Evidence @{ GateId='behaviorGreen'; Status='Pass'; ApiKey='ccsk-secret' } } 'stateIntegrityFailure'
Assert-Throws { Add-WorkflowReviewEvidence -State $state -Review @{ Disposition='Pass'; Response='raw provider text' } } 'stateIntegrityFailure'

$state = Add-WorkflowRequiredArtifact -State $state -ArtifactId 'approvedSpec' -ReferenceHash ('d' * 64)
Assert-True ('approvedSpec' -cin @($state.Artifacts.ArtifactId)) 'required artifact recorded by hash'
Assert-Throws { Add-WorkflowRequiredArtifact -State $state -ArtifactId 'unknownArtifact' -ReferenceHash ('d' * 64) } 'baselineMissing'

$device = Add-WorkflowArtifactReference -State $device -ArtifactHash ('a' * 64) -ArtifactType 'apk' -ReferenceHash ('b' * 64)
Assert-Throws { Add-WorkflowGateEvidence -State $device -Evidence (New-PassingEvidence -GateId 'deviceJourneys' -ArtifactHash ('c' * 64)) } 'artifactMismatch'

$complete = Test-WorkflowCompletion -State (Add-AllRequiredPasses $state)
Assert-True $complete.Ready 'all required evidence complete'
$state.OpenFindings = @([pscustomobject]@{ Id='R1'; Severity='P2'; Status='Open' })
Assert-False (Test-WorkflowCompletion -State $state).Ready 'open P2 blocks'
```

`New-PassingEvidence` is a test-only constructor that fills every allowlisted evidence field with deterministic lowercase hashes and UTC values, then applies explicitly supplied overrides. `Add-AllRequiredPasses` records every required artifact, every composed gate PASS, one verified required review, matching owner references for owner adapters, and the single workflow artifact when required. Both helpers call the public Task 5 functions; they do not edit the state object directly.

Also assert that a review result cannot change `Phase`, that P0-P2 must have `Resolved` or `Blocked` dispositions, P3 can remain deferred, owner/device gates require sanitized owner evidence, and exported JSON contains no forbidden keys/values.

- [ ] **Step 2: Run evidence tests and verify RED**

Expected: FAIL because `lib/evidence.ps1` does not exist.

- [ ] **Step 3: Implement recursive evidence allowlists**

Accept only explicit evidence fields:

```powershell
$script:WorkflowEvidenceFields = @('GateId','GateKey','Status','Category','EvidenceKind','Summary','CommandSignature','CommitSha','DependencyHash','SchemaHash','ConfigurationHash','ArtifactHash','EnvironmentClass','ReferenceHash','OccurredAtUtc','ValidUntilUtc','TimeBound','OwnerEvidence')
$script:WorkflowReviewFields = @('ReviewId','Provider','Model','Effort','Disposition','FindingIds','ReferenceHash','OccurredAtUtc')
$script:WorkflowForbiddenNames = '(?i)api.?key|authorization|cookie|password|secret|prompt|response|transcript|account.?id|device.?serial|advertising.?id|source(content)?|patch|header'
$script:WorkflowForbiddenValues = '(?i)\bccsk-[a-z0-9_-]+|\bbearer\s+[a-z0-9._-]+|-----BEGIN [A-Z ]+PRIVATE KEY-----'
```

Reject unknown properties, forbidden names at any nesting depth, forbidden value patterns, absolute paths, raw commands, and strings longer than the field limit. Store only lowercase 64-character hashes for external references and artifacts.

`EvidenceKind` is one of `automatedTest`, `manualObservation`, `integrationTest`, `migrationTest`, `securityCheck`, `deviceJourney`, `artifactCheck`, `manualEvidence`, or `rolloutObservation`. `behavior-baseline-v1` accepts `automatedTest`, or `manualObservation` with a nonblank `ReferenceHash` whose referenced owner document records why automation is infeasible.

`Add-WorkflowGateEvidence` verifies that the gate exists in the state snapshot, its key is correct, and PASS evidence uses the workflow artifact hash for any `artifact`-invalidated gate. It returns proposed state without writing. `Add-WorkflowReviewEvidence` stores sanitized metadata and findings dispositions only; it cannot change phase or gate status.

- [ ] **Step 4: Implement exact completion evaluation and reports**

Evaluate every rule in the immutable state snapshot:

```powershell
$checks = [ordered]@{
    allRequiredGatesPassed = Test-AllRequiredGatesPassed $State
    noOpenP0P2 = @($State.OpenFindings | Where-Object { $_.Severity -in @('P0','P1','P2') -and $_.Status -ne 'Resolved' }).Count -eq 0
    reviewSatisfied = Test-RequiredReview $State
    architectureReviewCleared = -not [bool]$State.ArchitectureReviewRequired
    noBehaviorDrift = Test-GatesPassed $State @('equivalence','contractDiff')
    singleArtifact = Test-SingleArtifact $State
    dataPreserved = Test-GatesPassed $State @('freshMigration','legacyMigration','migrationIdempotency')
    noSecretLeak = Test-GatesPassed $State @('secretScan')
    ownerEvidenceSatisfied = Test-OwnerEvidence $State
    rolloutSatisfied = Test-GatesPassed $State @('stagedRollout')
}
```

`Test-GatesPassed` evaluates only gate IDs that exist in the composed state snapshot; each existing named gate must have a valid PASS. `Test-OwnerEvidence` requires a 64-character owner reference hash on every PASS whose adapter is `device-journey-v1` or `rollout-v1`. This mapping is code-owned and versioned; profile JSON cannot provide an executable completion expression.

Completion also requires every ID in `RequiredArtifacts` to have exactly one hashed entry in `Artifacts`; missing IDs are returned as `MissingArtifactIds`. Return `Ready`, `FailedRules`, `MissingGateIds`, and `MissingArtifactIds`. `Export-WorkflowReport` writes a sanitized ordered JSON report under `build/engineering-workflows/<workflow-id>/report.json` after resolving the path beneath the repository build directory. It includes no ledger events beyond normalized summaries.

- [ ] **Step 5: Run focused suites and commit Task 5**

Run evidence and gate-ledger suites. Expected: 0 failures.

```powershell
git add -- tool/engineering-workflows/lib/evidence.ps1 tool/engineering-workflows/tests/evidence.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): enforce evidence completion rules"
```

---

### Task 6: Add the Read-only Project Runtime Reviewer Boundary

**Files:**
- Create: `tool/engineering-workflows/lib/reviewer-adapter.ps1`
- Create: `tool/engineering-workflows/tests/reviewer-adapter.tests.ps1`

**Interfaces:**
- Consumes: accepted stable AI-analysis launcher and approved repository-relative paths.
- Produces: `Test-WorkflowAnalysisRuntime`; `Invoke-WorkflowIndependentReview -> sanitized review candidate`.

- [ ] **Step 1: Write failing exact-argument and untrusted-output tests**

Use a fake launcher scriptblock and capture every argument:

```powershell
$health = Test-WorkflowAnalysisRuntime -ProjectRoot $repo -Launcher $fakeLauncher
Assert-Equal 'ready' $health.Status 'local health required'
Assert-Equal 1 $calls.Count 'one health call'
Assert-False ($calls[0] -contains 'Analyze') 'health does not analyze'

$candidate = Invoke-WorkflowIndependentReview -ProjectRoot $repo -WorkflowState $state -Paths @('tool/engineering-workflows/lib/evidence.ps1') -Effort 'High' -Launcher $fakeLauncher
Assert-Equal @('Health','Analyze') @($calls | ForEach-Object Command) 'sequential health then analysis'
Assert-True $calls[1].NoReport 'raw report disabled'
Assert-False $calls[1].NoReviewer 'independent reviewer cannot be disabled'
Assert-True ($candidate.Model -in @('claude-sonnet-5','claude-opus-5')) 'reviewer model belongs to foundation allowlist'
Assert-Equal $candidate.PolicyModel $candidate.Model 'review result matches foundation policy model'
Assert-Equal 'PendingVerification' $candidate.Disposition 'model cannot approve itself'
Assert-False ($candidate.PSObject.Properties.Name -contains 'RawResult') 'raw result excluded'

Assert-Throws { Invoke-WorkflowIndependentReview -ProjectRoot $repo -WorkflowState $state -Paths @('..\secret.txt') -Effort High -Launcher $fakeLauncher } 'scopeDrift'
Assert-Throws { ConvertFrom-WorkflowReviewerResult -Result @{ tool_calls=@(@{ command='git commit' }) } } 'stateIntegrityFailure'
```

- [ ] **Step 2: Run reviewer-adapter tests and verify RED**

Expected: FAIL because `lib/reviewer-adapter.ps1` does not exist.

- [ ] **Step 3: Implement one-attempt stable-launcher projection**

Resolve the default launcher only as:

```powershell
$launcherPath = Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1'
```

Require it to exist. Call Health first with exact `ProjectRoot`; when not ready, throw `externalReviewUnavailable`. Then call the launcher once in the same PowerShell process:

```powershell
$result = & $launcherPath -Command Analyze -ProjectRoot $ProjectRoot -Task $boundedTask -Path $Paths -Effort $Effort -NoReport -TimeoutSeconds $TimeoutSeconds
if ($LASTEXITCODE -ne 0 -or $null -eq $result) { throw 'externalReviewUnavailable' }
```

Require the normalized result to contain a non-null independent review from the foundation's fixed AWS Lite Ultimate configuration. Require `Policy.ClaudeModel` to be exactly `claude-sonnet-5` or `claude-opus-5`, require the review model to equal that policy value, and project it as `PolicyModel`. A missing reviewer, a model outside the allowlist, or a policy/review mismatch throws `externalReviewUnavailable`; do not bypass the launcher, disable review, or read DPAPI blobs directly.

Build `$boundedTask` from a fixed code template containing workflow ID, phase, gate IDs, and the instruction to return read-only P0-P3 findings. Do not include ledger history, user text beyond the sanitized label, prompts/responses, or evidence references. Validate all paths with `Assert-WorkflowScope`.

Project only provider, model, effort, finding IDs/severity/category/file/line, conclusion hash, and UTC metadata. Always return `Disposition = 'PendingVerification'`. Codex must verify findings locally and explicitly record their final disposition through Task 5.

- [ ] **Step 4: Run focused suites and commit Task 6**

Run reviewer-adapter and evidence suites. Expected: 0 failures.

```powershell
git add -- tool/engineering-workflows/lib/reviewer-adapter.ps1 tool/engineering-workflows/tests/reviewer-adapter.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): add read-only checkpoint reviewer"
```

- [ ] **Checkpoint B: Independent read-only evidence/reviewer review**

Review only Tasks 4-6 and their interfaces to state/lifecycle. Check key relevance, time-bound reuse, failure fingerprints, privacy recursion, artifact consistency, completion bypass, exact launcher arguments, provider pinning, one-attempt behavior, raw-output exclusion, and inability of model output to mutate state. Resolve every verified P0-P2 finding with a failing focused test and fix commit.

Run the full workflow suite once after fixes and record its commit/result.

---

### Task 7: Add the Explicit CLI and New-session Discovery Contract

**Files:**
- Create: `tool/engineering-workflows/invoke-workflow.ps1`
- Create: `tool/engineering-workflows/README.md`
- Create: `tool/engineering-workflows/tests/command.tests.ps1`
- Create: `tool/engineering-workflows/tests/documentation.tests.ps1`
- Modify: `AGENTS.md`

**Interfaces:**
- Consumes: Tasks 1-6 and the Project Runtime Foundation AGENTS section.
- Produces: public commands `Health`, `List`, `Start`, `RecordArtifact`, `Advance`, `RecordGate`, `Review`, `RecordReview`, `Report`, `Complete`, and `Block`.

- [ ] **Step 1: Write failing dispatcher and documentation tests**

Assert the public script has only explicit parameters and dispatches each command once through a literal switch. Test unknown/remaining arguments fail before state mutation, Health/List make zero provider calls, Complete calls `Test-WorkflowCompletion`, and Review cannot record its own disposition.

Use this canonical subprocess health assertion:

```powershell
$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $commandPath -Command Health -ProjectRoot $repo -LocalAppData $localRoot
if ($LASTEXITCODE -ne 0) { throw 'workflow health failed' }
$health = $json | ConvertFrom-Json
Assert-Equal 'ready' $health.Status 'workflow health'
Assert-Equal @('ActiveCount','ProjectId','Status','StoreSchemaVersion') @($health.PSObject.Properties.Name | Sort-Object) 'sanitized health shape'
```

Documentation tests require AGENTS to preserve all repository guardrails and Project Runtime Foundation discovery rules, name the eight profiles, run workflow Health/List at new-session start, prohibit automatic resume/retry, and require explicit workflow continuation.

- [ ] **Step 2: Run command/documentation tests and verify RED**

Expected: command test fails because the public script is absent; documentation test fails because workflow discovery is absent.

- [ ] **Step 3: Implement the strict dispatcher**

Use explicit parameters only:

```powershell
param(
  [Parameter(Mandatory)][ValidateSet('Health','List','Start','RecordArtifact','Advance','RecordGate','Review','RecordReview','Report','Complete','Block')][string]$Command,
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$WorkflowId,
  [string]$Label,
  [ValidateSet('feature','bugfix','refactor','migration','security','device','release','hotfix')][string]$PrimaryProfile,
  [string[]]$SecondaryProfile = @(),
  [string[]]$Scope = @(),
  [string[]]$SharedArea = @(),
  [ValidateSet('Baseline','Implement','FocusedGate','Review','IntegrationGate','Evidence')][string]$TargetPhase,
  [string]$GateId,
  [ValidateSet('Pass','Fail')][string]$GateStatus,
  [string]$ArtifactId,
  [ValidateSet('apk','aab','document','testEvidence','reviewEvidence','migrationFixture','rolloutEvidence')][string]$ArtifactType,
  [ValidateSet('automatedTest','manualObservation','integrationTest','migrationTest','securityCheck','deviceJourney','artifactCheck','manualEvidence','rolloutObservation')][string]$EvidenceKind,
  [string]$CommandSignature,
  [string]$SourceHash,
  [string]$DependencyHash,
  [string]$SchemaHash,
  [string]$ConfigurationHash,
  [string]$ArtifactHash,
  [string]$EnvironmentClass,
  [string]$ReferenceHash,
  [datetime]$ValidUntilUtc,
  [switch]$OwnerEvidence,
  [ValidateSet('Low','Medium','High','Max','Ultra')][string]$Effort = 'Medium',
  [string[]]$Path = @(),
  [ValidateSet('Resolved','Blocked','Deferred')][string]$ReviewDisposition,
  [ValidateSet('code','test','environment','credential','device','artifact','externalService')][string]$FailureCategory,
  [string]$RootCauseId,
  [string]$ErrorSignature,
  [string]$BlockerCategory,
  [string]$EvidenceRef,
  [ValidateRange(5,600)][int]$TimeoutSeconds = 120,
  [string]$LocalAppData = $env:LOCALAPPDATA
)
```

`LocalAppData` exists for isolated tests; reject it in normal operation when it does not equal the resolved current-user LocalAppData unless `LEXIQUEST_WORKFLOW_TEST_MODE` equals `1`. Dispatch with a literal `switch`; use parameter splats; reject parameters irrelevant to the selected command; never use `Invoke-Expression`, `Start-Process`, generated command strings, or remaining arguments.

Health verifies project binding and local state only. List returns sanitized summaries. Start composes profiles and creates Intake. RecordArtifact stores one required-artifact reference hash and, for application artifacts, the single artifact hash/type. Advance performs one transition. RecordGate records caller-supplied results but never executes the command signature; it requires every hash named by that gate's invalidation inputs, requires `ValidUntilUtc` only for time-bound gates, and requires `OwnerEvidence` plus `ReferenceHash` for device/rollout adapters. Review returns a pending candidate. RecordReview records Codex-verified dispositions. Complete evaluates rules then transitions from Evidence. Block requires an allowed composed blocker category and sanitized reference.

- [ ] **Step 4: Add Desktop/CLI discovery and operator documentation**

Append to AGENTS without altering existing guardrails or AI runtime text. Name both supported entry surfaces exactly as `Codex Desktop` and `Codex CLI`:

```powershell
$workflow = Join-Path (Get-Location).Path 'tool\engineering-workflows\invoke-workflow.ps1'
& $workflow -Command Health -ProjectRoot (Get-Location).Path
& $workflow -Command List -ProjectRoot (Get-Location).Path
```

State that new Desktop/CLI sessions run only local Health/List, show active workflow state, require explicit continuation, and do not rerun tests/providers/devices or mutate state automatically. Document Start/RecordArtifact/Advance/RecordGate/Review/RecordReview/Report/Complete/Block examples, eight profile-selection rules, composition, shared areas, recovery, and adding a versioned profile.

- [ ] **Step 5: Run focused suites and commit Task 7**

Run command and documentation suites, then state/lifecycle suites. Expected: all pass.

```powershell
git add -- AGENTS.md tool/engineering-workflows/invoke-workflow.ps1 tool/engineering-workflows/README.md tool/engineering-workflows/tests/command.tests.ps1 tool/engineering-workflows/tests/documentation.tests.ps1
git diff --cached --check
git commit -m "feat(workflow): expose project engineering lifecycle"
```

---

### Task 8: Prove Complete and Blocked Paths for All Eight Profiles

**Files:**
- Create: `tool/engineering-workflows/tests/profile-e2e.tests.ps1`

**Interfaces:**
- Consumes: public CLI and all engine modules.
- Produces: 16 isolated profile fixtures plus composite, cross-process, worktree, and artifact acceptance coverage.

- [ ] **Step 1: Write the full failing profile matrix test**

For every profile ID, start an isolated workflow, attach exactly its required artifacts, advance through every phase, record every required gate PASS with correct hashes, attach required review/owner/named-assertion evidence, and assert Complete. Start a second workflow and assert a declared blocker moves it to Blocked and releases shared ownership.

Use this matrix as the exact fixture source:

```powershell
$matrix = @{
  feature   = @{ Secondary=@(); Artifact=$false; Owner=$false }
  bugfix    = @{ Secondary=@(); Artifact=$false; Owner=$false }
  refactor  = @{ Secondary=@(); Artifact=$false; Owner=$false }
  migration = @{ Secondary=@(); Artifact=$true;  Owner=$true  }
  security  = @{ Secondary=@(); Artifact=$false; Owner=$false }
  device    = @{ Secondary=@(); Artifact=$true;  Owner=$true  }
  release   = @{ Secondary=@('device','security'); Artifact=$true; Owner=$true }
  hotfix    = @{ Secondary=@('security'); Artifact=$true; Owner=$true }
}
```

Also prove feature+migration+security composition, cross-process List/Resume, another linked worktree acceptance, another repository rejection before disclosure, one changed source hash invalidates only dependent gates, and mixed device/release artifact hashes fail.

- [ ] **Step 2: Run the end-to-end acceptance test**

Expected: all 16 profile paths and the composite/isolation cases pass. A failure is an implementation defect in Tasks 1-7; do not weaken the fixture or add a gate waiver.

- [ ] **Step 3: Resolve any acceptance defect at its owning interface**

Classify the first failure as registry, state, lifecycle, gate, evidence, reviewer, or CLI. Stop Task 8, reopen the owning earlier task, add a narrower failing assertion to that component's existing test file, correct and commit only its owning module/test, then restart Task 8. Do not add profile-specific conditionals to the CLI; completion remains driven by validated profile data plus the fixed rule adapter registry.

- [ ] **Step 4: Run all workflow tests once**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/run-tests.ps1
```

Expected: these nine suite files pass with zero failures: command, documentation, evidence, gate-ledger, lifecycle, profile-e2e, profile-registry, reviewer-adapter, and state-store.

- [ ] **Step 5: Commit Task 8 and any exact matrix-driven fixes**

```powershell
git add -- tool/engineering-workflows/tests/profile-e2e.tests.ps1
git diff --cached --check
git commit -m "test(workflow): cover all engineering profiles"
```

Before committing, inspect `git diff --cached --name-only`; it must contain no unrelated P8-H, generated, `tool/cli`, or field-evidence file.

---

### Task 9: Final Acceptance and Enroll Current LexiQuest Work

**Files:**
- No product source changes expected.
- Machine-local state only under `%LOCALAPPDATA%\LexiQuest\engineering-workflows\lexiquest\`.
- Ignored reports only under `build/engineering-workflows/`.

**Interfaces:**
- Consumes: accepted foundation runtime, committed workflow engine, current P8-H/release scope.
- Produces: final acceptance report plus active `p8h-multi-provider` and `release-readiness` workflow records.

- [ ] **Step 1: Run bounded final source verification once**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/engineering-workflows/tests/run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1
git diff --check -- tool/engineering-workflows AGENTS.md
gitleaks detect --no-banner --redact --no-git --source tool/engineering-workflows
```

Expected: 9 workflow suites pass, the accepted AI suite count passes, diff check has no output, and scoped Gitleaks reports no leaks. Do not scan repository history or unrelated dirty files.

- [ ] **Step 2: Run Final Acceptance independent review**

Review the committed workflow package, AGENTS additions, test results, and spec only. Verify all eight profiles, state recovery, ownership, gate reuse, artifact integrity, privacy, Desktop/CLI discovery, and guardrail preservation. Resolve verified P0-P2 findings with focused failing tests and exact-file commits. Rerun only affected suites, then the full workflow suite once because source changed.

- [ ] **Step 3: Prove fresh-process and linked-worktree health**

Run Health and List from the canonical checkout and `p8a-voice-architecture` worktree in separate PowerShell processes. Expected: both bind to `lexiquest`, disclose only sanitized summaries, and make zero MaxPlus calls. Run Health from a temporary unrelated Git repository and expect `projectMismatch` before state disclosure; delete only the validated temporary repository outside both workspace roots.

- [ ] **Step 4: Enroll the current P8-H workflow without editing its dirty files**

```powershell
$wf = 'tool\engineering-workflows\invoke-workflow.ps1'
& $wf -Command Start -WorkflowId 'p8h-multi-provider' -Label 'P8-H multi-provider BYOK' -PrimaryProfile feature -SecondaryProfile @('migration','security') -Scope @('lib/features/ai_tutor','lib/features/gemini','lib/data/local','lib/runtime','lib/screens','test/features/ai_tutor','test/features/gemini','test/data/local','test/runtime','test/screens') -SharedArea @('runtimeBootstrap','databaseSchema','navigation','privacyPolicy')
```

Expected: Intake state records the current branch/commit and detects the existing dirty scope. Do not mark Baseline or later phases until the approved P8-H plan's artifacts/evidence are attached.

- [ ] **Step 5: Enroll release readiness as a separate non-conflicting workflow**

```powershell
& $wf -Command Start -WorkflowId 'release-readiness' -Label 'P8-E through P8-G release readiness' -PrimaryProfile release -SecondaryProfile @('device','migration','security') -Scope @('docs/field','docs/runbooks','tool/cli','android','pubspec.yaml','pubspec.lock') -SharedArea @('signingRelease','appCheck')
```

Expected: separate Intake state. It does not claim runtimeBootstrap/databaseSchema/navigation because this workflow consumes upstream migration evidence without editing the schema. If future release remediation needs to edit one of those areas, scope expansion and ownership transfer must occur explicitly after P8-H releases it.

- [ ] **Step 6: Demonstrate one real Complete workflow using accepted foundation evidence**

Create `project-runtime-foundation` with primary `feature` and secondary `security`, attach the already accepted foundation spec/plan/commit/test/Gitleaks/reviewer hashes, move through every lifecycle phase, record required gates, and complete only if all evidence hashes match the accepted foundation commit. This proves controlled resume and Complete behavior using real project evidence rather than a synthetic fixture.

- [ ] **Step 7: Final report**

Report:

- workflow engine commit and profile-set hash;
- 9-suite result and scoped Gitleaks result;
- canonical/worktree/unrelated-repository health results;
- Project Runtime Foundation reviewer availability;
- `project-runtime-foundation` Complete evidence summary;
- P8-H and release-readiness workflow IDs, phases, owners, invalidated gates, and blockers;
- confirmation that no product source, key, provider prompt/response, device/account identifier, or private reference content was written by enrollment.

Do not claim that P8-H, P8-E, P8-F, P8-G, device matrix, signing, or rollout is complete merely because their workflow records exist.

## Specification Coverage Matrix

| Specification requirement | Implemented and proven by |
|---|---|
| Foundation dependency and read-only analyst/reviewer roles | Global constraints, Task 6, Checkpoints B/Final |
| Eight versioned data-only profiles and future extension safety | Task 1, Task 8 |
| Primary plus stricter secondary composition | Task 1, Task 8 composite fixture |
| Shared lifecycle and terminal Complete/Blocked states | Task 3, Task 8 |
| Scope drift and one owner per shared integration area | Task 3, Checkpoint A |
| Git common-directory project binding | Task 2, Tasks 7-9 cross-repository checks |
| Transactional state, append-only ledger, and crash recovery | Task 2, Checkpoint A |
| Gate-key reuse and relevant-input invalidation | Task 4, Task 8 |
| No automatic retry and three-failure architecture stop | Task 4, Task 8 bugfix/hotfix fixtures |
| Secret/privacy boundaries and hashed external references | Task 5, Checkpoints B/Final |
| Device/release single-artifact evidence | Task 5, Task 8 device/release fixtures |
| Independent review cannot mutate or complete state | Task 6, Task 7 |
| Desktop/CLI discovery and explicit cross-chat continuation | Task 7, Task 9 |
| Complete and Blocked fixtures for every profile | Task 8 |
| Current P8-H and release-readiness enrollment | Task 9 |
| Bounded local security verification without Codex Security | Global constraints, Task 9 |

## Execution Order and Checkpoint Ledger

The execution order is fixed: Project Runtime Foundation plan -> Tasks 1-3 -> Checkpoint A -> Tasks 4-6 -> Checkpoint B -> Tasks 7-8 -> Final Acceptance -> Task 9 enrollment.

At each checkpoint, record only commit SHA, dependency-lock hash when applicable, profile-set hash, test command signature, result, UTC time, and reviewer disposition. Do not repeat a checkpoint when those inputs are unchanged. If source changes after a checkpoint, rerun the smallest affected focused suite before the dependent checkpoint.

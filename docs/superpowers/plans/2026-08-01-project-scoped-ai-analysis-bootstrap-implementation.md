# Project-Scoped AI Analysis Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install one immutable LexiQuest AI-analysis runtime that every Codex Desktop chat and Windows Codex CLI session can discover and invoke across registered repository worktrees without re-entering or exposing API keys.

**Architecture:** Keep tested source in `tool/ai-analysis`, copy an exact allowlist into a versioned `%LOCALAPPDATA%` runtime, and atomically activate it through a stable launcher and hash manifest. Bind every invocation to LexiQuest's resolved Git common directory, keep keys in current-user DPAPI blobs, and teach new Codex sessions the local-only health/invocation contract through `AGENTS.md`.

**Tech Stack:** Windows PowerShell 5.1, .NET DPAPI/ACL APIs, Git CLI, SHA-256, JSON manifests, existing MaxPlus client, Codex Desktop, Codex CLI 0.144.6 or newer.

## Global Constraints

- Execute implementation inline; use a read-only independent subagent only at the two checkpoints identified below.
- Work only in `C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture` on `feature/p8a-voice-architecture`.
- Preserve all unrelated dirty P8-H and generated-file changes; stage only exact files listed by the current task.
- Store no plaintext API key in Git, PowerShell source, arguments, environment variables, reports, logs, or chat.
- The runtime supports Windows and the same Windows account that enrolled the DPAPI blobs; WSL, Linux, macOS, remote containers, other accounts, and other machines are out of scope.
- Accept only worktrees whose resolved `git rev-parse --git-common-dir` equals the registered LexiQuest Git common directory. Never authorize by path prefix.
- Runtime installation is explicit, offline, allowlist-only, SHA-256 verified, immutable per source commit, and atomically activated. It never downloads or self-updates.
- Health checks are local-only and make zero provider requests. Real smoke and effort certification remain explicit owner-cost gates.
- Provider calls remain sequential, one-attempt, no retry, no fallback, no effort downgrade, and bounded by the existing context/secret/output gates.
- Provider output is untrusted structured review data and is never executed as commands, patches, or tool calls.
- Stop on the first failure. Run the focused failed gate before a full suite, and do not repeat an unchanged full gate.
- Never invoke Codex Security or repository-wide security analysis. Use a scoped Gitleaks scan of `tool/ai-analysis` plus focused manual diff review.

## File Map and Ownership

- `tool/ai-analysis/lib/repository-root.ps1`: normalize an explicit repository root or the source-tree default; no Git authorization.
- `tool/ai-analysis/lib/project-binding.ps1`: resolve and compare canonical Git common directories.
- `tool/ai-analysis/lib/runtime-installer.ps1`: exact file allowlist, staging, hashing, immutable runtime directory, and atomic activation.
- `tool/ai-analysis/lib/runtime-health.ps1`: manifest/hash/project/DPAPI/ACL checks with sanitized results and no network access.
- `tool/ai-analysis/runtime/lexiquest-ai-analysis.ps1`: stable command dispatcher copied to the machine-local `bin` directory.
- `tool/ai-analysis/install-project-runtime.ps1`: project-owned installation entrypoint.
- `tool/ai-analysis/invoke-analysis.ps1` and `tool/ai-analysis/test-provider-smoke.ps1`: accept the active worktree root from the installed launcher.
- `AGENTS.md`: repository guardrails plus Desktop/CLI discovery and invocation policy.
- `tool/ai-analysis/README.md`: owner installation, enrollment, CLI, rotation, update, rollback, and removal commands.
- `tool/ai-analysis/tests/repository-root.tests.ps1`: repository-root behavior and entrypoint wiring.
- `tool/ai-analysis/tests/project-binding.tests.ps1`: Git binding and path-confusion regression coverage.
- `tool/ai-analysis/tests/runtime-installer.tests.ps1`: copy/hash/atomicity/rollback coverage.
- `tool/ai-analysis/tests/runtime-launcher.tests.ps1`: local health, dispatch, DPAPI, ACL, and failure taxonomy coverage.
- `tool/ai-analysis/tests/documentation.tests.ps1`: repository discovery contract and operator-command coverage.

---

### Task 1: Decouple Analysis Output from the Source Worktree

**Files:**
- Create: `tool/ai-analysis/lib/repository-root.ps1`
- Create: `tool/ai-analysis/tests/repository-root.tests.ps1`
- Modify: `tool/ai-analysis/invoke-analysis.ps1`
- Modify: `tool/ai-analysis/test-provider-smoke.ps1`

**Interfaces:**
- Consumes: a caller-supplied repository/worktree directory or the public script's source-tree default.
- Produces: `Resolve-AiAnalysisRepositoryRoot -RepositoryRoot <string> -DefaultRoot <string> -> absolute directory string`; public `-RepositoryRoot` parameters used by the stable launcher in Task 4.

- [ ] **Step 1: Write five failing repository-root and entrypoint tests**

Add `repository-root.tests.ps1` with a temporary directory and these exact assertions:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\repository-root.ps1')

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-root-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($tempRoot) | Out-Null
try {
    Invoke-AiAnalysisTest 'uses the source-tree default when no root is supplied' {
        Assert-Equal ([IO.Path]::GetFullPath($tempRoot)) (Resolve-AiAnalysisRepositoryRoot -RepositoryRoot '' -DefaultRoot $tempRoot) 'default root'
    }
    Invoke-AiAnalysisTest 'normalizes an explicit worktree root' {
        $nested = Join-Path $tempRoot 'nested\..'
        Assert-Equal ([IO.Path]::GetFullPath($tempRoot)) (Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $nested -DefaultRoot 'unused') 'explicit root'
    }
    Invoke-AiAnalysisTest 'rejects a missing root' {
        Assert-Throws { Resolve-AiAnalysisRepositoryRoot -RepositoryRoot (Join-Path $tempRoot 'missing') -DefaultRoot $tempRoot } 'repositoryRootNotFound'
    }
    Invoke-AiAnalysisTest 'rejects a file as a root' {
        $file = Join-Path $tempRoot 'file.txt'; [IO.File]::WriteAllText($file, 'x')
        Assert-Throws { Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $file -DefaultRoot $tempRoot } 'repositoryRootNotFound'
    }
    Invoke-AiAnalysisTest 'wires both public commands through the resolver' {
        foreach ($name in @('invoke-analysis.ps1', 'test-provider-smoke.ps1')) {
            $source = Get-Content -LiteralPath (Join-Path $PSScriptRoot "..\$name") -Raw -Encoding utf8
            Assert-Match 'RepositoryRoot' $source "$name exposes root"
            Assert-Match 'Resolve-AiAnalysisRepositoryRoot' $source "$name resolves root"
        }
    }
} finally {
    [IO.Directory]::Delete($tempRoot, $true)
}
Complete-AiAnalysisTests -SuiteName 'Repository root tests'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/repository-root.tests.ps1
```

Expected: FAIL while dot-sourcing missing `lib/repository-root.ps1`.

- [ ] **Step 3: Implement the minimal resolver and wire both public scripts**

Create `repository-root.ps1`:

```powershell
Set-StrictMode -Version Latest

function Resolve-AiAnalysisRepositoryRoot {
    [CmdletBinding()]
    param([string]$RepositoryRoot, [Parameter(Mandatory)][string]$DefaultRoot)

    $candidate = if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $DefaultRoot } else { $RepositoryRoot }
    try { $resolved = [IO.Path]::GetFullPath($candidate) } catch { throw 'repositoryRootNotFound' }
    if (-not [IO.Directory]::Exists($resolved)) { throw 'repositoryRootNotFound' }
    return $resolved.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}
```

In both public scripts, add `[string]$RepositoryRoot = ''`, dot-source `lib\repository-root.ps1`, and replace the hardcoded root with:

```powershell
$defaultRepositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repositoryRoot = Resolve-AiAnalysisRepositoryRoot -RepositoryRoot $RepositoryRoot -DefaultRoot $defaultRepositoryRoot
```

Keep all existing parameters and command calls unchanged; pass `$repositoryRoot` to the existing command function.

- [ ] **Step 4: Run focused and existing command tests**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/repository-root.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/orchestrator.tests.ps1
```

Expected: `Repository root tests: 5 passed, 0 failed` and `Orchestrator tests: 14 passed, 0 failed`.

- [ ] **Step 5: Commit Task 1 only**

```powershell
git add -- tool/ai-analysis/lib/repository-root.ps1 tool/ai-analysis/tests/repository-root.tests.ps1 tool/ai-analysis/invoke-analysis.ps1 tool/ai-analysis/test-provider-smoke.ps1
git diff --cached --check
git commit -m "refactor(ai-analysis): accept active repository root"
```

---

### Task 2: Bind the Runtime to LexiQuest Git Worktrees

**Files:**
- Create: `tool/ai-analysis/lib/project-binding.ps1`
- Create: `tool/ai-analysis/tests/project-binding.tests.ps1`

**Interfaces:**
- Consumes: an existing working directory, the installed manifest's expected Git common directory, and optionally an injected Git invoker for tests.
- Produces: `Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory <string> -GitInvoker <scriptblock> -> canonical string`; `Assert-AiAnalysisProjectBinding -WorkingDirectory <string> -ExpectedGitCommonDirectory <string> -GitInvoker <scriptblock> -> canonical string`.

- [ ] **Step 1: Write six failing project-binding tests**

Use a fake Git invoker that returns a relative `.git` path, an absolute common directory, or a failure object. Cover exact match, case-insensitive Windows match, unrelated repository rejection, path-prefix rejection (`LexiQuest-copy`), Git failure, and missing working directory. The central assertions must be:

```powershell
$gitInvoker = { param($workingDirectory) [pscustomobject]@{ ExitCode = 0; Output = '..\shared\.git' } }
$resolved = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory (Join-Path $tempRoot 'worktree') -GitInvoker $gitInvoker
Assert-Equal ([IO.Path]::GetFullPath((Join-Path $tempRoot 'shared\.git'))) $resolved 'relative git common dir'

Assert-Equal $resolved (Assert-AiAnalysisProjectBinding -WorkingDirectory (Join-Path $tempRoot 'worktree') -ExpectedGitCommonDirectory $resolved -GitInvoker $gitInvoker) 'exact binding'
Assert-Throws { Assert-AiAnalysisProjectBinding -WorkingDirectory $otherRoot -ExpectedGitCommonDirectory $resolved -GitInvoker $otherGitInvoker } 'projectMismatch'
Assert-Throws { Assert-AiAnalysisProjectBinding -WorkingDirectory $prefixRoot -ExpectedGitCommonDirectory $resolved -GitInvoker $prefixGitInvoker } 'projectMismatch'
Assert-Throws { Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $tempRoot -GitInvoker { [pscustomobject]@{ ExitCode = 128; Output = '' } } } 'gitCommonDirectoryUnavailable'
Assert-Throws { Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory (Join-Path $tempRoot 'missing') -GitInvoker $gitInvoker } 'repositoryRootNotFound'
```

- [ ] **Step 2: Run the focused test and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/project-binding.tests.ps1`.

Expected: FAIL while dot-sourcing missing `lib/project-binding.ps1`.

- [ ] **Step 3: Implement canonical Git common-directory resolution**

Implement the default invoker without a shell-built command string:

```powershell
function Invoke-AiAnalysisGitCommonDirectory {
    param([Parameter(Mandatory)][string]$WorkingDirectory)
    $output = & git -C $WorkingDirectory rev-parse --git-common-dir 2>$null
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = [string]($output | Select-Object -First 1) }
}

function Resolve-AiAnalysisGitCommonDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkingDirectory, [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory})
    if (-not [IO.Directory]::Exists($WorkingDirectory)) { throw 'repositoryRootNotFound' }
    $workingRoot = [IO.Path]::GetFullPath($WorkingDirectory)
    $result = & $GitInvoker $workingRoot
    if ($null -eq $result -or [int]$result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace([string]$result.Output)) { throw 'gitCommonDirectoryUnavailable' }
    $candidate = [string]$result.Output
    if (-not [IO.Path]::IsPathRooted($candidate)) { $candidate = Join-Path $workingRoot $candidate }
    return [IO.Path]::GetFullPath($candidate).TrimEnd('\', '/')
}

function Assert-AiAnalysisProjectBinding {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WorkingDirectory, [Parameter(Mandatory)][string]$ExpectedGitCommonDirectory, [scriptblock]$GitInvoker = ${function:Invoke-AiAnalysisGitCommonDirectory})
    $actual = Resolve-AiAnalysisGitCommonDirectory -WorkingDirectory $WorkingDirectory -GitInvoker $GitInvoker
    $expected = [IO.Path]::GetFullPath($ExpectedGitCommonDirectory).TrimEnd('\', '/')
    if (-not [string]::Equals($actual, $expected, [StringComparison]::OrdinalIgnoreCase)) { throw 'projectMismatch' }
    return $actual
}
```

- [ ] **Step 4: Run the focused binding tests**

Expected command and result:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/project-binding.tests.ps1
# Project binding tests: 6 passed, 0 failed
```

- [ ] **Step 5: Commit Task 2 only**

```powershell
git add -- tool/ai-analysis/lib/project-binding.ps1 tool/ai-analysis/tests/project-binding.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): bind runtime to LexiQuest git directory"
```

---

### Task 3: Install and Atomically Activate an Immutable Runtime

**Files:**
- Create: `tool/ai-analysis/lib/runtime-installer.ps1`
- Create: `tool/ai-analysis/tests/runtime-installer.tests.ps1`

**Interfaces:**
- Consumes: source root, project root, optional install root, resolved source commit, and Task 2's Git binding function.
- Produces: `Get-AiAnalysisRuntimeRelativePaths -> string[]`; `Install-AiAnalysisProjectRuntime -SourceRoot -ProjectRoot -InstallRoot -SourceCommit -GitInvoker -UtcNow -> sanitized manifest object`.
- Manifest: schema `1`, project ID `lexiquest`, source commit, canonical project root, canonical Git common directory, absolute runtime path, UTC installation time, and sorted `{ path, sha256 }` entries.

- [ ] **Step 1: Write seven failing installer tests**

Build a complete fake source tree from `Get-AiAnalysisRuntimeRelativePaths`, placing deterministic text in every file. Assert:

```powershell
$expectedPaths = @(
  'config.json','initialize-secrets.ps1','invoke-analysis.ps1','remove-secrets.ps1','test-provider-smoke.ps1',
  'lib\analysis-command.ps1','lib\config.ps1','lib\context-builder.ps1','lib\effort-router.ps1','lib\maxplus-client.ps1',
  'lib\project-binding.ps1','lib\repository-root.ps1','lib\report-writer.ps1','lib\reviewer.ps1','lib\runtime-health.ps1',
  'lib\secret-store.ps1','lib\smoke-command.ps1'
)
Assert-Equal $expectedPaths @(Get-AiAnalysisRuntimeRelativePaths) 'exact allowlist'
```

Then test: only allowlisted files are copied; all manifest hashes match `Get-FileHash -Algorithm SHA256`; `active-runtime.json` points to the commit runtime and pins `runtimeManifestSha256`; a missing allowlisted source file throws `runtimeSourceIncomplete` and preserves the previous active manifest byte-for-byte; reinstalling the same commit verifies/reuses the immutable directory; a conflicting existing same-commit directory throws `runtimeIntegrityFailure`; and no `.staging-*` directory remains after success or failure.

- [ ] **Step 2: Run the installer test and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/runtime-installer.tests.ps1`.

Expected: FAIL while dot-sourcing missing `lib/runtime-installer.ps1`.

- [ ] **Step 3: Implement the exact allowlist and manifest hashing**

Use a literal allowlist matching Step 1. Reject a source commit unless it matches `^[a-f0-9]{40}$`. Resolve all roots with `GetFullPath`. For each source file, require `File.Exists`, copy into `$InstallRoot\runtime\.$SourceCommit.staging-<guid>`, and build sorted hash records:

```powershell
$hashRecords = @($relativePaths | ForEach-Object {
    $installedPath = Join-Path $stagingRoot $_
    [pscustomobject]@{
        path = ($_ -replace '\\', '/')
        sha256 = (Get-FileHash -LiteralPath $installedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
} | Sort-Object path)
```

Write `runtime-manifest.json` inside staging using UTF-8 without BOM and JSON depth 8. Its `runtimePath` must be the final immutable path, never the staging path. Compute the completed manifest's SHA-256 and store that digest as `runtimeManifestSha256` in `active-runtime.json`; health must verify this digest before trusting any per-file hash from the runtime manifest.

- [ ] **Step 4: Implement immutable activation and rollback**

If the final runtime directory exists, verify every manifest entry and reuse it only when all hashes match. Otherwise move the completed staging directory to `runtime\<SourceCommit>`. Write `active-runtime.json` to a sibling temporary file, then activate with `File.Replace` plus a backup when active exists, or `File.Move` when it does not. Remove only task-owned staging/temp/backup paths in `finally`; never recursively delete the install root or an unresolved path.

Return only:

```powershell
[pscustomobject]@{
    ProjectId = 'lexiquest'
    SourceCommit = $SourceCommit
    RuntimePath = $finalRuntimeRoot
    GitCommonDirectory = $gitCommonDirectory
    InstalledAtUtc = $installedAtUtc
}
```

- [ ] **Step 5: Run installer and secret-store regression tests**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/runtime-installer.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/secret-store.tests.ps1
```

Expected: `Runtime installer tests: 7 passed, 0 failed` and `Secret store tests: 8 passed, 0 failed`.

- [ ] **Step 6: Commit Task 3 only**

```powershell
git add -- tool/ai-analysis/lib/runtime-installer.ps1 tool/ai-analysis/tests/runtime-installer.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): install immutable local runtime"
```

- [ ] **Checkpoint A: independent read-only architecture review**

Ask one independent reviewer to inspect only Tasks 1-3 for root confusion, path traversal, Git binding bypass, unsafe recursive operations, non-atomic activation, manifest/hash gaps, and Windows PowerShell 5.1 incompatibility. Do not let the reviewer edit files or run repository-wide/security analysis. Resolve each P0-P2 finding with a focused failing test, rerun only affected suites, and commit the fixes before Task 4.

---

### Task 4: Add Local-Only Health and the Stable Command Dispatcher

**Files:**
- Create: `tool/ai-analysis/lib/runtime-health.ps1`
- Create: `tool/ai-analysis/runtime/lexiquest-ai-analysis.ps1`
- Create: `tool/ai-analysis/tests/runtime-launcher.tests.ps1`
- Modify: `tool/ai-analysis/lib/runtime-installer.ps1`

**Interfaces:**
- Consumes: active manifest, runtime manifest, Task 2 binding, existing DPAPI secret store, and exact public commands.
- Produces: `Test-AiAnalysisProjectRuntime -InstallRoot -ProjectRoot -RequireSecrets -> sanitized health object`; launcher commands `Health`, `Analyze`, `Smoke`, `CertifyEfforts`, `Initialize`, and `Remove`.

- [ ] **Step 1: Write eight failing health/launcher tests**

Install a real test runtime beneath a temporary install root and create two valid DPAPI blobs using `Save-AiAnalysisSecret -DestinationRoot`. Cover:

1. Ready health returns only `Status`, `ProjectId`, `SourceCommit`, and `Providers`.
2. An injected web transport counter remains zero during health.
3. Missing GPT or Claude blob throws `secretNotFound`.
4. Corrupt DPAPI text throws `secretDecryptFailed`.
5. A modified installed file throws `runtimeIntegrityFailure`.
6. Another Git common directory throws `projectMismatch`.
7. Each allowed launcher command resolves to exactly one public script and passes explicit `RepositoryRoot` for Analyze/Smoke/CertifyEfforts.
8. An unknown command or remaining unparsed argument throws `invalidRuntimeCommand` before dispatch.

The subprocess assertion for ready health must be:

```powershell
$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $launcher -Command Health -ProjectRoot $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'health subprocess failed' }
$health = $json | ConvertFrom-Json
Assert-Equal 'ready' $health.Status 'ready health'
Assert-Equal @('gpt-stable','claude-reviewer') @($health.Providers) 'provider ids only'
Assert-Equal @('ProjectId','Providers','SourceCommit','Status') @($health.PSObject.Properties.Name | Sort-Object) 'sanitized health shape'
```

- [ ] **Step 2: Run the focused launcher test and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/runtime-launcher.tests.ps1`.

Expected: FAIL because `lib/runtime-health.ps1` and `runtime/lexiquest-ai-analysis.ps1` do not exist.

- [ ] **Step 3: Implement manifest, binding, hash, DPAPI, and ACL health checks**

`Test-AiAnalysisProjectRuntime` must:

```powershell
$activePath = Join-Path $InstallRoot 'active-runtime.json'
if (-not [IO.File]::Exists($activePath)) { throw 'runtimeMissing' }
$active = Get-Content -LiteralPath $activePath -Raw -Encoding utf8 | ConvertFrom-Json
if ([int]$active.schemaVersion -ne 1 -or $active.projectId -cne 'lexiquest') { throw 'runtimeIntegrityFailure' }
$null = Assert-AiAnalysisProjectBinding -WorkingDirectory $ProjectRoot -ExpectedGitCommonDirectory $active.gitCommonDirectory
```

Require `runtimePath` to equal `%InstallRoot%\runtime\<sourceCommit>` after canonicalization. Load `runtime-manifest.json`, require exact project/commit/common-directory agreement, and verify every listed file hash plus the exact allowlist count. Reject extra manifest entries. When `-RequireSecrets` is set, read both known blobs from `$InstallRoot\secrets`, validate secure-string shape, and check directory/file ACL inheritance and principals against current user SID plus `S-1-5-18`. Clear secure-string and ACL references in `finally`. Do not dot-source or call `maxplus-client.ps1`; health must have no network-capable dependency.

Return:

```powershell
[pscustomobject][ordered]@{
    Status = 'ready'
    ProjectId = 'lexiquest'
    SourceCommit = [string]$active.sourceCommit
    Providers = @('gpt-stable', 'claude-reviewer')
}
```

- [ ] **Step 4: Implement the stable dispatcher with exact parameter projection**

The launcher declares explicit parameters only:

```powershell
param(
  [Parameter(Mandatory)][ValidateSet('Health','Analyze','Smoke','CertifyEfforts','Initialize','Remove')][string]$Command,
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$Task,
  [string[]]$Path = @(),
  [ValidateSet('Auto','Low','Medium','High','XHigh','ExtraHigh','ExtendedHigh','Max','Ultra')][string]$Effort = 'Auto',
  [ValidateSet('All','GptStable','ClaudeReviewer')][string]$Provider = 'All',
  [switch]$ChangedFiles, [switch]$NoReviewer, [switch]$NoReport,
  [ValidateRange(5,600)][int]$TimeoutSeconds = 120
)
```

Derive `$InstallRoot` from the launcher's installed location with `[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))`; do not accept it as a public parameter. Resolve and validate the active runtime before dispatch. `Health`, `Analyze`, `Smoke`, and `CertifyEfforts` require both secrets; `Initialize` and `Remove` verify runtime integrity and project binding without requiring secrets. Dispatch with a literal `switch` and parameter splats; never use `Invoke-Expression`, a generated command string, or remaining arguments. `Analyze` requires nonblank `Task`. `Smoke` must reject analysis-only switches. `CertifyEfforts` calls `test-provider-smoke.ps1 -CertifyEfforts`. `Initialize` passes `Provider` and `TimeoutSeconds`; `Remove` passes only `Provider`.

Emit health JSON using `ConvertTo-Json -Compress`; do not emit manifest paths, common-directory paths, ACL identities, prompts, responses, or account data.

- [ ] **Step 5: Teach the installer to activate the stable launcher atomically**

Require `runtime\lexiquest-ai-analysis.ps1` in the source tree but exclude it from the runtime file hash allowlist. Stage the new launcher and the new active manifest before changing either destination. Replace or move `bin\lexiquest-ai-analysis.ps1` first while retaining an exact backup, then atomically replace `active-runtime.json`; if active-manifest replacement fails, restore the previous launcher before returning the error. Remove the backup only after both destinations validate. Add the staged launcher's SHA-256 to `active-runtime.json` as `launcherSha256`, and make the launcher verify its own hash plus `runtimeManifestSha256` before dispatch. This ordering prevents a completed installation from publishing a manifest that references a launcher that was never activated.

- [ ] **Step 6: Run all focused runtime suites**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/runtime-installer.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/runtime-launcher.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/project-binding.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/secret-store.tests.ps1
```

Expected: installer 7/0, launcher 8/0, binding 6/0, secret store 8/0.

- [ ] **Step 7: Commit Task 4 only**

```powershell
git add -- tool/ai-analysis/lib/runtime-health.ps1 tool/ai-analysis/runtime/lexiquest-ai-analysis.ps1 tool/ai-analysis/tests/runtime-launcher.tests.ps1 tool/ai-analysis/lib/runtime-installer.ps1 tool/ai-analysis/tests/runtime-installer.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): add project runtime launcher"
```

---

### Task 5: Add Installation, AGENTS Discovery, and Operator Documentation

**Files:**
- Create: `tool/ai-analysis/install-project-runtime.ps1`
- Create: `AGENTS.md` on the feature branch, preserving the five existing LexiQuest guardrail bullets from the canonical checkout
- Modify: `tool/ai-analysis/README.md`
- Modify: `tool/ai-analysis/tests/documentation.tests.ps1`

**Interfaces:**
- Consumes: Tasks 2-4 installation/runtime interfaces.
- Produces: one owner install command and one stable Desktop/CLI launcher contract discoverable in every new LexiQuest session.

- [ ] **Step 1: Extend documentation tests before writing docs or installer**

Assert the installer dot-sources `project-binding.ps1` and `runtime-installer.ps1`, obtains a full 40-character source commit with `git rev-parse HEAD`, and never accepts a key parameter. Assert `AGENTS.md` contains the exact launcher suffix `LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1`, commands `Health` and `Analyze`, Desktop and CLI wording, the native-Codex continuation rule, untrusted-output rule, no-paste rule, and all existing Codex Security guardrails. Assert README contains exact install, health, analyze, initialize, rotate, smoke, certify, update, rollback, and remove examples.

The key source-safety assertions are:

```powershell
$installer = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\install-project-runtime.ps1') -Raw -Encoding utf8
Assert-Match 'git\s+-C\s+\$ProjectRoot\s+rev-parse\s+HEAD' $installer 'source commit resolved by argument array'
Assert-False ($installer -match '(?i)apikey|securekey|ccsk-') 'installer accepts no secret'

$agents = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\..\AGENTS.md') -Raw -Encoding utf8
Assert-Match 'Codex Desktop' $agents 'Desktop discovery'
Assert-Match 'Codex CLI' $agents 'CLI discovery'
Assert-Match 'Never ask the user to paste' $agents 'no chat secret'
```

- [ ] **Step 2: Run documentation tests and verify RED**

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/documentation.tests.ps1`.

Expected: FAIL because installer and feature-branch `AGENTS.md` are absent.

- [ ] **Step 3: Implement the owner installation entrypoint**

Use these parameters and no secret parameters:

```powershell
param([string]$ProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')))
```

Require Windows, `LOCALAPPDATA`, Git, and a clean 40-character lowercase commit from `& git -C $ProjectRoot rev-parse HEAD`. Resolve `$InstallRoot` internally as `Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis'`; do not expose an installation-root parameter. Before copying, run `git -C $ProjectRoot status --porcelain --untracked-files=all -- tool/ai-analysis` and throw `runtimeSourceDirty` when any allowlisted source or launcher is modified or untracked. Call `Install-AiAnalysisProjectRuntime -SourceRoot $PSScriptRoot -ProjectRoot $ProjectRoot -InstallRoot $InstallRoot -SourceCommit $sourceCommit`. Print only project ID, source commit, and status `installed`; do not print secret/runtime/common-directory paths.

- [ ] **Step 4: Create the project discovery contract in AGENTS.md**

Preserve the existing five `LexiQuest Codex Guardrails` bullets exactly. Add `LexiQuest Local AI Analysis` rules that require new Desktop/CLI sessions to resolve the launcher beneath `$env:LOCALAPPDATA`, run local-only `Health` before first use, use GPT as bounded analyst and Claude only at independent checkpoints, verify findings locally, never paste/request/export keys, continue with native Codex and report a stable category when health is unavailable, and never auto-install/retry/fallback/downgrade.

Include these canonical examples:

```powershell
$launcher = Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1'
& $launcher -Command Health -ProjectRoot (Get-Location).Path
& $launcher -Command Analyze -ProjectRoot (Get-Location).Path -Task 'Review the current bounded change' -ChangedFiles
```

- [ ] **Step 5: Document the complete one-time and recurring workflow**

Add README commands for:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/install-project-runtime.ps1
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Health -ProjectRoot (Get-Location).Path
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Analyze -ProjectRoot (Get-Location).Path -Task 'Review provider cancellation' -ChangedFiles
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Smoke -ProjectRoot (Get-Location).Path
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command CertifyEfforts -ProjectRoot (Get-Location).Path
```

Document update as rerunning install from a reviewed commit; rollback as rerunning install from the prior reviewed checkout/commit; rotation as `Initialize -Provider GptStable` or `ClaudeReviewer`; removal as `Remove -Provider All`. State that starting a new chat or CLI session runs only Health and never repeats smoke/certification.

- [ ] **Step 6: Run documentation and full bounded tests once**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/documentation.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1
```

Expected: `Documentation tests: 1 passed, 0 failed`; every suite has zero failures; final line `AI analysis tests: 11 files passed`.

- [ ] **Step 7: Commit Task 5 only**

```powershell
git add -- AGENTS.md tool/ai-analysis/install-project-runtime.ps1 tool/ai-analysis/README.md tool/ai-analysis/tests/documentation.tests.ps1
git diff --cached --check
git commit -m "feat(ai-analysis): expose runtime to new Codex sessions"
```

- [ ] **Checkpoint B: independent read-only integration review**

Ask one independent reviewer to inspect only Task 4-5 changes plus their interfaces to Tasks 1-3. Check DPAPI/ACL lifetime, health's zero-network boundary, manifest/launcher integrity, strict command projection, Desktop/CLI discoverability, preservation of repository guardrails, and absence of secret-bearing parameters. Resolve P0-P2 findings with focused failing tests and exact-file commits before Task 6.

---

### Task 6: Install Once and Prove Desktop/CLI Cross-Chat Readiness

**Files:**
- No repository source changes expected
- Machine-local outputs: `%LOCALAPPDATA%\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1`, `active-runtime.json`, `runtime\<commit>\`, and two DPAPI blobs
- Untracked verification outputs only: `build/ai-analysis/smoke/` and `build/ai-analysis/reports/`

**Interfaces:**
- Consumes: the committed installer, stable launcher, owner-entered GPT/Claude inference keys, and an existing registered LexiQuest worktree.
- Produces: a locally ready runtime shared by new Codex Desktop and CLI sessions under the current Windows account.

- [ ] **Step 1: Run the final source gate before local installation**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/tests/run-tests.ps1
git diff --check -- tool/ai-analysis AGENTS.md
gitleaks detect --no-banner --redact --no-git --source tool/ai-analysis
```

Expected: 11 test files pass, diff check has no output, and scoped Gitleaks reports `no leaks found`. Do not run a repository-history scan.

- [ ] **Step 2: Install the reviewed commit once**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/ai-analysis/install-project-runtime.ps1 -ProjectRoot (Get-Location).Path
```

Expected sanitized output: `ProjectId: lexiquest`, the current 40-character commit, and `Status: installed`; no key, identity, account, or absolute runtime path.

- [ ] **Step 3: Enroll both keys once through the secure prompt**

```powershell
& "$env:LOCALAPPDATA\LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1" -Command Initialize -ProjectRoot (Get-Location).Path -Provider All
```

The owner enters GPT Pro 20x Stable and AWS Lite Ultimate inference keys in the secure prompt. Expected: both account/model gates pass and two DPAPI blobs exist. Inspect only `Name`, `Length`, `LastWriteTimeUtc`, and ACL metadata; never call `Get-Content` on a blob.

- [ ] **Step 4: Prove local-only health from the canonical checkout and another worktree**

```powershell
$launcher = Join-Path $env:LOCALAPPDATA 'LexiQuest\ai-analysis\bin\lexiquest-ai-analysis.ps1'
& $launcher -Command Health -ProjectRoot 'C:\Users\Phet\Documents\LexiQuest'
& $launcher -Command Health -ProjectRoot 'C:\Users\Phet\Documents\LexiQuest\.worktrees\p8a-voice-architecture'
```

Expected for both: the same `ready`, `lexiquest`, source commit, and two provider IDs. Confirm MaxPlus request counters/evidence timestamps did not change during health.

- [ ] **Step 5: Prove project isolation**

Create a temporary non-LexiQuest Git repository outside the workspace, run only Health against it, and expect `projectMismatch`. Remove only that resolved temporary directory after confirming it is outside both workspace roots. Do not copy DPAPI blobs or runtime files into the temporary repository.

- [ ] **Step 6: Run one explicit real-provider smoke and effort certification**

```powershell
& $launcher -Command Smoke -ProjectRoot (Get-Location).Path -TimeoutSeconds 120
& $launcher -Command CertifyEfforts -ProjectRoot (Get-Location).Path -TimeoutSeconds 120
```

Expected: GPT and Claude Low smoke pass; each configured effort is recorded exactly once as `supported` or `unsupportedEffort`; no retry, downgrade, fallback, prompt, response, key, identity, or account envelope appears in evidence.

- [ ] **Step 7: Prove one bounded project analysis and no-report mode**

Use explicit committed source paths so unrelated dirty P8-H files cannot exceed the changed-file cap:

```powershell
& $launcher -Command Analyze -ProjectRoot (Get-Location).Path -Task 'Review the project-scoped runtime binding and secret boundaries' -Path @('tool/ai-analysis/lib/project-binding.ps1','tool/ai-analysis/lib/runtime-installer.ps1','tool/ai-analysis/lib/runtime-health.ps1','tool/ai-analysis/runtime/lexiquest-ai-analysis.ps1') -Effort High
& $launcher -Command Analyze -ProjectRoot (Get-Location).Path -Task 'Verify local-only health output boundary' -Path @('tool/ai-analysis/lib/runtime-health.ps1','tool/ai-analysis/tests/runtime-launcher.tests.ps1') -Effort Medium -NoReport
```

Expected: first command writes one normalized report; second returns a normalized result without creating a report. Review findings locally before accepting them.

- [ ] **Step 8: Prove a fresh Codex CLI session discovers the contract**

From `C:\Users\Phet\Documents\LexiQuest`, start a fresh `codex` CLI session under the same Windows user and ask it only to check the LexiQuest local AI runtime health. Expected: it reads `AGENTS.md`, invokes the stable launcher with `-Command Health`, reports `ready`, does not ask for a key, and does not call either provider.

- [ ] **Step 9: Final acceptance report**

Report the source commit, runtime source commit, launcher health result, two blob metadata records, canonical/worktree health results, project-mismatch result, smoke/certification matrix, bounded analysis result, CLI discovery result, 11-suite test result, and scoped Gitleaks result. Do not claim cross-machine, WSL, remote-container, public-production, or model-selector support.

Do not create another source commit unless a focused acceptance failure requires a code change. If source changes, reinstall the new commit and rerun only the affected focused gate, then Health from both roots and one smoke per provider.

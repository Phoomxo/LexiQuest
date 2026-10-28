Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')

Invoke-AiAnalysisTest 'README documents the complete secure operator contract' {
    $readmePath = Join-Path $PSScriptRoot '..\README.md'
    Assert-True (Test-Path -LiteralPath $readmePath -PathType Leaf) 'README exists'
    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding utf8
    $requiredPatterns = @(
        '%LOCALAPPDATA%\\LexiQuest\\ai-analysis\\secrets\\gpt-stable\.dpapi',
        '%LOCALAPPDATA%\\LexiQuest\\ai-analysis\\secrets\\claude-reviewer\.dpapi',
        'GPT Pro 20x Stable.*gpt-5\.6-sol',
        'AWS Lite Ultimate.*claude-sonnet-5',
        'AWS Lite Ultimate.*claude-opus-5',
        'focusedPackage',
        'architectureSensitive',
        'releaseBlocker',
        'initialize-secrets\.ps1',
        'rotate',
        'remove-secrets\.ps1',
        'invoke-analysis\.ps1.*-ChangedFiles',
        'invoke-analysis\.ps1.*-Path',
        '-NoReport',
        'test-provider-smoke\.ps1',
        'no automatic retry',
        'no automatic fallback',
        'remote.*revoke|revoke.*remote',
        '14 days',
        'cannot mutate files',
        'cannot execute tools'
    )
    foreach ($pattern in $requiredPatterns) {
        Assert-Match $pattern $readme "README requirement $pattern"
    }
    Assert-NotMatch 'aws-lite-ultimate/claude-opus-5' $readme 'obsolete pool-prefixed Claude model removed'
}

Invoke-AiAnalysisTest 'project runtime is installable and discoverable from Desktop and CLI' {
    $installerPath = Join-Path $PSScriptRoot '..\install-project-runtime.ps1'
    $agentsPath = Join-Path $PSScriptRoot '..\..\..\AGENTS.md'
    $readmePath = Join-Path $PSScriptRoot '..\README.md'
    Assert-True (Test-Path -LiteralPath $installerPath -PathType Leaf) 'runtime installer exists'
    Assert-True (Test-Path -LiteralPath $agentsPath -PathType Leaf) 'AGENTS exists'

    $installer = Get-Content -LiteralPath $installerPath -Raw -Encoding utf8
    Assert-Match 'project-binding\.ps1' $installer 'installer loads project binding'
    Assert-Match 'runtime-installer\.ps1' $installer 'installer loads runtime installer'
    Assert-Match 'rev-parse\s+--show-toplevel' $installer 'source and requested top levels resolved'
    Assert-Match 'git\s+-C\s+\$sourceWorktreeRoot\s+rev-parse\s+HEAD' $installer 'source commit resolved from source worktree'
    Assert-Match ':\(top\)tool/ai-analysis' $installer 'dirty check anchored to repository top'
    Assert-Match 'Assert-AiAnalysisProjectBinding' $installer 'requested worktree shares source Git binding'
    Assert-False ($installer -match '(?i)apikey|securekey|ccsk-') 'installer accepts no secret'

    $agents = Get-Content -LiteralPath $agentsPath -Raw -Encoding utf8
    foreach ($pattern in @(
        'Codex Desktop',
        'Codex CLI',
        'LexiQuest\\ai-analysis\\bin\\lexiquest-ai-analysis\.ps1',
        '-Command Health',
        '-Command Analyze',
        'Never ask the user to paste',
        'untrusted structured review data',
        'continue with native Codex',
        'Do not invoke, install, resume, or recommend Codex Security',
        'Never run multi-agent implementation concurrently with security or repository-wide analysis'
    )) {
        Assert-Match $pattern $agents "AGENTS requirement $pattern"
    }

    $readme = Get-Content -LiteralPath $readmePath -Raw -Encoding utf8
    foreach ($pattern in @(
        'install-project-runtime\.ps1',
        '-Command Health',
        '-Command Analyze',
        '-Command Initialize',
        '-Provider GptStable',
        '-Provider ClaudeReviewer',
        '-Command Smoke',
        '-Command CertifyEfforts',
        'update',
        'rollback',
        '-Command Remove',
        'new chat.*Health|Health.*new chat',
        'never repeats.*smoke|smoke.*never repeats'
    )) {
        Assert-Match $pattern $readme "runtime README requirement $pattern"
    }
}

Invoke-AiAnalysisTest 'installer pins source bytes to the source worktree commit across nested worktrees' {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('lexiquest-install-command-' + [guid]::NewGuid().ToString('N'))
    $sourceRepo = Join-Path $fixtureRoot 'source-repo'
    $otherWorktree = Join-Path $fixtureRoot 'other-worktree'
    $localData = Join-Path $fixtureRoot 'local-data'
    [IO.Directory]::CreateDirectory((Join-Path $sourceRepo 'tool')) | Out-Null
    [IO.Directory]::CreateDirectory($localData) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..') -Destination (Join-Path $sourceRepo 'tool\ai-analysis') -Recurse
    & git -C $sourceRepo init --quiet
    & git -C $sourceRepo -c core.autocrlf=false add -- tool/ai-analysis
    & git -C $sourceRepo -c user.name=LexiQuestTest -c user.email=test@example.invalid commit --quiet -m 'source A'
    $commitA = ([string](& git -C $sourceRepo rev-parse HEAD)).Trim().ToLowerInvariant()
    & git -C $sourceRepo worktree add --quiet -b fixture-b $otherWorktree
    [IO.File]::WriteAllText((Join-Path $otherWorktree 'branch-marker.txt'), 'B')
    & git -C $otherWorktree -c core.autocrlf=false add -- branch-marker.txt
    & git -C $otherWorktree -c user.name=LexiQuestTest -c user.email=test@example.invalid commit --quiet -m 'source B'
    $nested = Join-Path $otherWorktree 'nested\cwd'
    [IO.Directory]::CreateDirectory($nested) | Out-Null
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = $localData
        $installerPath = Join-Path $sourceRepo 'tool\ai-analysis\install-project-runtime.ps1'
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $installerOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $installerPath -ProjectRoot $nested 2>&1)
        $installerExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousPreference
        if ($installerExitCode -ne 0) { throw "fixture installer failed: $($installerOutput -join ' ')" }
        $active = Get-Content -LiteralPath (Join-Path $localData 'LexiQuest\ai-analysis\active-runtime.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-Equal $commitA ([string]$active.sourceCommit) 'source commit, not target worktree commit'
    } finally {
        $ErrorActionPreference = 'Stop'
        $env:LOCALAPPDATA = $previousLocalAppData
        if ([IO.Directory]::Exists($otherWorktree)) { & git -C $sourceRepo worktree remove --force $otherWorktree 2>$null }
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if ([IO.Directory]::Exists($resolvedFixture) -and $resolvedFixture.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($resolvedFixture) -like 'lexiquest-install-command-*') {
            Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
        }
    }
}

Complete-AiAnalysisTests -Suite 'Documentation'

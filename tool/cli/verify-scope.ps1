#Requires -Version 5.1
<#
.SYNOPSIS
    Runs bounded LexiQuest verification at targeted, subsystem, or release scope.

.DESCRIPTION
    Persists command-level results under build\verification. Resume mode skips
    commands that already passed for the same source fingerprint and reruns only
    commands whose inputs changed or whose previous result did not pass.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Targeted', 'Subsystem', 'Release')]
    [string]$Level,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        'Learning',
        'AI',
        'Voice',
        'Economy',
        'Runtime',
        'BackendAI',
        'BackendVoice',
        'BackendLM',
        'All'
    )]
    [string]$Area,

    [string]$BaseSha = 'HEAD',

    [switch]$Resume
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$timeoutSeconds = @{
    Targeted = 600
    Subsystem = 1200
    Release = 2700
}

function Get-Sha256Text {
    param([string]$Text)

    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return (
            ($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join ''
        )
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-AreaPathPattern {
    param([string]$SelectedArea)

    switch ($SelectedArea) {
        'Learning' {
            return '^(lib/(learning|progress|services/associative_|screens/associative_)|test/(learning|progress|services/associative_|screens/associative_))'
        }
        'AI' {
            return '^(lib/(ai|services/ai_|screens/ai_)|test/(ai|services/ai_|screens/ai_))'
        }
        'Voice' {
            return '^(lib/(voice|services/voice_|screens/.*voice)|test/(voice|services/.*voice|screens/.*voice))'
        }
        'Economy' {
            return '^(lib/(progress|config/remote_economy_policy|screens/(shop|score|achievements|setting))|test/(progress|screens/(shop|score|quiz_score|achievements|setting))|firestore\.rules|test/security/firestore-rules\.test\.cjs|package(-lock)?\.json)'
        }
        'Runtime' {
            return '^(lib/(runtime|config)|test/(runtime|config)|tool/cli/|android/|\.github/workflows/)'
        }
        'BackendAI' { return '^backend/ai_api/' }
        'BackendVoice' { return '^backend/voice_api/' }
        'BackendLM' { return '^backend/lexiquest_lm/' }
        'All' {
            return '^(lib/|test/|backend/|tool/cli/|android/|firestore\.rules|storage\.rules|supabase/|\.github/workflows/|pubspec\.(yaml|lock)|package(-lock)?\.json)'
        }
        default { throw ('Unsupported area: ' + $SelectedArea) }
    }
}

function Get-SourceFingerprint {
    param(
        [string]$SelectedArea,
        [string]$ResolvedBaseSha,
        [string]$CurrentHeadSha
    )

    $pathPattern = Get-AreaPathPattern -SelectedArea $SelectedArea
    $candidatePaths = @(
        & git -C $repoRoot ls-files --cached --others --exclude-standard |
            ForEach-Object { $_ -replace '\\', '/' } |
            Where-Object { $_ -match $pathPattern } |
            Sort-Object -Unique
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add('baseSha=' + $ResolvedBaseSha)
    $parts.Add('headSha=' + $CurrentHeadSha)
    $parts.Add('area=' + $SelectedArea)

    foreach ($relativePath in $candidatePaths) {
        $absolutePath = Join-Path $repoRoot ($relativePath -replace '/', '\')
        if (-not (Test-Path -LiteralPath $absolutePath -PathType Leaf)) {
            continue
        }
        $fileHash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $parts.Add($relativePath + '=' + $fileHash)
    }

    return Get-Sha256Text -Text ($parts -join "`n")
}

function New-CommandSpec {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$SourceArea
    )

    $identity = $FilePath + [char]0 + ($Arguments -join [char]0)
    return [pscustomobject]@{
        Name = $Name
        FilePath = $FilePath
        Arguments = @($Arguments)
        SourceArea = $SourceArea
        commandKey = Get-Sha256Text -Text $identity
    }
}

function Get-ExistingTargets {
    param([string[]]$Candidates)

    return @(
        $Candidates |
            Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) }
    )
}

function New-FlutterTestSpec {
    param(
        [string]$Name,
        [string[]]$Candidates,
        [string]$SourceArea
    )

    $targets = Get-ExistingTargets -Candidates $Candidates
    if ($targets.Count -eq 0) {
        throw ('No Flutter test targets exist for ' + $Name + '.')
    }
    return New-CommandSpec `
        -Name $Name `
        -FilePath 'flutter' `
        -Arguments (@('test') + $targets + @('--reporter', 'compact')) `
        -SourceArea $SourceArea
}

function New-BackendTestSpec {
    param(
        [string]$Name,
        [string]$Project,
        [string]$ExcludedGroup,
        [string]$SourceArea,
        [string[]]$AdditionalPytestArguments = @()
    )

    $arguments = @(
        'run',
        '--project',
        (Join-Path $repoRoot $Project),
        '--frozen',
        '--group',
        'dev',
        '--no-group',
        $ExcludedGroup,
        'pytest',
        (Join-Path $repoRoot ($Project + '\tests')),
        '-q'
    ) + $AdditionalPytestArguments

    return New-CommandSpec `
        -Name $Name `
        -FilePath 'uv' `
        -Arguments $arguments `
        -SourceArea $SourceArea
}

function Get-VerificationCommands {
    param(
        [string]$SelectedLevel,
        [string]$SelectedArea
    )

    if ($SelectedLevel -eq 'Release') {
        if ($SelectedArea -ne 'All') {
            throw 'Release verification requires -Area All.'
        }
        return @(
            New-CommandSpec `
                -Name 'Canonical release verification' `
                -FilePath 'powershell' `
                -Arguments @(
                    '-NoProfile',
                    '-ExecutionPolicy',
                    'Bypass',
                    '-File',
                    (Join-Path $scriptDir 'verify.ps1')
                ) `
                -SourceArea 'All'
        )
    }

    if ($SelectedArea -eq 'All') {
        throw 'Targeted and Subsystem verification require a specific area.'
    }

    $commands = [System.Collections.Generic.List[object]]::new()
    switch ($SelectedArea) {
        'Learning' {
            $commands.Add((New-FlutterTestSpec `
                -Name 'Learning tests' `
                -Candidates @(
                    'test\learning',
                    'test\progress',
                    'test\services\associative_memory_test.dart',
                    'test\screens\associative_reading_session_screen_test.dart'
                ) `
                -SourceArea 'Learning'))
        }
        'AI' {
            $commands.Add((New-FlutterTestSpec `
                -Name 'Flutter AI tests' `
                -Candidates @(
                    'test\ai',
                    'test\services\ai_voice_reading_adapters_test.dart',
                    'test\screens\ai_tutor_screen_test.dart'
                ) `
                -SourceArea 'AI'))
            if ($SelectedLevel -eq 'Subsystem') {
                $commands.Add((New-BackendTestSpec `
                    -Name 'AI API tests' `
                    -Project 'backend\ai_api' `
                    -ExcludedGroup 'llm' `
                    -SourceArea 'BackendAI'))
            }
        }
        'Voice' {
            $commands.Add((New-FlutterTestSpec `
                -Name 'Flutter voice tests' `
                -Candidates @(
                    'test\voice',
                    'test\services\ai_voice_reading_adapters_test.dart',
                    'test\screens\speak_to_text_screen_voice_test.dart'
                ) `
                -SourceArea 'Voice'))
            if ($SelectedLevel -eq 'Subsystem') {
                $commands.Add((New-BackendTestSpec `
                    -Name 'Voice API tests' `
                    -Project 'backend\voice_api' `
                    -ExcludedGroup 'gpu' `
                    -SourceArea 'BackendVoice' `
                    -AdditionalPytestArguments @('--ignore', 'backend\voice_api\tests\integration')))
            }
        }
        'Economy' {
            $commands.Add((New-FlutterTestSpec `
                -Name 'Progress and economy tests' `
                -Candidates @(
                    'test\progress',
                    'test\screens\shop_page_test.dart',
                    'test\screens\score_screen_test.dart',
                    'test\screens\quiz_score_persistence_regression_test.dart',
                    'test\screens\achievements_screen_test.dart',
                    'test\screens\setting_screen_test.dart'
                ) `
                -SourceArea 'Economy'))
            if ($SelectedLevel -eq 'Subsystem') {
                $commands.Add((New-CommandSpec `
                    -Name 'Firestore rules tests' `
                    -FilePath 'npm' `
                    -Arguments @('run', 'test:rules') `
                    -SourceArea 'Economy'))
            }
        }
        'Runtime' {
            $commands.Add((New-FlutterTestSpec `
                -Name 'Runtime and configuration tests' `
                -Candidates @('test\runtime', 'test\config') `
                -SourceArea 'Runtime'))
            if ($SelectedLevel -eq 'Subsystem') {
                $commands.Add((New-CommandSpec `
                    -Name 'CLI contract tests' `
                    -FilePath 'powershell' `
                    -Arguments @(
                        '-NoProfile',
                        '-ExecutionPolicy',
                        'Bypass',
                        '-File',
                        (Join-Path $scriptDir 'tests\verify-scope.tests.ps1')
                    ) `
                    -SourceArea 'Runtime'))
            }
        }
        'BackendAI' {
            $commands.Add((New-BackendTestSpec `
                -Name 'AI API tests' `
                -Project 'backend\ai_api' `
                -ExcludedGroup 'llm' `
                -SourceArea 'BackendAI'))
        }
        'BackendVoice' {
            $commands.Add((New-BackendTestSpec `
                -Name 'Voice API tests' `
                -Project 'backend\voice_api' `
                -ExcludedGroup 'gpu' `
                -SourceArea 'BackendVoice' `
                -AdditionalPytestArguments @('--ignore', 'backend\voice_api\tests\integration')))
        }
        'BackendLM' {
            $commands.Add((New-BackendTestSpec `
                -Name 'Local LM tests' `
                -Project 'backend\lexiquest_lm' `
                -ExcludedGroup 'train' `
                -SourceArea 'BackendLM'))
        }
        default { throw ('Unsupported area: ' + $SelectedArea) }
    }
    return @($commands)
}

function Save-VerificationResult {
    param(
        [object]$Result,
        [string]$Path
    )

    $Result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertTo-PowerShellLiteral {
    param([string]$Value)

    return "'" + $Value.Replace("'", "''") + "'"
}

function Invoke-BoundedCommand {
    param(
        [object]$Command,
        [int]$LimitSeconds,
        [string]$LogDirectory,
        [string]$SourceFingerprint
    )

    $safeName = ($Command.Name -replace '[^A-Za-z0-9._-]', '-').Trim('-')
    $stdoutPath = Join-Path $LogDirectory ($safeName + '.stdout.log')
    $stderrPath = Join-Path $LogDirectory ($safeName + '.stderr.log')
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    $startedAt = [DateTimeOffset]::UtcNow
    $fileLiteral = ConvertTo-PowerShellLiteral -Value $Command.FilePath
    $argumentLiterals = @(
        $Command.Arguments |
            ForEach-Object { ConvertTo-PowerShellLiteral -Value ([string]$_) }
    )
    $wrappedCommand = @(
        "`$ErrorActionPreference = 'Continue'"
        "`$global:LASTEXITCODE = `$null"
        (
            '& ' +
            $fileLiteral +
            ' @(' +
            ($argumentLiterals -join ', ') +
            ') 1> ' +
            (ConvertTo-PowerShellLiteral -Value $stdoutPath) +
            ' 2> ' +
            (ConvertTo-PowerShellLiteral -Value $stderrPath)
        )
        "`$commandSucceeded = `$?"
        'if ($null -ne $LASTEXITCODE) { exit [int]$LASTEXITCODE }'
        'if (-not $commandSucceeded) { exit 1 }'
        'exit 0'
    ) -join "`n"
    $encodedCommand = [Convert]::ToBase64String(
        [System.Text.Encoding]::Unicode.GetBytes($wrappedCommand)
    )
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = 'powershell.exe'
    $processInfo.Arguments =
        '-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' +
        $encodedCommand
    $processInfo.WorkingDirectory = $repoRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    [void]$process.Start()

    $finished = $process.WaitForExit($LimitSeconds * 1000)
    if (-not $finished) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        return [pscustomobject]@{
            Name = $Command.Name
            commandKey = $Command.commandKey
            fingerprint = $SourceFingerprint
            Status = 'TimedOut'
            ExitCode = $null
            StartedAt = $startedAt.ToString('o')
            FinishedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Stdout = $stdoutPath
            Stderr = $stderrPath
        }
    }

    $process.WaitForExit()
    $wrapperError = $process.StandardError.ReadToEnd()
    if (-not [string]::IsNullOrWhiteSpace($wrapperError)) {
        Add-Content -LiteralPath $stderrPath -Value $wrapperError -Encoding UTF8
    }
    $process.Refresh()
    $status = if ($process.ExitCode -eq 0) { 'Passed' } else { 'Failed' }
    return [pscustomobject]@{
        Name = $Command.Name
        commandKey = $Command.commandKey
        fingerprint = $SourceFingerprint
        Status = $status
        ExitCode = $process.ExitCode
        StartedAt = $startedAt.ToString('o')
        FinishedAt = [DateTimeOffset]::UtcNow.ToString('o')
        Stdout = $stdoutPath
        Stderr = $stderrPath
    }
}

Push-Location -LiteralPath $repoRoot
try {
    $resolvedBaseSha = (& git rev-parse --verify ($BaseSha + '^{commit}') 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($resolvedBaseSha)) {
        throw ('Base SHA does not resolve to a commit: ' + $BaseSha)
    }
    $resolvedBaseSha = $resolvedBaseSha.Trim()

    $headSha = (& git rev-parse HEAD 2>$null | Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($headSha)) {
        throw 'Unable to resolve the current HEAD SHA.'
    }
    $headSha = $headSha.Trim()

    $fingerprint = Get-SourceFingerprint `
        -SelectedArea $Area `
        -ResolvedBaseSha $resolvedBaseSha `
        -CurrentHeadSha $headSha

    $resultDirectory = Join-Path $repoRoot ('build\verification\' + $headSha)
    New-Item -ItemType Directory -Force -Path $resultDirectory | Out-Null
    $resultPath = Join-Path $resultDirectory ($Level.ToLowerInvariant() + '-' + $Area.ToLowerInvariant() + '.json')

    $previousByCommand = @{}
    if ($Resume -and (Test-Path -LiteralPath $resultPath)) {
        $previous = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
        if ($null -ne $previous.commands) {
            foreach ($previousCommand in $previous.commands) {
                $previousByCommand[[string]$previousCommand.commandKey] = $previousCommand
            }
        }
    }

    $commands = @(Get-VerificationCommands -SelectedLevel $Level -SelectedArea $Area)
    $result = [ordered]@{
        schemaVersion = 'verify-scope-v1'
        headSha = $headSha
        baseSha = $resolvedBaseSha
        level = $Level
        area = $Area
        fingerprint = $fingerprint
        timeoutSeconds = $timeoutSeconds[$Level]
        startedAt = [DateTimeOffset]::UtcNow.ToString('o')
        finishedAt = $null
        status = 'Running'
        commands = @()
    }

    foreach ($command in $commands) {
        $commandFingerprint = Get-SourceFingerprint `
            -SelectedArea $command.SourceArea `
            -ResolvedBaseSha $resolvedBaseSha `
            -CurrentHeadSha $headSha
        $previousCommand = $previousByCommand[[string]$command.commandKey]
        $previousFingerprintProperty = if ($null -ne $previousCommand) {
            $previousCommand.PSObject.Properties['fingerprint']
        } else {
            $null
        }
        if (
            $null -ne $previousCommand -and
            $previousCommand.Status -eq 'Passed' -and
            $null -ne $previousFingerprintProperty -and
            $previousCommand.fingerprint -eq $commandFingerprint
        ) {
            $result.commands += [pscustomobject]@{
                Name = $previousCommand.Name
                commandKey = $previousCommand.commandKey
                fingerprint = $commandFingerprint
                Status = 'Passed'
                ExitCode = 0
                StartedAt = $previousCommand.StartedAt
                FinishedAt = $previousCommand.FinishedAt
                Stdout = $previousCommand.Stdout
                Stderr = $previousCommand.Stderr
                Resumed = $true
            }
            Write-Host ('SKIP: ' + $command.Name + ' already passed for this fingerprint.') -ForegroundColor DarkGray
            continue
        }

        Write-Host ('RUN: ' + $command.Name) -ForegroundColor Cyan
        $commandResult = Invoke-BoundedCommand `
            -Command $command `
            -LimitSeconds $timeoutSeconds[$Level] `
            -LogDirectory $resultDirectory `
            -SourceFingerprint $commandFingerprint
        $result.commands += $commandResult
        Save-VerificationResult -Result $result -Path $resultPath

        if ($commandResult.Status -ne 'Passed') {
            $result.status = $commandResult.Status
            $result.finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
            Save-VerificationResult -Result $result -Path $resultPath
            Write-Host (
                'FAIL: {0} ({1}); see {2} and {3}' -f
                $commandResult.Name,
                $commandResult.Status,
                $commandResult.Stdout,
                $commandResult.Stderr
            ) -ForegroundColor Red
            exit 1
        }
    }

    $result.status = 'Passed'
    $result.finishedAt = [DateTimeOffset]::UtcNow.ToString('o')
    Save-VerificationResult -Result $result -Path $resultPath
    Write-Host ('PASS: {0}/{1} at {2}' -f $Level, $Area, $headSha) -ForegroundColor Green
    Write-Host ('Result: ' + $resultPath)
    exit 0
}
finally {
    Pop-Location
}

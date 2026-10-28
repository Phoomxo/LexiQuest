#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$ResolveToolsOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$results = @()

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates
    )

    $command = Get-Command -Name $Name -CommandType Application `
        -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) {
        return $command.Source
    }
    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        try {
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
        catch [System.UnauthorizedAccessException] {
            # Managed sandboxes can permit execution of an explicitly approved
            # SDK path while denying metadata probes outside the workspace.
            # The first real invocation remains the executable validation.
            return $candidate
        }
    }
    throw "Required executable '$Name' was not found."
}

$localAppData = [Environment]::GetFolderPath('LocalApplicationData')
$flutterCandidates = @(
    (Join-Path $repoRoot '.fvm/flutter_sdk/bin/flutter.bat')
)
$flutterRoot = [Environment]::GetEnvironmentVariable('FLUTTER_ROOT')
if (-not [string]::IsNullOrWhiteSpace($flutterRoot)) {
    $flutterCandidates += Join-Path $flutterRoot 'bin/flutter.bat'
}
if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
    $flutterCandidates += Join-Path $localAppData 'Programs/flutter/bin/flutter.bat'
}
$flutterExecutable = Resolve-ToolPath -Name 'flutter' -Candidates $flutterCandidates
$flutterBin = Split-Path -Parent $flutterExecutable
$dartExecutable = Resolve-ToolPath -Name 'dart' -Candidates @(
    (Join-Path $flutterBin 'dart.bat'),
    (Join-Path $flutterBin 'cache/dart-sdk/bin/dart.exe')
)

if ($ResolveToolsOnly) {
    Write-Output "Flutter: $flutterExecutable"
    Write-Output "Dart: $dartExecutable"
    exit 0
}

function Invoke-Gate {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    & $Action
    $code = [int]$LASTEXITCODE
    $script:results += [pscustomobject]@{ Name = $Name; ExitCode = $code }
    if ($code -ne 0) {
        throw ("Gate failed: {0} (exit {1})" -f $Name, $code)
    }
}

$dartFiles = @(
    'lib/features/ai_tutor',
    'lib/features/gemini',
    'lib/runtime/app_bootstrap.dart',
    'lib/runtime/app_dependencies.dart',
    'lib/screens/ai_tutor_screen.dart',
    'lib/screens/ai_tutor_settings_screen.dart',
    'lib/screens/gemini_settings_screen.dart',
    'lib/screens/main_navigation_screen.dart',
    'test/features/ai_tutor',
    'test/features/gemini',
    'test/architecture/provider_composition_boundary_test.dart',
    'test/screens/ai_tutor_screen_test.dart',
    'test/screens/gemini_settings_screen_test.dart',
    'test/config/flutter_dependency_surface_test.dart'
)

Push-Location -LiteralPath $repoRoot
try {
    Invoke-Gate 'CLI contract' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/tests/verify-gemini-byok.tests.ps1'
    }
    Invoke-Gate 'Dart format' {
        # Contract marker: dart format --output=none --set-exit-if-changed
        & $dartExecutable format --output=none --set-exit-if-changed $dartFiles
    }
    Invoke-Gate 'Static analysis' {
        # Contract marker: flutter analyze
        & $flutterExecutable analyze
    }
    Invoke-Gate 'Gemini BYOK tests' {
        & $flutterExecutable test `
            test/features/ai_tutor `
            test/features/gemini `
            test/architecture/provider_composition_boundary_test.dart `
            test/screens/ai_tutor_screen_test.dart `
            test/screens/gemini_settings_screen_test.dart `
            test/config/flutter_dependency_surface_test.dart `
            test/runtime/app_bootstrap_test.dart `
            test/screens/main_navigation_screen_test.dart `
            --timeout 90s --reporter compact
    }
    Invoke-Gate 'Android debug APK' {
        # Contract marker: flutter build apk --debug
        $buildArguments = @(
            'build',
            'apk',
            '--debug',
            '--dart-define=LEXIQUEST_VERSION=1.0.0+1',
            '--dart-define=LEXIQUEST_BUILD_ID=p6-gemini-byok'
        )
        & $flutterExecutable @buildArguments
    }
    Invoke-Gate 'APK model runtime integrity' {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            'tool/cli/verify-apk-model-runtime.ps1'
    }
    Invoke-Gate 'Whitespace and conflict markers' {
        & git diff --check
    }
}
finally {
    Pop-Location
}

Write-Host 'LexiQuest P6 Gemini BYOK gate: PASS' -ForegroundColor Green
foreach ($result in $results) {
    Write-Host ('  {0}: PASS' -f $result.Name) -ForegroundColor Green
}
exit 0

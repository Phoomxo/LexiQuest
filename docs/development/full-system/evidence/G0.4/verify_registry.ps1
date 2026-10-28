$ErrorActionPreference = 'Stop'
$repo = (git rev-parse --show-toplevel).Trim()
$runner = Join-Path $repo 'tool/cli/verify-scope.ps1'
$registry = Get-Content (Join-Path $PSScriptRoot 'command-registry.json') -Raw | ConvertFrom-Json
$checks = [System.Collections.Generic.List[object]]::new()
$unavailable = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $registry.entries) {
    foreach ($command in $entry.commands) {
        $arguments = @($command.Arguments)
        $paths = @()
        if ($command.FilePath -eq 'flutter') {
            $paths = @($arguments | Where-Object { $_ -match '^(test|integration_test)[/\\]' })
        } elseif ($command.FilePath -eq 'uv') {
            $project = $arguments[([array]::IndexOf($arguments, '--project') + 1)]
            $paths = @((Join-Path $project 'pyproject.toml'),(Join-Path $project 'uv.lock'),(Join-Path $project 'tests'))
        } elseif ($command.FilePath -eq 'powershell') {
            $paths = @($arguments[([array]::IndexOf($arguments, '-File') + 1)])
        } elseif ($command.FilePath -eq 'npm') {
            $paths = @('package.json')
            if ($arguments -contains '--prefix') { $paths = @('functions/package.json') }
        }
        foreach ($path in $paths) {
            $absolute = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $repo $path }
            if (-not (Test-Path -LiteralPath $absolute)) {
                if ($entry.area -notin @('Economy','Integration')) { throw "Unexpected registry missing path: $path" }
                $unavailable.Add([ordered]@{level=$entry.level;area=$entry.area;command=$command.Name;missingPath=$path;status='Unavailable / NOT RUN';owner=$(if($entry.area -eq 'Economy'){'P7.3'}else{'P7.7/P8.4'})})
            }
        }
    }
}
$cases = @(
    @('-Level','Targeted','-Area','All'),
    @('-Level','Targeted','-Area','Runtime','-CliOnly'),
    @('-Level','Targeted','-Area','Learning','-TestName','orphan'),
    @('-Level','Targeted','-Area','Learning','-TestTargets','test/../pubspec.dart'),
    @('-Level','Release','-Area','Runtime'),
    @('-Level','Release','-Area','All'),
    @('-Level','Release','-Area','All','-FrozenSha',('0' * 40))
    @('-Level','Targeted','-Area','Economy','-PlanOnly'),
    @('-Level','Targeted','-Area','Integration','-PlanOnly'),
    @('-Level','Subsystem','-Area','Integration','-PlanOnly')
)
foreach ($case in $cases) {
    # All are rejected before dispatch. Never provide a valid frozen release pin.
    try {
        $ErrorActionPreference = 'Continue' # Native stderr is expected for rejection probes.
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner @case 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($code -eq 0) { throw ('Expected rejection: ' + ($case -join ' ')) }
    $checks.Add([ordered]@{arguments=$case;exitCode=$code;expected='Rejected before dispatch';output=($output -join "`n")})
}
$plan = & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Level Release -Area All -PlanOnly | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $plan.status -ne 'Planned' -or $plan.runtimeVerified -ne $false) { throw 'Plan-only must remain non-runtime evidence' }
[ordered]@{schemaVersion=1;registryEntries=$registry.entries.Count;pathValidation='Complete; unavailable paths explicitly recorded and rejected by runner';unavailable=$unavailable;parameterRejections=$checks;releasePlan=$plan;releaseExecuted=$false} |
    ConvertTo-Json -Depth 14 | Set-Content (Join-Path $PSScriptRoot 'registry-verification.json')
Write-Output "PASS: $($registry.entries.Count) registry entries, $($checks.Count) expected rejections, $($unavailable.Count) unavailable paths, release plan-only (no execution)"

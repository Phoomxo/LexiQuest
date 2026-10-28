Set-StrictMode -Version Latest

function Get-AiAnalysisReportProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Resolve-AiAnalysisSafeOutputRoot {
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OutputRoot
    )

    $repository = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $output = [System.IO.Path]::GetFullPath($OutputRoot).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $repositoryPrefix = $repository + [System.IO.Path]::DirectorySeparatorChar
    if (-not $output.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'unsafeReportPath'
    }

    $relative = $output.Substring($repositoryPrefix.Length)
    $current = $repository
    foreach ($segment in $relative.Split(@(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ), [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $current = [System.IO.Path]::Combine($current, $segment)
        if ([System.IO.File]::Exists($current) -or [System.IO.Directory]::Exists($current)) {
            $attributes = [System.IO.File]::GetAttributes($current)
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'reparsePoint' }
        }
    }
    return $output
}

function Protect-AiAnalysisReportText {
    param($Value)
    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $rules = @(
        @{ Id = 'maxplusInferenceKey'; Pattern = '(?<![A-Za-z0-9])ccsk-[a-f0-9]{64}' },
        @{ Id = 'maxplusManagementToken'; Pattern = '(?<![A-Za-z0-9])ccmk-[A-Za-z0-9_-]{16,}' },
        @{ Id = 'anthropicKey'; Pattern = '(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_-]{20,}' },
        @{ Id = 'openAiKey'; Pattern = '(?<![A-Za-z0-9])sk-(?!ant-)[A-Za-z0-9_-]{20,}' },
        @{ Id = 'geminiKey'; Pattern = '(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{20,}' }
    )
    foreach ($rule in $rules) {
        $text = [regex]::Replace($text, $rule.Pattern, "[REDACTED:$($rule.Id)]")
    }
    return $text
}

function ConvertTo-AiAnalysisReportFinding {
    param([Parameter(Mandatory)]$Finding)
    [pscustomobject]@{
        id = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'id')
        severity = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'severity')
        category = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'category')
        message = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'message')
        file = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'file')
        line = [int](Get-AiAnalysisReportProperty $Finding 'line')
        evidence = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Finding 'evidence')
    }
}

function ConvertTo-AiAnalysisNullableIntegerMetadata {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool] -or $Value -is [string] -or $Value -isnot [ValueType]) { throw 'invalidReportMetadata' }
    try { $number = [decimal]$Value } catch { throw 'invalidReportMetadata' }
    if ($number -lt 0 -or $number -ne [decimal]::Truncate($number) -or $number -gt [long]::MaxValue) {
        throw 'invalidReportMetadata'
    }
    return [long]$number
}

function ConvertTo-AiAnalysisCostMetadata {
    param($Value)
    if ($null -eq $Value) { return 'unknown' }
    if ($Value -is [string]) {
        if ($Value -ceq 'unknown') { return 'unknown' }
        throw 'invalidReportMetadata'
    }
    if ($Value -is [bool] -or $Value -isnot [ValueType]) { throw 'invalidReportMetadata' }
    try { $number = [decimal]$Value } catch { throw 'invalidReportMetadata' }
    if ($number -lt 0) { throw 'invalidReportMetadata' }
    return $number
}

function ConvertTo-AiAnalysisProviderMetadata {
    param([Parameter(Mandatory)]$ProviderResult)

    $usage = Get-AiAnalysisReportProperty $ProviderResult 'Usage'
    $cost = ConvertTo-AiAnalysisCostMetadata (Get-AiAnalysisReportProperty $usage 'ProviderReportedCost')
    [pscustomobject]@{
        provider = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $ProviderResult 'Provider')
        model = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $ProviderResult 'Model')
        effort = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $ProviderResult 'Effort')
        latencyMs = ConvertTo-AiAnalysisNullableIntegerMetadata (Get-AiAnalysisReportProperty $ProviderResult 'LatencyMs')
        inputTokens = ConvertTo-AiAnalysisNullableIntegerMetadata (Get-AiAnalysisReportProperty $usage 'InputTokens')
        outputTokens = ConvertTo-AiAnalysisNullableIntegerMetadata (Get-AiAnalysisReportProperty $usage 'OutputTokens')
        totalTokens = ConvertTo-AiAnalysisNullableIntegerMetadata (Get-AiAnalysisReportProperty $usage 'TotalTokens')
        cachedTokens = ConvertTo-AiAnalysisNullableIntegerMetadata (Get-AiAnalysisReportProperty $usage 'CachedTokens')
        providerReportedCost = $cost
    }
}

function Remove-ExpiredAiAnalysisReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][ValidateRange(1, 3650)][int]$RetentionDays,
        [DateTime]$NowUtc = [DateTime]::UtcNow
    )

    if (-not [System.IO.Directory]::Exists($OutputRoot)) { return }
    $root = [System.IO.Path]::GetFullPath($OutputRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
    $cutoff = $NowUtc.ToUniversalTime().AddDays(-$RetentionDays)
    foreach ($directory in [System.IO.Directory]::GetDirectories($root)) {
        $name = [System.IO.Path]::GetFileName($directory)
        if ($name -cnotmatch '^\d{8}T\d{6}Z-[a-f0-9]{8}$') { continue }
        $timestampText = $name.Substring(0, 16)
        $timestamp = [DateTime]::MinValue
        $parsed = [DateTime]::TryParseExact(
            $timestampText,
            'yyyyMMddTHHmmssZ',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
            [ref]$timestamp
        )
        if (-not $parsed -or $timestamp -ge $cutoff) { continue }
        $fullDirectory = [System.IO.Path]::GetFullPath($directory)
        if (-not $fullDirectory.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'unsafeReportPath' }
        Remove-Item -LiteralPath $fullDirectory -Recurse -Force
    }
}

function Write-AiAnalysisReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$Scope,
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$OutputRoot,
        [Parameter(Mandatory)][ValidateRange(1, 3650)][int]$RetentionDays,
        [switch]$NoReport
    )

    if ($NoReport) { return [pscustomobject]@{ Written = $false; Path = $null } }

    $output = Resolve-AiAnalysisSafeOutputRoot -RepositoryRoot $RepositoryRoot -OutputRoot $OutputRoot

    $recordedAt = [DateTime]::UtcNow
    $runName = $recordedAt.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    [System.IO.Directory]::CreateDirectory($output) | Out-Null
    $runDirectory = [System.IO.Path]::Combine($output, $runName)
    [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null

    try {
        $providerResults = @(
            Get-AiAnalysisReportProperty $Result 'Primary'
            Get-AiAnalysisReportProperty $Result 'Review'
            Get-AiAnalysisReportProperty $Result 'Adjudication'
        ) | Where-Object { $null -ne $_ }
        $providers = @($providerResults | ForEach-Object { ConvertTo-AiAnalysisProviderMetadata $_ })
        $scopeFiles = @($Scope.Files | ForEach-Object { Protect-AiAnalysisReportText $_ })

        $metadata = [ordered]@{
            schemaVersion = 1
            task = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Task')
            scope = $scopeFiles
            commitSha = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Scope 'CommitSha')
            dirty = [bool](Get-AiAnalysisReportProperty $Scope 'Dirty')
            outcome = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Outcome')
            agreement = Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Agreement')
            providers = $providers
            recordedAtUtc = $recordedAt.ToString('o')
        }

        $markdown = New-Object System.Text.StringBuilder
        [void]$markdown.AppendLine('# AI Analysis Report')
        [void]$markdown.AppendLine()
        [void]$markdown.AppendLine("Task: $(Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Task'))")
        [void]$markdown.AppendLine("Outcome: $(Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Outcome'))")
        [void]$markdown.AppendLine("Agreement: $(Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $Result 'Agreement'))")
        [void]$markdown.AppendLine()
        [void]$markdown.AppendLine('Scope:')
        foreach ($file in $scopeFiles) { [void]$markdown.AppendLine("- $file") }

        foreach ($entry in @(
            [pscustomobject]@{ Label = 'Primary'; Value = Get-AiAnalysisReportProperty $Result 'Primary' },
            [pscustomobject]@{ Label = 'Review'; Value = Get-AiAnalysisReportProperty $Result 'Review' },
            [pscustomobject]@{ Label = 'Adjudication'; Value = Get-AiAnalysisReportProperty $Result 'Adjudication' }
        )) {
            if ($null -eq $entry.Value) { continue }
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine("## $($entry.Label)")
            [void]$markdown.AppendLine()
            [void]$markdown.AppendLine((Protect-AiAnalysisReportText (Get-AiAnalysisReportProperty $entry.Value 'Conclusion')))
            foreach ($finding in @((Get-AiAnalysisReportProperty $entry.Value 'Findings'))) {
                $safe = ConvertTo-AiAnalysisReportFinding $finding
                [void]$markdown.AppendLine("- [$($safe.severity)] $($safe.id) $($safe.file):$($safe.line) - $($safe.message) Evidence: $($safe.evidence)")
            }
        }

        $reportTemporary = [System.IO.Path]::Combine($runDirectory, 'report.md.tmp')
        $metadataTemporary = [System.IO.Path]::Combine($runDirectory, 'metadata.json.tmp')
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($reportTemporary, $markdown.ToString(), $encoding)
        [System.IO.File]::WriteAllText($metadataTemporary, ($metadata | ConvertTo-Json -Depth 20), $encoding)
        [System.IO.File]::Move($reportTemporary, [System.IO.Path]::Combine($runDirectory, 'report.md'))
        [System.IO.File]::Move($metadataTemporary, [System.IO.Path]::Combine($runDirectory, 'metadata.json'))
        return [pscustomobject]@{ Written = $true; Path = $runDirectory }
    } catch {
        if ([System.IO.Directory]::Exists($runDirectory)) { Remove-Item -LiteralPath $runDirectory -Recurse -Force }
        throw
    }
}

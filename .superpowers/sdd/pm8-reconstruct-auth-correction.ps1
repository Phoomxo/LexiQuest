$ErrorActionPreference = 'Stop'
$pm8Lines = @(Get-Content -LiteralPath '.superpowers/sdd/pm8-auth-current-review.diff')
$pm8Reviewed = @(Get-Content -LiteralPath '.superpowers/sdd/pm8-auth-current-manifest.json' -Raw | ConvertFrom-Json)
$pm8Targets = @($pm8Reviewed[0], $pm8Reviewed[3])
$pm8Output = [Text.StringBuilder]::new()
foreach ($pm8Target in $pm8Targets) {
    $pm8Path = $pm8Target.path
    $pm8Base = @()
    if ($pm8Path.StartsWith('lib/')) {
        $pm8Base = @(& git show ('3bdb5f5605e670e8b30628f3f237cd9c0d660ad9:' + $pm8Path))
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read accepted base.' }
    }
    $pm8Start = [Array]::IndexOf($pm8Lines, ('diff --git a/' + $pm8Path + ' b/' + $pm8Path))
    if ($pm8Start -lt 0) { throw 'Reviewed diff section missing.' }
    $pm8Result = [Collections.Generic.List[string]]::new()
    $pm8Cursor = 0
    $pm8InHunk = $false
    for ($pm8Index = $pm8Start + 1; $pm8Index -lt $pm8Lines.Count; $pm8Index++) {
        $pm8Line = $pm8Lines[$pm8Index]
        if ($pm8Line.StartsWith('diff --git ')) { break }
        if ($pm8Line -match '^@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@') {
            $pm8OldStart = [Math]::Max(0, [int]$Matches[1] - 1)
            while ($pm8Cursor -lt $pm8OldStart) {
                $pm8Result.Add($pm8Base[$pm8Cursor++])
            }
            $pm8InHunk = $true
            continue
        }
        if (-not $pm8InHunk -or $pm8Line.StartsWith('\')) { continue }
        if ($pm8Line.StartsWith(' ') -or $pm8Line.StartsWith('-')) {
            if ($pm8Cursor -ge $pm8Base.Count -or $pm8Base[$pm8Cursor] -cne $pm8Line.Substring(1)) {
                throw "Reviewed patch base mismatch: $pm8Path at $pm8Cursor"
            }
            $pm8Cursor++
        }
        if ($pm8Line.StartsWith(' ') -or $pm8Line.StartsWith('+')) {
            $pm8Result.Add($pm8Line.Substring(1))
        }
    }
    while ($pm8Cursor -lt $pm8Base.Count) { $pm8Result.Add($pm8Base[$pm8Cursor++]) }
    $pm8Recovered = '.superpowers/sdd/pm8-reviewed-before-' + [IO.Path]::GetFileName($pm8Path)
    $pm8Text = ($pm8Result -join "`n") + "`n"
    [IO.File]::WriteAllText((Join-Path (Get-Location).Path $pm8Recovered), $pm8Text, [Text.UTF8Encoding]::new($false))
    $pm8Hash = (Get-FileHash -LiteralPath $pm8Recovered).Hash.ToLowerInvariant()
    if ($pm8Hash -cne $pm8Target.sha256) {
        $pm8CrLfText = $pm8Text.Replace("`n", "`r`n")
        $pm8CrLfHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($pm8CrLfText))).ToLowerInvariant()
        if ($pm8CrLfHash -cne $pm8Target.sha256) { throw "Reconstructed reviewed hash mismatch: $pm8Path" }
        [IO.File]::WriteAllText((Join-Path (Get-Location).Path $pm8Recovered), $pm8CrLfText, [Text.UTF8Encoding]::new($false))
        $pm8Hash = $pm8CrLfHash
    }
    [void]$pm8Output.AppendLine("Reviewed SHA256=$pm8Hash; current file=$pm8Path")
    $pm8Delta = @(& git diff --no-index --no-ext-diff --no-color -U8 -- $pm8Recovered $pm8Path)
    if ($LASTEXITCODE -ne 1) { throw 'Expected nonempty corrective delta.' }
    [void]$pm8Output.AppendLine(($pm8Delta -join "`n"))
}
$pm8Packet = '.superpowers/sdd/pm8-auth-classification-correction.diff'
[IO.File]::WriteAllText((Join-Path (Get-Location).Path $pm8Packet), $pm8Output.ToString(), [Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $pm8Packet
exit 0

param([ValidateSet('Task','Branch')][string]$Mode = 'Task')
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$pm8Root = 'C:\Users\Phet\.codex\worktrees\02fa\LexiQuest'
if ((Get-Location).Path -cne $pm8Root) { throw 'Wrong PM8 worktree.' }
$pm8Base = if ($Mode -eq 'Task') { '3bdb5f5605e670e8b30628f3f237cd9c0d660ad9' } else { 'ca123dddc1349acc4ed67bdd8f5476b02165307c' }
$pm8Head = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read HEAD.' }
$pm8Tracked = @(& git diff --name-only $pm8Base -- lib test tool)
if ($LASTEXITCODE -ne 0) { throw 'Cannot list tracked changes.' }
$pm8New = @(& git ls-files --others --exclude-standard -- lib test tool)
if ($LASTEXITCODE -ne 0) { throw 'Cannot list untracked changes.' }
$pm8Files = @(@($pm8Tracked) + @($pm8New) | Sort-Object -Unique)
if ($pm8Files.Count -eq 0) { throw 'Empty review scope.' }
$pm8Manifest = foreach ($pm8File in $pm8Files) {
    if (-not (Test-Path -LiteralPath $pm8File -PathType Leaf)) { throw "Missing review source: $pm8File" }
    $pm8Name = [IO.Path]::GetFileNameWithoutExtension($pm8File)
    $pm8Group = 'task'
    if ($Mode -eq 'Branch') {
        $pm8Group = 'boundary'
        if ($pm8File -match '/(presentation|screens|voice)/' -or
            $pm8File -match '/goldens/' -or
            $pm8Name -in @('lesson_mode_registry','unified_lesson_controller','production_feature_navigation_test','adventure_pair_renderer_parity_test') -or
            $pm8Name -match '^pair_(board|matching_host_golden|matching_experience_host|matching_result_view)') {
            $pm8Group = 'ui'
        }
        if ($pm8Name -in @(
            'pair_matching_atomic_start','pair_matching_atomic_start_test',
            'pair_matching_session_coordinator','pair_matching_source_composer','pair_matching_source_composer_test',
            'pair_matching_source_property_test','pair_matching_checkpoint_codec','pair_matching_checkpoint_codec_test',
            'pair_active_clock','pair_active_timer_test','pair_matching_checkpoint_budget',
            'pair_matching_engine','pair_matching_engine_test','pair_matching_launch',
            'pair_matching_plan','pair_matching_plan_test','pair_repair_policy','pair_repair_policy_test',
            'pair_star_policy','pair_star_policy_test','pair_support_policy','pair_support_classification_test',
            'pair_matching_idempotency_test','pair_timeout_race_test','pair_timeout_recovery_test',
            'pair_matching_density_preference_test','pair_matching_owner_command_test')) {
            $pm8Group = 'engine'
        }
    }
    [pscustomobject]@{ path = $pm8File; group = $pm8Group; sha256 = (Get-FileHash -LiteralPath $pm8File -Algorithm SHA256).Hash.ToLowerInvariant(); isNew = $pm8File -in $pm8New }
}
$pm8Stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfff',[Globalization.CultureInfo]::InvariantCulture)
$pm8Prefix = Join-Path $pm8Root ('.superpowers/sdd/pm8-' + $Mode.ToLowerInvariant() + '-' + $pm8Stamp)
$pm8Manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($pm8Prefix + '.manifest.json') -Encoding utf8
$pm8Packets = foreach ($pm8GroupSet in ($pm8Manifest | Group-Object group)) {
    $pm8Packet = $pm8Prefix + '-' + $pm8GroupSet.Name + '.diff'
    $pm8Builder = [Text.StringBuilder]::new()
    [void]$pm8Builder.AppendLine("PM8 $Mode review; group=$($pm8GroupSet.Name); base=$pm8Base; checkout=$pm8Head; current worktree includes uncommitted/new files; captured UTC=$pm8Stamp")
    [void]$pm8Builder.AppendLine('Exact file manifest (raw SHA256):')
    foreach ($pm8Entry in $pm8GroupSet.Group) { [void]$pm8Builder.AppendLine("$($pm8Entry.sha256)  $($pm8Entry.path)") }
    [void]$pm8Builder.AppendLine('Commits in review range:')
    [void]$pm8Builder.AppendLine((@(& git log --oneline "$pm8Base..$pm8Head") -join "`n"))
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read commit list.' }
    $pm8TrackedGroup = @($pm8GroupSet.Group | Where-Object { -not $_.isNew } | ForEach-Object path)
    if ($pm8TrackedGroup.Count -gt 0) {
        [void]$pm8Builder.AppendLine((@(& git diff --stat $pm8Base -- @pm8TrackedGroup) -join "`n"))
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read diff stat.' }
        [void]$pm8Builder.AppendLine((@(& git diff --no-ext-diff --no-color -U10 $pm8Base -- @pm8TrackedGroup) -join "`n"))
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read context diff.' }
    }
    foreach ($pm8Entry in ($pm8GroupSet.Group | Where-Object isNew)) {
        [void]$pm8Builder.AppendLine((@(& git diff --no-index --no-ext-diff --no-color -U10 -- NUL $pm8Entry.path) -join "`n"))
        if ($LASTEXITCODE -ne 1) { throw "Unexpected new-file diff exit for $($pm8Entry.path)." }
    }
    [IO.File]::WriteAllText($pm8Packet, $pm8Builder.ToString(), [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ group = $pm8GroupSet.Name; fileCount = $pm8GroupSet.Count; packet = $pm8Packet; bytes = (Get-Item -LiteralPath $pm8Packet).Length; sha256 = (Get-FileHash -LiteralPath $pm8Packet -Algorithm SHA256).Hash.ToLowerInvariant() }
}
foreach ($pm8Entry in $pm8Manifest) {
    if ((Get-FileHash -LiteralPath $pm8Entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $pm8Entry.sha256) { throw "Source changed during capture: $($pm8Entry.path)" }
}
$pm8Result = [ordered]@{ mode=$Mode; base=$pm8Base; checkoutHead=$pm8Head; manifest=($pm8Prefix+'.manifest.json'); totalFiles=$pm8Files.Count; capturedUtc=$pm8Stamp; packets=@($pm8Packets) }
$pm8Result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($pm8Prefix+'.packets.json') -Encoding utf8
$pm8Result | ConvertTo-Json -Depth 5
exit 0

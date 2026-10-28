param()
$ErrorActionPreference = 'Stop'
$pm8Root = 'C:\Users\Phet\.codex\worktrees\02fa\LexiQuest'
if ((Get-Location).Path -cne $pm8Root) { throw 'Wrong PM8 worktree.' }
$pm8Plan = Get-Content -LiteralPath 'docs/generated/alltcas-8-44-final-test-plan.json' -Raw | ConvertFrom-Json
$pm8Evidence = Join-Path $pm8Root ('build/verification/' + $pm8Plan.sourceCommit)
$pm8Required = @(
    'generator-contracts', 'full-default', 'full-serial',
    'host-core-journey', 'host-feature-controls', 'host-media-smoke',
    'analyze', 'privacy-authority', 'runtime-catalog-navigation',
    'firestore-static-policy', 'osv-config-policy', 'demo-auth-policy', 'demo-firestore-policy',
    'gitleaks-lib', 'gitleaks-test', 'gitleaks-docs', 'gitleaks-tool-final-test-plan',
    'gitleaks-tool-feature-contract', 'gitleaks-pubspec-yaml', 'gitleaks-pubspec-lock',
    'gitleaks-firestore-rules', 'gitleaks-agents-md', 'osv-literal-locks',
    'debug-apk-build', 'apk-native-integrity', 'apk-application-id', 'apk-version-name',
    'apk-version-code', 'final-feature-map-check', 'final-test-plan-check'
)
function Get-Pm8EvidenceHash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('Missing evidence: ' + $Path) }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$pm8Attempts = @(Get-ChildItem -LiteralPath $pm8Evidence -File -Filter '*.metadata.json' | ForEach-Object {
    $pm8Item = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -DateKind String
    if ($pm8Item.PSObject.Properties.Name -contains 'label') {
        [pscustomobject]@{file=$_.FullName; metadata=$pm8Item}
    }
})
$pm8Gates = @($pm8Required | ForEach-Object {
    $pm8Label = $_
    $pm8Matches = @($pm8Attempts | Where-Object { $_.metadata.label -ceq $pm8Label } | Sort-Object { $_.metadata.startUtc })
    if ($pm8Matches.Count -eq 0) { throw ('Missing gate: ' + $pm8Label) }
    $pm8Selected = $pm8Matches[-1]
    $pm8Meta = $pm8Selected.metadata
    if ($pm8Meta.nativeExitCode -ne 0 -or $pm8Meta.gateExitCode -ne 0 -or
        -not $pm8Meta.commandStarted -or -not $pm8Meta.headMatchBefore -or -not $pm8Meta.headMatchAfter -or
        -not $pm8Meta.planUnchanged -or $pm8Meta.sourceCheckBefore.status -cne 'match' -or
        $pm8Meta.sourceCheckAfter.status -cne 'match' -or
        $pm8Meta.sourceCheckBefore.entryCount -ne 104 -or $pm8Meta.sourceCheckAfter.entryCount -ne 104 -or
        $pm8Meta.sourceCommit -cne $pm8Plan.sourceCommit -or $pm8Meta.sourceFingerprint -cne $pm8Plan.sourceFingerprint) {
        throw ('Latest gate lacks passing source-bound evidence: ' + $pm8Label)
    }
    [ordered]@{
        label=$pm8Label; metadata=(Split-Path -Leaf $pm8Selected.file)
        metadataSha256=(Get-Pm8EvidenceHash $pm8Selected.file)
        stdoutSha256=(Get-Pm8EvidenceHash $pm8Meta.stdout)
        stderrSha256=(Get-Pm8EvidenceHash $pm8Meta.stderr)
        executable=$pm8Meta.executable; arguments=$pm8Meta.arguments
        nativeExitCode=$pm8Meta.nativeExitCode; gateExitCode=$pm8Meta.gateExitCode
        startUtc=$pm8Meta.startUtc; endUtc=$pm8Meta.endUtc; durationSeconds=$pm8Meta.durationSeconds
        attemptCount=$pm8Matches.Count
    }
})
$pm8Artifacts = @('pm8-full-default.summary.json', 'pm8-full-default.inventory.json',
    'pm8-full-serial.summary.json', 'pm8-full-serial.inventory.json', 'pm8-pmt-inventory-reconciliation.json',
    'pm8-document-inventory.json', 'pm8-apk-identity.json', 'pm8-unexecuted-gates.json', 'pm8-golden-preservation.json',
    'pm8-gitleaks-finding-disposition.json', 'pm8-gitleaks-controls-v3.metadata.json', 'pm8-gitleaks-verified-policy.toml',
    'pm8-generated-gate-coverage.json', 'pm8-runtime-source-configuration.json')
$pm8ArtifactHashes = @($pm8Artifacts | ForEach-Object {
    [ordered]@{file=$_; sha256=(Get-Pm8EvidenceHash (Join-Path $pm8Evidence $_))}
})
$pm8Record = [ordered]@{
    evidenceType='Local engineering verification; not signed G4P, device acceptance or production authorization'
    capturedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    sourceCommit=$pm8Plan.sourceCommit; sourceFingerprint=$pm8Plan.sourceFingerprint
    canonicalSourceEntries=$pm8Plan.sources.Count
    productContract=$pm8Plan.productContract; database=$pm8Plan.database
    runtimeStates=$pm8Plan.runtime; rulesRevisions=$pm8Plan.rulesRevisions
    contentRevisionAuthorities=$pm8Plan.contentRevisionAuthorities
    contentRevisions='Synthetic per-test captured plan/configuration pins; no real participant content or deployment revision is asserted.'
    rollbackDrillResult='Current reader/owner/off/recovery fixtures passed in both full named inventories; no historical APK execution or device rollout asserted.'
    gates=$pm8Gates; artifacts=$pm8ArtifactHashes
    retainedNonzeroAttempts=@($pm8Attempts | Where-Object { $_.metadata.gateExitCode -ne 0 } | ForEach-Object {
        [ordered]@{metadata=(Split-Path -Leaf $_.file); label=$_.metadata.label; nativeExitCode=$_.metadata.nativeExitCode; gateExitCode=$_.metadata.gateExitCode}
    })
    earlierFailedSource='94c1e97fea5097af144b63adfdf9ab2e5f277bee; full-default4848passed/2failed, corrected by1875a618; original evidence retained separately.'
}
$pm8Record | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath (Join-Path $pm8Evidence 'pm8-local-release-evidence.json') -Encoding utf8
[pscustomobject]@{requiredGates=$pm8Gates.Count; source=$pm8Plan.sourceCommit; retainedNonzeroAttempts=$pm8Record.retainedNonzeroAttempts.Count} | ConvertTo-Json -Compress
exit 0

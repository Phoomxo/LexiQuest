#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot 'tool/cli/lib/mirofish-synthetic-uat.ps1')

$seedSource = Join-Path $repoRoot 'docs/testing/mirofish-synthetic-uat.md'
if (-not (Test-Path -LiteralPath $seedSource -PathType Leaf)) {
    throw "Synthetic UAT seed source is missing: $seedSource"
}

$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
    [System.IO.Path]::GetFullPath($OutputPath)
} else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
}

$seedText = Get-Content -LiteralPath $seedSource -Raw -Encoding utf8
if ([Text.Encoding]::UTF8.GetByteCount($seedText) -gt 1MB) {
    throw 'Synthetic UAT seed exceeds the 1 MiB pilot limit.'
}
$seedErrors = @(Test-LexiQuestSyntheticText -Text $seedText)
if ($seedErrors.Count -gt 0) {
    throw ($seedErrors -join ' ')
}

$requestText = @'
จำลองผู้ใช้สังเคราะห์ทั้ง 6 persona ตาม seed เท่านั้นเป็นเวลาไม่เกิน 10 รอบ
วิเคราะห์ความเข้าใจ การค้นพบฟีเจอร์ ความลังเล ความเป็นส่วนตัว การเข้าถึง
และการทำงานออฟไลน์ของ flow ที่ระบุ ห้ามอ้างว่าได้แตะ APK หรือพบผู้ใช้จริง
ส่งออกผลตาม JSON contract ในหัวข้อ "Report contract" โดย findings ทั้งหมด
เป็นเพียงสมมติฐานและต้องระบุ deterministic verification target
'@
$requestErrors = @(Test-LexiQuestSyntheticText -Text $requestText)
if ($requestErrors.Count -gt 0) {
    throw ($requestErrors -join ' ')
}

New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$seedPath = Join-Path $resolvedOutput 'seed.md'
$requestPath = Join-Path $resolvedOutput 'simulation-request.md'
$manifestPath = Join-Path $resolvedOutput 'manifest.json'
foreach ($target in @($seedPath, $requestPath, $manifestPath)) {
    if (Test-Path -LiteralPath $target) {
        throw "Refusing to overwrite an existing synthetic-UAT artifact: $target"
    }
}

Copy-Item -LiteralPath $seedSource -Destination $seedPath
Set-Content -LiteralPath $requestPath -Value $requestText -Encoding utf8
$seedSha256 = (Get-FileHash -LiteralPath $seedPath -Algorithm SHA256).Hash
$requestSha256 = (Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash
$sourceCommit = (& git -C $repoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $sourceCommit -notmatch '^[A-Fa-f0-9]{40}$') {
    throw 'Unable to resolve the LexiQuest source commit.'
}

$manifest = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    advisoryOnly = $true
    dataClassification = 'synthetic'
    sourceCommit = $sourceCommit
    engine = [ordered]@{
        name = 'MiroFish'
        version = 'v0.1.2'
        commit = '985f89f49acbb44ee14d9d680682c741a44eeebe'
    }
    scenario = [ordered]@{
        personaCount = 6
        maxRounds = 10
        containsRealUserData = $false
    }
    artifacts = [ordered]@{
        seedFile = 'seed.md'
        seedSha256 = $seedSha256
        simulationRequestFile = 'simulation-request.md'
        simulationRequestSha256 = $requestSha256
    }
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath `
    -Encoding utf8

Write-Host "MiroFish synthetic-UAT pack created: $resolvedOutput"
Write-Host "Seed SHA-256: $seedSha256"
Write-Host 'Disposition: REPORT_ONLY'

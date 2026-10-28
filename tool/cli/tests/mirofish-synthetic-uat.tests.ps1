#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) {
        $script:Passed++
    } else {
        $script:Failed++
        Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
    }
}

function Invoke-Cli {
    param([string]$ScriptPath, [string[]]$Arguments)
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File `
            $ScriptPath @Arguments 2>&1
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

$repoRoot = Split-Path -Parent (
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
)
$libraryPath = Join-Path $repoRoot 'tool/cli/lib/mirofish-synthetic-uat.ps1'
$packagerPath = Join-Path $repoRoot 'tool/cli/new-mirofish-synthetic-uat.ps1'
$validatorPath = Join-Path $repoRoot 'tool/cli/verify-mirofish-synthetic-uat.ps1'

foreach ($requiredPath in @($libraryPath, $packagerPath, $validatorPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        Write-Error "Required MiroFish synthetic-UAT tool is missing: $requiredPath"
    }
}

. $libraryPath

$safeErrors = @(Test-LexiQuestSyntheticText -Text (
    'ผู้เรียนสังเคราะห์กำลังทดสอบหน้าเข้าสู่ระบบและการเรียนออฟไลน์'
))
Assert-True ($safeErrors.Count -eq 0) 'synthetic Thai UX text is accepted'

foreach ($unsafe in @(
    'student@example.com',
    'เบอร์ 081-234-5678',
    'เลขบัตร 1101700203451',
    'Authorization: Bearer secret-token-value',
    'api_key=live-secret-value',
    '-----BEGIN PRIVATE KEY-----',
    'deviceSerial=9582188822004C6',
    ('sk-' + ('a' * 32)),
    ('ccsk-' + ('b' * 32)),
    ('AIza' + ('C' * 32)),
    (('d' * 24) + '.' + ('e' * 24) + '.' + ('f' * 24))
)) {
    Assert-True (@(Test-LexiQuestSyntheticText -Text $unsafe).Count -gt 0) `
        "unsafe text is rejected: $unsafe"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'lexiquest-mirofish-test-' + [Guid]::NewGuid().ToString('N')
)
$packPath = Join-Path $tempRoot 'pack'
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $env:LEXIQUEST_TEST_LLM_API_KEY = 'must-not-appear-in-pack'
    $pack = Invoke-Cli -ScriptPath $packagerPath -Arguments @(
        '-OutputPath', $packPath
    )
    Assert-True ($pack.ExitCode -eq 0) 'offline packager exits successfully'

    $seedPath = Join-Path $packPath 'seed.md'
    $requestPath = Join-Path $packPath 'simulation-request.md'
    $manifestPath = Join-Path $packPath 'manifest.json'
    foreach ($artifact in @($seedPath, $requestPath, $manifestPath)) {
        Assert-True (Test-Path -LiteralPath $artifact -PathType Leaf) `
            "packager creates $artifact"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 |
        ConvertFrom-Json
    $seedHash = (Get-FileHash -LiteralPath $seedPath -Algorithm SHA256).Hash
    Assert-True ($manifest.schemaVersion -eq 1) 'manifest schema is versioned'
    Assert-True ($manifest.advisoryOnly -eq $true) 'manifest is advisory-only'
    Assert-True ($manifest.dataClassification -eq 'synthetic') `
        'manifest classifies all input as synthetic'
    Assert-True ($manifest.scenario.containsRealUserData -eq $false) `
        'manifest forbids real user data'
    Assert-True ($manifest.scenario.personaCount -eq 6) `
        'pilot is bounded to six personas'
    Assert-True ($manifest.scenario.maxRounds -eq 10) `
        'pilot is bounded to ten rounds'
    Assert-True ($manifest.artifacts.seedSha256 -eq $seedHash) `
        'manifest pins the generated seed hash'
    $requestHash = (
        Get-FileHash -LiteralPath $requestPath -Algorithm SHA256
    ).Hash
    Assert-True ($manifest.artifacts.simulationRequestSha256 -eq $requestHash) `
        'manifest pins the generated simulation request hash'
    Assert-True ($manifest.engine.version -eq 'v0.1.2') `
        'manifest pins the upstream release'
    Assert-True (
        $manifest.engine.commit -eq `
            '985f89f49acbb44ee14d9d680682c741a44eeebe'
    ) 'manifest pins the upstream commit'

    $packText = (
        Get-Content -LiteralPath $seedPath -Raw -Encoding utf8
    ) + (
        Get-Content -LiteralPath $requestPath -Raw -Encoding utf8
    ) + (
        Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8
    )
    Assert-True (-not $packText.Contains($env:LEXIQUEST_TEST_LLM_API_KEY)) `
        'packager never copies environment secrets'

    $validReportPath = Join-Path $tempRoot 'valid-report.json'
    [ordered]@{
        schemaVersion = 1
        advisoryOnly = $true
        dataClassification = 'synthetic'
        seedSha256 = $seedHash
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
        findings = @(
            [ordered]@{
                id = 'MF-001'
                severity = 'P1'
                surface = 'login'
                persona = 'privacy-conscious'
                observation = 'ผู้ใช้สังเคราะห์ลังเลก่อนเข้าแบบไม่ใช้บัญชี'
                evidence = 'agent-3 รอบ 2 และ 4 ให้เหตุผลสอดคล้องกัน'
                recommendation = 'ทดสอบข้อความอธิบายโหมดไม่ใช้บัญชีให้ชัดขึ้น'
                verification = 'flutter_widget'
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $validReportPath `
        -Encoding utf8

    $valid = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $validReportPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($valid.ExitCode -eq 0) `
        'valid P1 report remains non-blocking'
    Assert-True ($valid.Output.Contains('REPORT_ONLY')) `
        'valid report is explicitly advisory'

    $invalidPiiPath = Join-Path $tempRoot 'invalid-pii-report.json'
    (Get-Content -LiteralPath $validReportPath -Raw -Encoding utf8).Replace(
        'ผู้ใช้สังเคราะห์ลังเลก่อนเข้าแบบไม่ใช้บัญชี',
        'ติดต่อ student@example.com เพื่อยืนยัน'
    ) | Set-Content -LiteralPath $invalidPiiPath -Encoding utf8
    $invalidPii = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $invalidPiiPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($invalidPii.ExitCode -ne 0) 'report containing PII is rejected'

    $escapedPiiPath = Join-Path $tempRoot 'escaped-pii-report.json'
    (Get-Content -LiteralPath $validReportPath -Raw -Encoding utf8).Replace(
        'ผู้ใช้สังเคราะห์ลังเลก่อนเข้าแบบไม่ใช้บัญชี',
        'ติดต่อ student\u0040example.com เพื่อยืนยัน'
    ) | Set-Content -LiteralPath $escapedPiiPath -Encoding utf8
    $escapedPii = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $escapedPiiPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($escapedPii.ExitCode -ne 0) `
        'JSON-escaped PII is rejected after decoding'

    $invalidClassPath = Join-Path $tempRoot 'invalid-class-report.json'
    $invalidClassReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $invalidClassReport.dataClassification = 'production'
    $invalidClassReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $invalidClassPath -Encoding utf8
    $invalidClass = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $invalidClassPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($invalidClass.ExitCode -ne 0) `
        'non-synthetic report is rejected'

    $invalidHashPath = Join-Path $tempRoot 'invalid-hash-report.json'
    (Get-Content -LiteralPath $validReportPath -Raw -Encoding utf8).Replace(
        $seedHash,
        ('A' * 64)
    ) | Set-Content -LiteralPath $invalidHashPath -Encoding utf8
    $invalidHash = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $invalidHashPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($invalidHash.ExitCode -ne 0) `
        'report with mismatched seed provenance is rejected'

    $invalidManifestPath = Join-Path $tempRoot 'invalid-manifest.json'
    $invalidManifestObject = Get-Content -LiteralPath $manifestPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $invalidManifestObject.dataClassification = 'production'
    $invalidManifestObject | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $invalidManifestPath -Encoding utf8
    $invalidManifest = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $validReportPath,
        '-ManifestPath', $invalidManifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($invalidManifest.ExitCode -ne 0) `
        'modified manifest classification is rejected'

    $tamperedSeedPath = Join-Path $tempRoot 'tampered-seed.md'
    ((Get-Content -LiteralPath $seedPath -Raw -Encoding utf8) + "`nchanged") |
        Set-Content -LiteralPath $tamperedSeedPath -Encoding utf8
    $tamperedSeed = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $validReportPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $tamperedSeedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($tamperedSeed.ExitCode -ne 0) `
        'manifest hash is recomputed from the supplied seed'

    $extraFieldPath = Join-Path $tempRoot 'extra-field-report.json'
    $extraFieldReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $extraFieldReport | Add-Member -NotePropertyName 'agentTranscript' `
        -NotePropertyValue 'raw memory must not enter evidence'
    $extraFieldReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $extraFieldPath -Encoding utf8
    $extraField = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $extraFieldPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($extraField.ExitCode -ne 0) `
        'uncontracted raw transcript fields are rejected'

    $emptyFindingsPath = Join-Path $tempRoot 'empty-findings-report.json'
    $emptyFindingsReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $emptyFindingsReport.findings = @()
    $emptyFindingsReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $emptyFindingsPath -Encoding utf8
    $emptyFindings = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $emptyFindingsPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($emptyFindings.ExitCode -eq 0) `
        'a bounded report with zero findings is valid'

    $tamperedRequestPath = Join-Path $tempRoot 'tampered-request.md'
    ((Get-Content -LiteralPath $requestPath -Raw -Encoding utf8) + "`nchanged") |
        Set-Content -LiteralPath $tamperedRequestPath -Encoding utf8
    $tamperedRequest = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $validReportPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $tamperedRequestPath
    )
    Assert-True ($tamperedRequest.ExitCode -ne 0) `
        'manifest hash is recomputed from the supplied simulation request'

    $stringSchemaPath = Join-Path $tempRoot 'string-schema-report.json'
    $stringSchemaReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $stringSchemaReport.schemaVersion = '1'
    $stringSchemaReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $stringSchemaPath -Encoding utf8
    $stringSchema = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $stringSchemaPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($stringSchema.ExitCode -ne 0) `
        'string schemaVersion is rejected instead of coerced'

    $singleFindingPath = Join-Path $tempRoot 'single-finding-object.json'
    $singleFindingReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $singleFindingReport.findings = $singleFindingReport.findings[0]
    $singleFindingReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $singleFindingPath -Encoding utf8
    $singleFinding = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $singleFindingPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($singleFinding.ExitCode -ne 0) `
        'findings must be encoded as a JSON array'

    $objectTextPath = Join-Path $tempRoot 'object-text-report.json'
    $objectTextReport = Get-Content -LiteralPath $validReportPath -Raw `
        -Encoding utf8 | ConvertFrom-Json
    $objectTextReport.findings[0].observation = [pscustomobject]@{
        agentTranscript = 'raw memory must not enter evidence'
    }
    $objectTextReport | ConvertTo-Json -Depth 8 | Set-Content `
        -LiteralPath $objectTextPath -Encoding utf8
    $objectText = Invoke-Cli -ScriptPath $validatorPath -Arguments @(
        '-ReportPath', $objectTextPath,
        '-ManifestPath', $manifestPath,
        '-SeedPath', $seedPath,
        '-SimulationRequestPath', $requestPath
    )
    Assert-True ($objectText.ExitCode -ne 0) `
        'finding text fields must be JSON strings'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:LEXIQUEST_TEST_LLM_API_KEY -ErrorAction SilentlyContinue
}

Write-Host ("MiroFish synthetic-UAT contract: {0} passed, {1} failed" -f `
    $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0

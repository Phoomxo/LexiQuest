Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\report-writer.ps1')

function New-ReportTestFinding {
    param([string]$Message, [string]$Evidence)
    [pscustomobject]@{
        id = 'P1'; severity = 'high'; category = 'correctness'; message = $Message
        file = 'lib/sample.dart'; line = 12; evidence = $Evidence
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-report-test-" + [guid]::NewGuid().ToString('N'))
$outputRoot = Join-Path $tempRoot 'reports'
$fakeKey = 'ccsk-' + ('a' * 64)
$management = 'ccmk-' + ('b' * 32)
$email = 'owner@example.invalid'
$rawSource = 'private source body sentinel'
$scope = [pscustomobject]@{
    Files = @('lib/sample.dart')
    CommitSha = '0123456789abcdef'
    Dirty = $true
}
$result = [pscustomobject]@{
    Task = 'Review reporting boundary'
    Outcome = 'agreed'
    Agreement = 'agree'
    Primary = [pscustomobject]@{
        Conclusion = 'Primary conclusion'
        Findings = @(New-ReportTestFinding -Message "Detected $fakeKey" -Evidence "Header Bearer $management")
        Provider = 'GPT Pro 20x Stable'; Model = 'gpt-5.6-sol'; Effort = 'high'; LatencyMs = 123
        Usage = [pscustomobject]@{ InputTokens = 10; OutputTokens = 5; TotalTokens = 15; CachedTokens = 2; ProviderReportedCost = 0.25 }
        RawResponse = 'forbidden raw response'
    }
    Review = [pscustomobject]@{
        Conclusion = 'Review conclusion'; Findings = @(); Agreement = 'agree'
        Provider = 'AWS Lite Ultimate'; Model = 'claude-opus-5'; Effort = 'medium'; LatencyMs = 77
        Usage = [pscustomobject]@{ InputTokens = 8; OutputTokens = 4; TotalTokens = 12; CachedTokens = 0; ProviderReportedCost = $null }
    }
    Adjudication = $null
    Authorization = "Bearer $fakeKey"
    DpapiBlob = '01000000d08c9ddf'
    Source = $rawSource
    Email = $email
    Identity = 'private-user-id'
}

try {
    Invoke-AiAnalysisTest 'writes only allowlisted redacted report fields atomically' {
        $written = Write-AiAnalysisReport -Result $result -Scope $scope -RepositoryRoot $tempRoot -OutputRoot $outputRoot -RetentionDays 14
        Assert-True $written.Written 'report written'
        Assert-Match '\d{8}T\d{6}Z-[a-f0-9]{8}$' $written.Path 'run directory name'
        $reportPath = Join-Path $written.Path 'report.md'
        $metadataPath = Join-Path $written.Path 'metadata.json'
        Assert-True (Test-Path -LiteralPath $reportPath -PathType Leaf) 'report exists'
        Assert-True (Test-Path -LiteralPath $metadataPath -PathType Leaf) 'metadata exists'
        Assert-Equal 0 @(Get-ChildItem -LiteralPath $written.Path -Filter '*.tmp' -File).Count 'no temporary files remain'

        $combined = (Get-Content -LiteralPath $reportPath -Raw -Encoding utf8) + (Get-Content -LiteralPath $metadataPath -Raw -Encoding utf8)
        foreach ($forbidden in @($fakeKey, $management, $email, $rawSource, 'forbidden raw response', 'Authorization', 'DpapiBlob', 'RawResponse', 'Identity')) {
            Assert-NotMatch ([regex]::Escape($forbidden)) $combined "forbidden value/property $forbidden"
        }
        Assert-Match '\[REDACTED:maxplusInferenceKey\]' $combined 'inference key redacted'
        Assert-Match '\[REDACTED:maxplusManagementToken\]' $combined 'management token redacted'
        Assert-Match 'GPT Pro 20x Stable' $combined 'primary provider metadata'
        Assert-Match 'claude-opus-5' $combined 'review model metadata'
        Assert-Match '"providerReportedCost"\s*:\s*"unknown"' $combined 'missing provider cost is unknown'
    }

    Invoke-AiAnalysisTest 'NoReport creates no output directory' {
        $noReportRoot = Join-Path $tempRoot 'no-report'
        $notWritten = Write-AiAnalysisReport -Result $result -Scope $scope -RepositoryRoot $tempRoot -OutputRoot $noReportRoot -RetentionDays 14 -NoReport
        Assert-False $notWritten.Written 'NoReport result'
        Assert-False (Test-Path -LiteralPath $noReportRoot) 'NoReport output absent'
    }

    Invoke-AiAnalysisTest 'rejects provider-controlled objects in scalar metadata fields' {
        $maliciousRoot = Join-Path $tempRoot 'malicious-metadata'
        foreach ($field in @('InputTokens', 'ProviderReportedCost')) {
            $badPrimary = $result.Primary.PSObject.Copy()
            $badUsage = $result.Primary.Usage.PSObject.Copy()
            $badUsage.$field = [pscustomobject]@{ Authorization = "Bearer $fakeKey"; RawResponse = 'nested raw response' }
            $badPrimary.Usage = $badUsage
            $badResult = $result.PSObject.Copy()
            $badResult.Primary = $badPrimary
            Assert-Throws { Write-AiAnalysisReport -Result $badResult -Scope $scope -RepositoryRoot $tempRoot -OutputRoot $maliciousRoot -RetentionDays 14 } 'invalidReportMetadata'
            Assert-Equal 0 @(Get-ChildItem -LiteralPath $maliciousRoot -Directory -ErrorAction SilentlyContinue).Count "no report persisted for $field"
        }
    }

    Invoke-AiAnalysisTest 'retention deletes only expired valid run directories' {
        $retentionRoot = Join-Path $tempRoot 'retention'
        $expired = Join-Path $retentionRoot '20000101T000000Z-abcdef12'
        $recent = Join-Path $retentionRoot (([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')) + '-1234abcd')
        $unrelated = Join-Path $retentionRoot 'do-not-delete'
        [System.IO.Directory]::CreateDirectory($expired) | Out-Null
        [System.IO.Directory]::CreateDirectory($recent) | Out-Null
        [System.IO.Directory]::CreateDirectory($unrelated) | Out-Null
        Remove-ExpiredAiAnalysisReports -OutputRoot $retentionRoot -RetentionDays 14 -NowUtc ([DateTime]::UtcNow)
        Assert-False (Test-Path -LiteralPath $expired) 'expired valid run removed'
        Assert-True (Test-Path -LiteralPath $recent) 'recent run retained'
        Assert-True (Test-Path -LiteralPath $unrelated) 'unrelated directory retained'
    }
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Complete-AiAnalysisTests -Suite 'Report writer'

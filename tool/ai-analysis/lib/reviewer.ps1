Set-StrictMode -Version Latest

function Get-AiAnalysisReviewProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-AiAnalysisUnsafeModelValue {
    param($Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) {
        return $Value -match '(?is)```(?:diff|patch|powershell|bash|sh)|\b(?:execute|run|invoke)\s+(?:(?:a|the)\s+)?(?:shell\s+)?command\b|\b(?:apply|emit)\s+(?:a\s+)?patch\b|\bgit\s+(?:add|commit|push)\b|\bstage\s+(?:these|the)\s+files\b|\b(?:delete|remove|write|modify|overwrite)\s+(?:(?:the|this|these|a)\s+)?(?:file|source|workspace)\b'
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '^(?i:tool_calls?|shell_command|patch)$') { return $true }
            if (Test-AiAnalysisUnsafeModelValue -Value $Value[$key]) { return $true }
        }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if (Test-AiAnalysisUnsafeModelValue -Value $item) { return $true }
        }
        return $false
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        if ($property.Name -match '^(?i:tool_calls?|shell_command|patch)$') { return $true }
        if (Test-AiAnalysisUnsafeModelValue -Value $property.Value) { return $true }
    }
    return $false
}

function Assert-AiAnalysisSafeModelResult {
    param(
        [Parameter(Mandatory)]$Result,
        [Parameter(Mandatory)]$Context,
        [switch]$RequireAgreement
    )

    $conclusion = Get-AiAnalysisReviewProperty -Object $Result -Name 'Conclusion'
    $findingsProperty = $Result.PSObject.Properties['Findings']
    if ([string]::IsNullOrWhiteSpace([string]$conclusion) -or $null -eq $findingsProperty) {
        throw 'malformedResponse'
    }
    if (Test-AiAnalysisUnsafeModelValue -Value $Result) { throw 'unsafeModelOutput' }

    foreach ($finding in @($findingsProperty.Value)) {
        foreach ($required in @('id', 'severity', 'category', 'message', 'file', 'line', 'evidence')) {
            if ($null -eq $finding.PSObject.Properties[$required]) { throw 'malformedResponse' }
        }
        $file = [string]$finding.file
        $line = 0
        if (-not [int]::TryParse([string]$finding.line, [ref]$line) -or $line -le 0 -or $file -cnotin @($Context.Files)) {
            throw 'invalidCitation'
        }
    }

    if ($RequireAgreement) {
        $agreement = [string](Get-AiAnalysisReviewProperty -Object $Result -Name 'Agreement')
        if ($agreement -cnotin @('agree', 'disagree')) { throw 'malformedResponse' }
    }
}

function Get-AiAnalysisContradictions {
    param([Parameter(Mandatory)]$Primary, [Parameter(Mandatory)]$Review)

    $primaryIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($finding in @($Primary.Findings)) { [void]$primaryIds.Add([string]$finding.id) }
    $contradictions = New-Object System.Collections.ArrayList
    foreach ($finding in @($Review.Findings)) {
        $target = Get-AiAnalysisReviewProperty -Object $finding -Name 'contradicts'
        if ([string]::IsNullOrWhiteSpace([string]$target)) { $target = [string]$finding.id }
        $severity = ([string]$finding.severity).ToLowerInvariant()
        if ($primaryIds.Contains([string]$target) -and $severity -in @('high', 'critical')) {
            [void]$contradictions.Add($finding)
        }
    }
    return @($contradictions)
}

function New-AiAnalysisPrimaryPrompt {
    param([Parameter(Mandatory)][string]$Task, [Parameter(Mandatory)]$Context)
    $files = @($Context.Files) -join "`n"
    return @"
You are a read-only software analyst. Analyze only the supplied excerpts. Do not request tools, commands, patches, file changes, Git actions, or additional data. Cite only an allowed file and a positive supplied line number. Return only raw JSON. Do not use Markdown fences or add any text outside JSON. The JSON must contain conclusion and findings. Every finding must contain id, severity, category, message, file, line, and evidence.

TASK:
$Task

ALLOWED FILES:
$files

BOUNDED SOURCE:
$($Context.Text)
"@
}

function New-AiAnalysisReviewerPrompt {
    param([Parameter(Mandatory)][string]$Task, [Parameter(Mandatory)]$Context, [Parameter(Mandatory)]$Primary)
    $primaryProjection = [pscustomobject]@{
        conclusion = [string]$Primary.Conclusion
        findings = @($Primary.Findings)
    } | ConvertTo-Json -Depth 20 -Compress
    $files = @($Context.Files) -join "`n"
    return @"
You are an independent read-only reviewer. Check the primary analysis against only the supplied excerpts. Do not request tools, commands, patches, file changes, or Git actions. Return only raw JSON. Do not use Markdown fences or add any text outside JSON. The JSON must contain agreement (agree or disagree), conclusion, and findings. Every finding must contain id, severity, category, message, file, line, and evidence. Reuse a primary finding id, or add a contradicts field, when contradicting it.

TASK:
$Task

ALLOWED FILES:
$files

PRIMARY ANALYSIS:
$primaryProjection

BOUNDED SOURCE:
$($Context.Text)
"@
}

function New-AiAnalysisAdjudicationPrompt {
    param([Parameter(Mandatory)]$Primary, [Parameter(Mandatory)]$Review)

    $references = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($finding in @($Primary.Findings) + @($Review.Findings)) {
        [void]$references.Add("$([string]$finding.file):$([int]$finding.line)")
    }
    $referenceText = @($references | Sort-Object) -join "`n"
    return @"
Resolve one critical disagreement using only the two conclusions and cited references below. Do not request source, tools, commands, patches, file changes, or Git actions. Return only raw JSON. Do not use Markdown fences or add any text outside JSON. The JSON must contain conclusion and findings.

PRIMARY CONCLUSION:
$([string]$Primary.Conclusion)

REVIEW CONCLUSION:
$([string]$Review.Conclusion)

CITED REFERENCES:
$referenceText
"@
}

function Invoke-AiAnalysisReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)]$Context,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][scriptblock]$PrimaryInvoker,
        [Parameter(Mandatory)][scriptblock]$ReviewerInvoker,
        [Parameter(Mandatory)][scriptblock]$AdjudicatorInvoker
    )

    $providerCalls = 0
    $primaryPrompt = New-AiAnalysisPrimaryPrompt -Task $Task -Context $Context
    $primary = & $PrimaryInvoker $primaryPrompt ([string]$Policy.GptEffort) ([int]$Policy.GptMaxOutputTokens)
    $providerCalls++
    Assert-AiAnalysisSafeModelResult -Result $primary -Context $Context

    if (-not [bool]$Policy.ReviewerRequired) {
        return [pscustomobject]@{
            Outcome = 'primaryOnly'
            Agreement = 'notReviewed'
            Primary = $primary
            Review = $null
            Adjudication = $null
            ProviderCalls = $providerCalls
        }
    }

    $reviewPrompt = New-AiAnalysisReviewerPrompt -Task $Task -Context $Context -Primary $primary
    $review = & $ReviewerInvoker $reviewPrompt ([string]$Policy.ClaudeEffort) ([int]$Policy.ClaudeMaxOutputTokens)
    $providerCalls++
    Assert-AiAnalysisSafeModelResult -Result $review -Context $Context -RequireAgreement

    $contradictions = @(Get-AiAnalysisContradictions -Primary $primary -Review $review)
    $agreed = ([string]$review.Agreement -ceq 'agree' -and $contradictions.Count -eq 0)
    if ($agreed) {
        return [pscustomobject]@{
            Outcome = 'agreed'
            Agreement = 'agree'
            Primary = $primary
            Review = $review
            Adjudication = $null
            ProviderCalls = $providerCalls
        }
    }

    $critical = @($contradictions | Where-Object { ([string]$_.severity).ToLowerInvariant() -eq 'critical' })
    if ($critical.Count -eq 0) {
        return [pscustomobject]@{
            Outcome = 'disagreement'
            Agreement = 'disagree'
            Primary = $primary
            Review = $review
            Adjudication = $null
            ProviderCalls = $providerCalls
        }
    }

    $adjudicationPrompt = New-AiAnalysisAdjudicationPrompt -Primary $primary -Review $review
    $adjudication = & $AdjudicatorInvoker $adjudicationPrompt 'ultra' 65536
    $providerCalls++
    Assert-AiAnalysisSafeModelResult -Result $adjudication -Context $Context
    return [pscustomobject]@{
        Outcome = 'adjudicated'
        Agreement = 'disagree'
        Primary = $primary
        Review = $review
        Adjudication = $adjudication
        ProviderCalls = $providerCalls
    }
}

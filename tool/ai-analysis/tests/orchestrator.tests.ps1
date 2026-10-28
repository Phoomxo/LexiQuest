Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\config.ps1')
. (Join-Path $PSScriptRoot '..\lib\effort-router.ps1')
. (Join-Path $PSScriptRoot '..\lib\secret-store.ps1')
. (Join-Path $PSScriptRoot '..\lib\context-builder.ps1')
. (Join-Path $PSScriptRoot '..\lib\maxplus-client.ps1')
. (Join-Path $PSScriptRoot '..\lib\reviewer.ps1')
. (Join-Path $PSScriptRoot '..\lib\report-writer.ps1')
. (Join-Path $PSScriptRoot '..\lib\analysis-command.ps1')
. (Join-Path $PSScriptRoot '..\lib\smoke-command.ps1')

function New-TestFinding {
    param(
        [string]$Id = 'P1',
        [string]$Severity = 'medium',
        [string]$Message = 'finding',
        [string]$File = 'lib/sample.dart',
        [int]$Line = 12,
        [string]$Evidence = 'bounded evidence'
    )
    [pscustomobject]@{
        id = $Id
        severity = $Severity
        category = 'correctness'
        message = $Message
        file = $File
        line = $Line
        evidence = $Evidence
    }
}

function New-TestModelResult {
    param(
        [string]$Conclusion = 'safe conclusion',
        [object[]]$Findings = @(),
        [string]$Agreement
    )
    $result = [ordered]@{
        Conclusion = $Conclusion
        Findings = @($Findings)
        Usage = [pscustomobject]@{ InputTokens = 1; OutputTokens = 1; TotalTokens = 2; CachedTokens = 0; ProviderReportedCost = 'unknown' }
        Provider = 'test-provider'
        Model = 'test-model'
        Effort = 'low'
        LatencyMs = 1
    }
    if ($PSBoundParameters.ContainsKey('Agreement')) { $result.Agreement = $Agreement }
    [pscustomobject]$result
}

function New-TestGptSseBody {
    $response = '{"output":[{"content":[{"type":"output_text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}]}],"usage":{"input_tokens":1,"output_tokens":1,"total_tokens":2}}'
    return "event: response.completed`ndata: {`"type`":`"response.completed`",`"response`":$response}`n`n"
}

$context = [pscustomobject]@{
    Files = @('lib/sample.dart')
    Text = "--- FILE: lib/sample.dart ---`n    12 | source body sentinel`n"
    CharacterCount = 64
    Mode = 'explicit'
}

Invoke-AiAnalysisTest 'simple work calls only the primary analyst' {
    $calls = [pscustomobject]@{ Primary = 0; Reviewer = 0; Adjudicator = 0 }
    $primary = { param($prompt, $effort, $maxTokens) $calls.Primary++; New-TestModelResult }
    $reviewer = { param($prompt, $effort, $maxTokens) $calls.Reviewer++; New-TestModelResult -Agreement agree }
    $adjudicator = { param($prompt, $effort, $maxTokens) $calls.Adjudicator++; New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'low'; ClaudeEffort = $null; ReviewerRequired = $false; GptMaxOutputTokens = 2048; ClaudeMaxOutputTokens = $null; Classification = 'simple' }
    $result = Invoke-AiAnalysisReview -Task 'Summarize files' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator
    Assert-Equal 1 $calls.Primary 'one primary call'
    Assert-Equal 0 $calls.Reviewer 'no reviewer call'
    Assert-Equal 0 $calls.Adjudicator 'no adjudicator call'
    Assert-Equal 'primaryOnly' $result.Outcome 'primary-only outcome'
    Assert-Equal 1 $result.ProviderCalls 'provider call count'
}

Invoke-AiAnalysisTest 'agreement calls primary and reviewer once without adjudication' {
    $calls = [pscustomobject]@{ Primary = 0; Reviewer = 0; Adjudicator = 0 }
    $primary = { param($prompt, $effort, $maxTokens) $calls.Primary++; New-TestModelResult -Findings @(New-TestFinding) }
    $reviewer = { param($prompt, $effort, $maxTokens) $calls.Reviewer++; New-TestModelResult -Agreement agree }
    $adjudicator = { param($prompt, $effort, $maxTokens) $calls.Adjudicator++; New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'medium'; ClaudeEffort = 'low'; ReviewerRequired = $true; GptMaxOutputTokens = 4096; ClaudeMaxOutputTokens = 4096; Classification = 'focusedPackage' }
    $result = Invoke-AiAnalysisReview -Task 'Review source behavior' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator
    Assert-Equal 1 $calls.Primary 'one primary call'
    Assert-Equal 1 $calls.Reviewer 'one reviewer call'
    Assert-Equal 0 $calls.Adjudicator 'agreement does not adjudicate'
    Assert-Equal 'agreed' $result.Outcome 'agreed outcome'
    Assert-Equal 'agree' $result.Agreement 'agreement value'
}

Invoke-AiAnalysisTest 'critical contradiction invokes one bounded GPT adjudication' {
    $calls = [pscustomobject]@{ Primary = 0; Reviewer = 0; Adjudicator = 0 }
    $script:CapturedAdjudicationPrompt = $null
    $primary = { param($prompt, $effort, $maxTokens) $calls.Primary++; New-TestModelResult -Conclusion 'primary conclusion' -Findings @(New-TestFinding -Id P1) }
    $reviewer = { param($prompt, $effort, $maxTokens) $calls.Reviewer++; New-TestModelResult -Conclusion 'review conclusion' -Agreement disagree -Findings @(New-TestFinding -Id P1 -Severity critical -Message 'contradicts P1') }
    $adjudicator = {
        param($prompt, $effort, $maxTokens)
        $calls.Adjudicator++
        $script:CapturedAdjudicationPrompt = $prompt
        Assert-Equal 'ultra' $effort 'critical GPT effort'
        Assert-Equal 65536 $maxTokens 'critical output cap'
        New-TestModelResult -Conclusion 'final conclusion'
    }
    $policy = [pscustomobject]@{ GptEffort = 'xhigh'; ClaudeEffort = 'high'; ReviewerRequired = $true; GptMaxOutputTokens = 32768; ClaudeMaxOutputTokens = 16384; Classification = 'architectureSensitive' }
    $result = Invoke-AiAnalysisReview -Task 'Review race condition' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator
    Assert-Equal 1 $calls.Primary 'one primary call'
    Assert-Equal 1 $calls.Reviewer 'one reviewer call'
    Assert-Equal 1 $calls.Adjudicator 'one critical adjudication'
    Assert-NotMatch 'source body sentinel' $script:CapturedAdjudicationPrompt 'adjudication excludes source context'
    Assert-Match 'lib/sample\.dart:12' $script:CapturedAdjudicationPrompt 'adjudication keeps cited reference'
    Assert-Equal 'adjudicated' $result.Outcome 'adjudicated outcome'
    Assert-Equal 3 $result.ProviderCalls 'three provider calls'
}

Invoke-AiAnalysisTest 'noncritical disagreement remains visible without adjudication' {
    $calls = [pscustomobject]@{ Primary = 0; Reviewer = 0; Adjudicator = 0 }
    $primary = { param($prompt, $effort, $maxTokens) $calls.Primary++; New-TestModelResult -Findings @(New-TestFinding -Id P1) }
    $reviewer = { param($prompt, $effort, $maxTokens) $calls.Reviewer++; New-TestModelResult -Agreement disagree -Findings @(New-TestFinding -Id P1 -Severity high) }
    $adjudicator = { param($prompt, $effort, $maxTokens) $calls.Adjudicator++; New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'high'; ClaudeEffort = 'medium'; ReviewerRequired = $true; GptMaxOutputTokens = 8192; ClaudeMaxOutputTokens = 8192; Classification = 'failedOrMultiFile' }
    $result = Invoke-AiAnalysisReview -Task 'Review failed test' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator
    Assert-Equal 0 $calls.Adjudicator 'noncritical disagreement not adjudicated'
    Assert-Equal 'disagreement' $result.Outcome 'disagreement visible'
    Assert-Equal 'disagree' $result.Agreement 'disagreement value'
}

Invoke-AiAnalysisTest 'provider failure stops the pipeline immediately' {
    $calls = [pscustomobject]@{ Primary = 0; Reviewer = 0; Adjudicator = 0 }
    $primary = { param($prompt, $effort, $maxTokens) $calls.Primary++; throw 'quota' }
    $reviewer = { param($prompt, $effort, $maxTokens) $calls.Reviewer++; New-TestModelResult -Agreement agree }
    $adjudicator = { param($prompt, $effort, $maxTokens) $calls.Adjudicator++; New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'high'; ClaudeEffort = 'medium'; ReviewerRequired = $true; GptMaxOutputTokens = 8192; ClaudeMaxOutputTokens = 8192; Classification = 'failedOrMultiFile' }
    Assert-Throws { Invoke-AiAnalysisReview -Task 'Review failure' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $reviewer -AdjudicatorInvoker $adjudicator } 'quota'
    Assert-Equal 1 $calls.Primary 'primary attempted once'
    Assert-Equal 0 $calls.Reviewer 'reviewer skipped after failure'
    Assert-Equal 0 $calls.Adjudicator 'adjudicator skipped after failure'
}

Invoke-AiAnalysisTest 'rejects citations outside the supplied context' {
    $primary = { param($prompt, $effort, $maxTokens) New-TestModelResult -Findings @(New-TestFinding -File 'lib/not-supplied.dart') }
    $unused = { param($prompt, $effort, $maxTokens) New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'low'; ClaudeEffort = $null; ReviewerRequired = $false; GptMaxOutputTokens = 2048; ClaudeMaxOutputTokens = $null; Classification = 'simple' }
    Assert-Throws { Invoke-AiAnalysisReview -Task 'Summarize' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $unused -AdjudicatorInvoker $unused } 'invalidCitation'
}

Invoke-AiAnalysisTest 'rejects model output that requests workspace mutation' {
    $primary = { param($prompt, $effort, $maxTokens) New-TestModelResult -Conclusion 'Run git commit now' }
    $unused = { param($prompt, $effort, $maxTokens) New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'low'; ClaudeEffort = $null; ReviewerRequired = $false; GptMaxOutputTokens = 2048; ClaudeMaxOutputTokens = $null; Classification = 'simple' }
    Assert-Throws { Invoke-AiAnalysisReview -Task 'Summarize' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $unused -AdjudicatorInvoker $unused } 'unsafeModelOutput'
}

Invoke-AiAnalysisTest 'rejects mutation requests nested in finding strings' {
    $primary = {
        param($prompt, $effort, $maxTokens)
        New-TestModelResult -Findings @(New-TestFinding -Message 'Execute a command: Remove-Item the source file')
    }
    $unused = { param($prompt, $effort, $maxTokens) New-TestModelResult }
    $policy = [pscustomobject]@{ GptEffort = 'low'; ClaudeEffort = $null; ReviewerRequired = $false; GptMaxOutputTokens = 2048; ClaudeMaxOutputTokens = $null; Classification = 'simple' }
    Assert-Throws { Invoke-AiAnalysisReview -Task 'Summarize' -Context $context -Policy $policy -PrimaryInvoker $primary -ReviewerInvoker $unused -AdjudicatorInvoker $unused } 'unsafeModelOutput'
}

Invoke-AiAnalysisTest 'public scripts expose only the approved command contracts' {
    $invokePath = Join-Path $PSScriptRoot '..\invoke-analysis.ps1'
    $smokePath = Join-Path $PSScriptRoot '..\test-provider-smoke.ps1'
    Assert-True (Test-Path -LiteralPath $invokePath -PathType Leaf) 'analysis entry point exists'
    Assert-True (Test-Path -LiteralPath $smokePath -PathType Leaf) 'smoke entry point exists'
    $invokeCommand = Get-Command -Name $invokePath
    foreach ($parameter in @('Task', 'Path', 'ChangedFiles', 'Effort', 'NoReviewer', 'NoReport', 'TimeoutSeconds')) {
        Assert-True ($invokeCommand.Parameters.ContainsKey($parameter)) "analysis parameter $parameter"
    }
    foreach ($forbidden in @('Key', 'ApiKey', 'GptTransport', 'ClaudeTransport')) {
        Assert-False ($invokeCommand.Parameters.ContainsKey($forbidden)) "forbidden public parameter $forbidden"
    }
    $smokeCommand = Get-Command -Name $smokePath
    Assert-False ($smokeCommand.Parameters.ContainsKey('Task')) 'smoke accepts no task'
    Assert-False ($smokeCommand.Parameters.ContainsKey('Path')) 'smoke accepts no project path'
    Assert-True ($smokeCommand.Parameters.ContainsKey('CertifyEfforts')) 'smoke exposes explicit effort certification'
    $smokeSource = (Get-Content -LiteralPath $smokePath -Raw -Encoding utf8) + (Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\smoke-command.ps1') -Raw -Encoding utf8)
    Assert-Match 'Return only raw JSON: \{"conclusion":"ok","findings":\[\]\}\. Do not use Markdown fences or add any other text\.' $smokeSource 'strict fixed non-project smoke prompt'
    Assert-Match 'ConvertTo-AiAnalysisProviderMetadata' $smokeSource 'smoke uses allowlisted scalar metadata projection'
    $reviewerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\reviewer.ps1') -Raw -Encoding utf8
    Assert-Match 'Return only raw JSON\. Do not use Markdown fences or add any text outside JSON\.' $reviewerSource 'analysis prompts require raw JSON'
}

Invoke-AiAnalysisTest 'composition supports changed files explicit paths NoReport and timeout injection' {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-command-test-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory((Join-Path $tempRepo 'lib')) | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $tempRepo 'lib\sample.dart'), 'const value = 1;', (New-Object System.Text.UTF8Encoding($false)))
        & git -C $tempRepo init --quiet
        & git -C $tempRepo config user.email 'tests@example.invalid'
        & git -C $tempRepo config user.name 'LexiQuest Tests'
        & git -C $tempRepo add -- lib/sample.dart
        & git -C $tempRepo commit --quiet -m baseline
        [System.IO.File]::WriteAllText((Join-Path $tempRepo 'lib\sample.dart'), 'const value = 2;', (New-Object System.Text.UTF8Encoding($false)))

        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('d' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $timeouts = New-Object System.Collections.ArrayList
        $gptTransport = {
            param($request)
            [void]$timeouts.Add($request.TimeoutSeconds)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"gpt-5.6-sol"}]}' } }
            return [pscustomobject]@{ StatusCode = 200; Body = (New-TestGptSseBody) }
        }
        $outputRoot = Join-Path $tempRepo 'build\ai-analysis'
        $changed = Invoke-AiAnalysisCommand -Task 'Summarize tracked change' -ChangedFiles -TimeoutSeconds 17 -RepositoryRoot $tempRepo -OutputRoot $outputRoot -SecretReader $secretReader -GptTransport $gptTransport
        Assert-Equal @('lib/sample.dart') $changed.Context.Files 'changed tracked scope'
        Assert-True $changed.Report.Written 'successful analysis writes report'
        Assert-True (@($timeouts | Where-Object { $_ -ne 17 }).Count -eq 0) 'timeout propagated to every request'

        $before = @(Get-ChildItem -LiteralPath $outputRoot -Directory).Count
        $explicit = Invoke-AiAnalysisCommand -Task 'Summarize explicit source' -Path @('lib/sample.dart') -Effort High -NoReviewer -NoReport -RepositoryRoot $tempRepo -OutputRoot $outputRoot -SecretReader $secretReader -GptTransport $gptTransport
        Assert-Equal 'explicit' $explicit.Context.Mode 'explicit scope mode'
        Assert-Equal 'high' $explicit.Policy.GptEffort 'manual effort override propagated'
        Assert-False $explicit.Policy.ReviewerRequired 'optional reviewer disabled'
        Assert-False $explicit.Report.Written 'NoReport honored'
        Assert-Equal $before @(Get-ChildItem -LiteralPath $outputRoot -Directory).Count 'NoReport adds no run directory'
        Assert-Throws { Invoke-AiAnalysisCommand -Task 'Ambiguous' -Path @('lib/sample.dart') -ChangedFiles -RepositoryRoot $tempRepo -OutputRoot $outputRoot -SecretReader $secretReader -GptTransport $gptTransport } 'ambiguousScope'
        Assert-Throws { Invoke-AiAnalysisCommand -Task 'Privacy architecture review' -Path @('lib/sample.dart') -NoReviewer -RepositoryRoot $tempRepo -OutputRoot $outputRoot -SecretReader $secretReader -GptTransport $gptTransport } 'reviewerRequired'
    } finally {
        if (Test-Path -LiteralPath $tempRepo) { Remove-Item -LiteralPath $tempRepo -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'composition selects exactly one Claude model and never falls back' {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-hybrid-route-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory((Join-Path $tempRepo 'lib')) | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $tempRepo 'lib\sample.dart'), 'const value = 1;', (New-Object System.Text.UTF8Encoding($false)))
        & git -C $tempRepo init --quiet
        & git -C $tempRepo config user.email 'tests@example.invalid'
        & git -C $tempRepo config user.name 'LexiQuest Tests'
        & git -C $tempRepo add -- lib/sample.dart
        & git -C $tempRepo commit --quiet -m baseline

        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('7' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $gptTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"gpt-5.6-sol"}]}' } }
            [pscustomobject]@{ StatusCode = 200; Body = (New-TestGptSseBody) }
        }
        $selectedModels = New-Object System.Collections.ArrayList
        $claudeTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}' } }
            [void]$selectedModels.Add([string]$request.Body.model)
            [pscustomobject]@{ StatusCode = 200; Body = '{"content":[{"type":"text","text":"{\"agreement\":\"agree\",\"conclusion\":\"ok\",\"findings\":[]}"}],"usage":{"input_tokens":1,"output_tokens":1}}' }
        }

        $null = Invoke-AiAnalysisCommand -Task 'Review provider behavior' -Path @('lib/sample.dart') -NoReport -RepositoryRoot $tempRepo -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $claudeTransport
        $null = Invoke-AiAnalysisCommand -Task 'Security credential review' -Path @('lib/sample.dart') -NoReport -RepositoryRoot $tempRepo -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $claudeTransport
        Assert-Equal @('claude-sonnet-5', 'claude-opus-5') @($selectedModels) 'one deterministic reviewer model per command'

        $failedModels = New-Object System.Collections.ArrayList
        $failingClaudeTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}' } }
            [void]$failedModels.Add([string]$request.Body.model)
            [pscustomobject]@{ StatusCode = 503; Body = '{"error":{"message":"unavailable"}}' }
        }
        Assert-Throws {
            Invoke-AiAnalysisCommand -Task 'Review provider behavior' -Path @('lib/sample.dart') -RepositoryRoot $tempRepo -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $failingClaudeTransport
        } 'unavailable'
        Assert-Equal @('claude-sonnet-5') @($failedModels) 'Sonnet failure does not call Opus'
        Assert-False (Test-Path -LiteralPath (Join-Path $tempRepo 'build\ai-analysis') -PathType Container) 'failed route writes no report'
    } finally {
        if (Test-Path -LiteralPath $tempRepo) { Remove-Item -LiteralPath $tempRepo -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'bounded smoke calls each provider route exactly once and persists metadata only' {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-smoke-test-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('f' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $gptRequests = New-Object System.Collections.ArrayList
        $claudeRequests = New-Object System.Collections.ArrayList
        $gptTransport = {
            param($request)
            [void]$gptRequests.Add([pscustomobject]@{ Uri = $request.Uri; Method = $request.Method; TimeoutSeconds = $request.TimeoutSeconds })
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"gpt-5.6-sol"}]}' } }
            [pscustomobject]@{ StatusCode = 200; Body = (New-TestGptSseBody) }
        }
        $claudeTransport = {
            param($request)
            [void]$claudeRequests.Add([pscustomobject]@{
                Uri = $request.Uri
                Method = $request.Method
                TimeoutSeconds = $request.TimeoutSeconds
                Model = if ($null -ne $request.Body) { [string]$request.Body.model } else { $null }
                Effort = if ($null -ne $request.Body) { [string]$request.Body.output_config.effort } else { $null }
            })
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}' } }
            [pscustomobject]@{ StatusCode = 200; Body = '{"content":[{"type":"text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}],"usage":{"input_tokens":1,"output_tokens":1}}' }
        }
        $smoke = Invoke-AiAnalysisProviderSmoke -RepositoryRoot $tempRoot -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $claudeTransport -TimeoutSeconds 19
        Assert-Equal 3 $gptRequests.Count 'GPT account model generation calls'
        Assert-Equal 4 $claudeRequests.Count 'Claude account model and two generation calls'
        Assert-Equal 1 @($gptRequests | Where-Object { $_.Uri.AbsolutePath.EndsWith('/v1/me') }).Count 'one GPT account call'
        Assert-Equal 1 @($gptRequests | Where-Object { $_.Uri.AbsolutePath.EndsWith('/v1/models') }).Count 'one GPT model call'
        Assert-Equal 1 @($gptRequests | Where-Object { $_.Method -eq 'POST' }).Count 'one GPT generation call'
        Assert-Equal 1 @($claudeRequests | Where-Object { $_.Uri.AbsolutePath.EndsWith('/v1/me') }).Count 'one Claude account call'
        Assert-Equal 1 @($claudeRequests | Where-Object { $_.Uri.AbsolutePath.EndsWith('/v1/models') }).Count 'one Claude model call'
        $claudeGenerations = @($claudeRequests | Where-Object { $_.Method -eq 'POST' })
        Assert-Equal @('claude-sonnet-5', 'claude-opus-5') @($claudeGenerations.Model) 'both Claude smoke models exactly once'
        Assert-Equal @('low', 'high') @($claudeGenerations.Effort) 'lowest routed Claude efforts'
        Assert-True (@($gptRequests + $claudeRequests | Where-Object { $_.TimeoutSeconds -ne 19 }).Count -eq 0) 'smoke timeout propagated'
        $metadataText = Get-Content -LiteralPath (Join-Path $smoke.Path 'metadata.json') -Raw -Encoding utf8
        Assert-NotMatch 'Return JSON|prompt|response|source|authorization|ccsk-' $metadataText 'smoke metadata excludes request content and secrets'
        Assert-Match '"outcome"\s*:\s*"pass"' $metadataText 'smoke pass outcome'
        $metadata = $metadataText | ConvertFrom-Json
        Assert-Equal @('gpt-5.6-sol', 'claude-sonnet-5', 'claude-opus-5') @($metadata.providers.model) 'three smoke provider records'
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'effort certification probes every level once without downgrade' {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-effort-smoke-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('1' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $gptEfforts = New-Object System.Collections.ArrayList
        $claudeProbes = New-Object System.Collections.ArrayList
        $gptTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":50,"key":{"active":true,"limit_usd":100,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"gpt-5.6-sol"}]}' } }
            $effort = [string]$request.Body.reasoning.effort
            [void]$gptEfforts.Add($effort)
            [pscustomobject]@{ StatusCode = 200; Body = (New-TestGptSseBody) }
        }
        $claudeTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":50,"key":{"active":true,"limit_usd":100,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}' } }
            [void]$claudeProbes.Add([pscustomobject]@{ Model=[string]$request.Body.model; Effort=[string]$request.Body.output_config.effort })
            [pscustomobject]@{ StatusCode = 200; Body = '{"content":[{"type":"text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}],"usage":{"input_tokens":1,"output_tokens":1}}' }
        }
        $smoke = Invoke-AiAnalysisProviderSmoke -RepositoryRoot $tempRoot -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $claudeTransport -CertifyEfforts
        Assert-Equal @('low', 'medium', 'high', 'xhigh', 'max', 'ultra') @($gptEfforts) 'GPT effort probes exactly once in order'
        Assert-Equal @(
            'claude-sonnet-5:low',
            'claude-opus-5:high',
            'claude-sonnet-5:medium',
            'claude-sonnet-5:high',
            'claude-opus-5:xhigh',
            'claude-opus-5:max'
        ) @($claudeProbes | ForEach-Object { "$($_.Model):$($_.Effort)" }) 'Claude model-specific effort probes exactly once'
        $metadata = Get-Content -LiteralPath (Join-Path $smoke.Path 'metadata.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-Equal 12 @($metadata.effortSupport).Count 'complete model-specific effort support matrix'
        Assert-Equal 3 @($metadata.effortSupport | Where-Object { $_.model -eq 'claude-sonnet-5' }).Count 'Sonnet low medium high rows'
        Assert-Equal 3 @($metadata.effortSupport | Where-Object { $_.model -eq 'claude-opus-5' }).Count 'Opus high xhigh max rows'
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'effort certification stops later probes for only the unsupported model' {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-effort-stop-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    try {
        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('2' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $gptEfforts = New-Object System.Collections.ArrayList
        $claudeProbes = New-Object System.Collections.ArrayList
        $gptTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":50,"key":{"active":true,"limit_usd":100,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"gpt-5.6-sol"}]}' } }
            $effort = [string]$request.Body.reasoning.effort
            [void]$gptEfforts.Add($effort)
            if ($effort -ceq 'xhigh') { return [pscustomobject]@{ StatusCode = 400; Body = '{"error":{"message":"unsupported effort xhigh"}}' } }
            [pscustomobject]@{ StatusCode = 200; Body = (New-TestGptSseBody) }
        }
        $claudeTransport = {
            param($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"credit_usd":50,"key":{"active":true,"limit_usd":100,"limit_period":"daily","limit_used_usd":1}}' } }
            if ($request.Uri.AbsolutePath.EndsWith('/v1/models')) { return [pscustomobject]@{ StatusCode = 200; Body = '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"}]}' } }
            $model = [string]$request.Body.model
            $effort = [string]$request.Body.output_config.effort
            [void]$claudeProbes.Add("$model`:$effort")
            if ($model -ceq 'claude-sonnet-5' -and $effort -ceq 'medium') {
                return [pscustomobject]@{ StatusCode = 400; Body = '{"error":{"message":"unsupported effort medium"}}' }
            }
            [pscustomobject]@{ StatusCode = 200; Body = '{"content":[{"type":"text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}],"usage":{"input_tokens":1,"output_tokens":1}}' }
        }
        $smoke = Invoke-AiAnalysisProviderSmoke -RepositoryRoot $tempRoot -SecretReader $secretReader -GptTransport $gptTransport -ClaudeTransport $claudeTransport -CertifyEfforts
        Assert-Equal @('low', 'medium', 'high', 'xhigh') @($gptEfforts) 'GPT stops after unsupported xhigh'
        Assert-Equal @(
            'claude-sonnet-5:low',
            'claude-opus-5:high',
            'claude-sonnet-5:medium',
            'claude-opus-5:xhigh',
            'claude-opus-5:max'
        ) @($claudeProbes) 'Sonnet stops after medium while Opus certification continues'
        $metadata = Get-Content -LiteralPath (Join-Path $smoke.Path 'metadata.json') -Raw -Encoding utf8 | ConvertFrom-Json
        Assert-Equal 1 @($metadata.effortSupport | Where-Object { $_.model -eq 'gpt-5.6-sol' -and $_.effort -eq 'xhigh' -and $_.status -eq 'unsupportedEffort' }).Count 'GPT unsupported row recorded'
        Assert-Equal 1 @($metadata.effortSupport | Where-Object { $_.model -eq 'claude-sonnet-5' -and $_.effort -eq 'medium' -and $_.status -eq 'unsupportedEffort' }).Count 'Sonnet unsupported row recorded'
    } finally {
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'composition stops on the first provider failure without a partial report' {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-command-fail-" + [guid]::NewGuid().ToString('N'))
    [System.IO.Directory]::CreateDirectory((Join-Path $tempRepo 'lib')) | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $tempRepo 'lib\sample.dart'), 'const value = 1;', (New-Object System.Text.UTF8Encoding($false)))
        & git -C $tempRepo init --quiet
        & git -C $tempRepo config user.email 'tests@example.invalid'
        & git -C $tempRepo config user.name 'LexiQuest Tests'
        & git -C $tempRepo add -- lib/sample.dart
        & git -C $tempRepo commit --quiet -m baseline
        [System.IO.File]::WriteAllText((Join-Path $tempRepo 'lib\sample.dart'), 'const value = 2;', (New-Object System.Text.UTF8Encoding($false)))
        $fakeSecureKey = ConvertTo-SecureString ('ccsk-' + ('e' * 64)) -AsPlainText -Force
        $secretReader = { param($secretId) $fakeSecureKey }
        $calls = New-Object System.Collections.ArrayList
        $failingTransport = { param($request) [void]$calls.Add($request); [pscustomobject]@{ StatusCode = 429; Body = '{"error":{"message":"quota exhausted"}}' } }
        $outputRoot = Join-Path $tempRepo 'build\ai-analysis'
        Assert-Throws { Invoke-AiAnalysisCommand -Task 'Summarize failure' -ChangedFiles -RepositoryRoot $tempRepo -OutputRoot $outputRoot -SecretReader $secretReader -GptTransport $failingTransport } 'quota'
        Assert-Equal 1 $calls.Count 'first failure stops without retry'
        Assert-False (Test-Path -LiteralPath $outputRoot) 'no partial report root'
    } finally {
        if (Test-Path -LiteralPath $tempRepo) { Remove-Item -LiteralPath $tempRepo -Recurse -Force }
    }
}

Invoke-AiAnalysisTest 'composition rejects external and junction report roots before retention cleanup' {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("lexiquest-ai-output-root-" + [guid]::NewGuid().ToString('N'))
    $repo = Join-Path $tempRoot 'repo'
    $outside = Join-Path $tempRoot 'outside-reports'
    $expired = Join-Path $outside '20000101T000000Z-abcdef12'
    $junction = Join-Path $repo 'build-link'
    [System.IO.Directory]::CreateDirectory((Join-Path $repo 'lib')) | Out-Null
    [System.IO.Directory]::CreateDirectory($expired) | Out-Null
    try {
        [System.IO.File]::WriteAllText((Join-Path $repo 'lib\sample.dart'), 'const value = 1;', (New-Object System.Text.UTF8Encoding($false)))
        & git -C $repo init --quiet
        & git -C $repo config user.email 'tests@example.invalid'
        & git -C $repo config user.name 'LexiQuest Tests'
        & git -C $repo add -- lib/sample.dart
        & git -C $repo commit --quiet -m baseline
        [System.IO.File]::WriteAllText((Join-Path $repo 'lib\sample.dart'), 'const value = 2;', (New-Object System.Text.UTF8Encoding($false)))
        $neverRead = { param($secretId) throw 'secretReaderShouldNotRun' }
        Assert-Throws { Invoke-AiAnalysisCommand -Task 'Summarize' -ChangedFiles -RepositoryRoot $repo -OutputRoot $outside -SecretReader $neverRead } 'unsafeReportPath'
        Assert-True (Test-Path -LiteralPath $expired -PathType Container) 'external retention target untouched'

        New-Item -ItemType Junction -Path $junction -Target $outside | Out-Null
        Assert-Throws { Invoke-AiAnalysisCommand -Task 'Summarize' -ChangedFiles -RepositoryRoot $repo -OutputRoot $junction -SecretReader $neverRead } 'reparsePoint'
        Assert-True (Test-Path -LiteralPath $expired -PathType Container) 'junction retention target untouched'
    } finally {
        if ([System.IO.Directory]::Exists($junction)) { [System.IO.Directory]::Delete($junction) }
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
}

Complete-AiAnalysisTests -Suite 'Orchestrator'

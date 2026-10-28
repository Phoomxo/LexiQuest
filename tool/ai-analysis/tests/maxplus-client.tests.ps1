Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-helpers.ps1')
. (Join-Path $PSScriptRoot '..\lib\config.ps1')
. (Join-Path $PSScriptRoot '..\lib\secret-store.ps1')
. (Join-Path $PSScriptRoot '..\lib\maxplus-client.ps1')

$config = Get-AiAnalysisConfig -ConfigPath (Join-Path $PSScriptRoot '..\config.json')
$fakeKey = ConvertTo-SecureString ('ccsk-' + ('a' * 64)) -AsPlainText -Force
$none = [Threading.CancellationToken]::None

Invoke-AiAnalysisTest 'loads the HTTP transport assembly on Windows PowerShell' {
    $httpHandlerType = 'System.Net.Http.HttpClientHandler' -as [type]
    Assert-True ($null -ne $httpHandlerType) 'System.Net.Http assembly loaded by the client module'
}

function New-TestResponse {
    param([int]$StatusCode = 200, [string]$Body = '{}')
    [pscustomobject]@{ StatusCode = $StatusCode; Body = $Body }
}

function New-GptSseBody {
    param([Parameter(Mandatory)][string]$ResponseJson)
    return "event: response.completed`ndata: {`"type`":`"response.completed`",`"response`":$ResponseJson}`n`n"
}

function Copy-TestRequest {
    param($Request)
    $headerCopy = @{}
    foreach ($name in @($Request.Headers.Keys)) { $headerCopy[$name] = $Request.Headers[$name] }
    [pscustomobject]@{
        Uri = $Request.Uri
        Method = $Request.Method
        Headers = $headerCopy
        Body = $Request.Body
        TimeoutSeconds = $Request.TimeoutSeconds
        CancellationToken = $Request.CancellationToken
    }
}

Invoke-AiAnalysisTest 'sends one GPT Responses request with storage disabled' {
    $requests = New-Object System.Collections.ArrayList
    $payload = @'
event: response.output_text.delta
data: {"type":"response.output_text.delta","delta":"ignored"}

event: response.completed
data: {"type":"response.completed","response":{"output":[{"type":"message","content":[{"type":"output_text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}]}],"usage":{"input_tokens":11,"output_tokens":7,"total_tokens":18,"cached_tokens":3,"cost":0.25}}}

'@
    $transport = {
        param($request)
        [void]$requests.Add((Copy-TestRequest $request))
        New-TestResponse -Body $payload
    }
    $result = Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort high -MaxOutputTokens 8192 -TimeoutSeconds 30 -Transport $transport
    Assert-Equal 1 $requests.Count 'one GPT request'
    Assert-Equal 'https://api.maxplus-ai.cc/gpt-pro-20x-stable/v1/responses' $requests[0].Uri.AbsoluteUri 'GPT route'
    Assert-Equal 'POST' $requests[0].Method 'GPT method'
    Assert-False $requests[0].Body.store 'Responses storage disabled'
    Assert-True $requests[0].Body.stream 'Responses streaming required by MaxPlus'
    Assert-Equal 'gpt-5.6-sol' $requests[0].Body.model 'GPT model'
    Assert-Equal 'high' $requests[0].Body.reasoning.effort 'GPT effort'
    Assert-Equal 8192 $requests[0].Body.max_output_tokens 'GPT output cap'
    Assert-Match '^Bearer ccsk-' $requests[0].Headers.Authorization 'GPT bearer auth'
    Assert-Equal 'ok' $result.Conclusion 'GPT conclusion'
    Assert-Equal 18 $result.Usage.TotalTokens 'GPT usage normalized'
    Assert-Equal 0.25 $result.Usage.ProviderReportedCost 'GPT cost normalized'
}

Invoke-AiAnalysisTest 'rejects GPT SSE without one completed response and never retries' {
    $calls = New-Object System.Collections.ArrayList
    $transport = {
        param($request)
        [void]$calls.Add($request)
        New-TestResponse -Body "event: response.output_text.done`ndata: {`"type`":`"response.output_text.done`",`"text`":`"partial`"}`n`n"
    }
    Assert-Throws {
        Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort low -MaxOutputTokens 2048 -TimeoutSeconds 30 -Transport $transport
    } 'malformedResponse'
    Assert-Equal 1 $calls.Count 'incomplete SSE not retried'
}

Invoke-AiAnalysisTest 'accepts only one successful completed GPT SSE terminal event' {
    $successJson = '{"output":[{"content":[{"type":"output_text","text":"{\"conclusion\":\"ok\",\"findings\":[]}"}]}]}'
    $completed = "event: response.completed`ndata: {`"type`":`"response.completed`",`"response`":$successJson}`n`n"
    $failed = "event: response.failed`ndata: {`"type`":`"response.failed`"}`n`n"
    $incomplete = "event: response.incomplete`ndata: {`"type`":`"response.incomplete`"}`n`n"
    $error = "event: error`ndata: {`"type`":`"error`"}`n`n"
    $cases = @(
        [pscustomobject]@{ Name='bare JSON success'; Body=$successJson; Category='malformedResponse' },
        [pscustomobject]@{ Name='duplicate completion'; Body=($completed + $completed); Category='malformedResponse' },
        [pscustomobject]@{ Name='completion missing response'; Body="event: response.completed`ndata: {`"type`":`"response.completed`"}`n`n"; Category='malformedResponse' },
        [pscustomobject]@{ Name='failed before completion'; Body=($failed + $completed); Category='unavailable' },
        [pscustomobject]@{ Name='failed after completion'; Body=($completed + $failed); Category='unavailable' },
        [pscustomobject]@{ Name='incomplete terminal'; Body=($completed + $incomplete); Category='malformedResponse' },
        [pscustomobject]@{ Name='error terminal'; Body=($completed + $error); Category='unavailable' }
    )
    foreach ($case in $cases) {
        $calls = New-Object System.Collections.ArrayList
        $responseBody = $case.Body
        $transport = { param($request) [void]$calls.Add($request); New-TestResponse -Body $responseBody }.GetNewClosure()
        $actualCategory = 'noError'
        try {
            $null = Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort low -MaxOutputTokens 2048 -TimeoutSeconds 30 -Transport $transport
        } catch {
            $actualCategory = $_.Exception.Message
        }
        Assert-Equal $case.Category $actualCategory "$($case.Name) category"
        Assert-Equal 1 $calls.Count "$($case.Name) not retried"
    }
}

Invoke-AiAnalysisTest 'sends one Claude Messages request with adaptive thinking' {
    $requests = New-Object System.Collections.ArrayList
    $payload = '{"content":[{"type":"text","text":"{\"conclusion\":\"reviewed\",\"findings\":[]}"}],"usage":{"input_tokens":13,"output_tokens":5,"cache_read_input_tokens":2}}'
    $provider = New-AiAnalysisClaudeProvider -ClaudeConfig $config.providers.claudeReviewer -Model 'claude-opus-5'
    $transport = {
        param($request)
        [void]$requests.Add((Copy-TestRequest $request))
        New-TestResponse -Body $payload
    }
    $result = Invoke-ClaudeReview -Provider $provider -SecureKey $fakeKey -Prompt 'fixed' -Effort xhigh -MaxOutputTokens 65536 -TimeoutSeconds 30 -Transport $transport
    Assert-Equal 1 $requests.Count 'one Claude request'
    Assert-Equal 'https://api.maxplus-ai.cc/aws-lite-ultimate/v1/messages' $requests[0].Uri.AbsoluteUri 'Claude route'
    Assert-Equal 'adaptive' $requests[0].Body.thinking.type 'adaptive thinking'
    Assert-Equal 'xhigh' $requests[0].Body.output_config.effort 'Claude effort'
    Assert-Equal 65536 $requests[0].Body.max_tokens 'Claude output cap'
    Assert-Match '^ccsk-' $requests[0].Headers.'x-api-key' 'Claude key header'
    Assert-Equal '2023-06-01' $requests[0].Headers.'anthropic-version' 'Anthropic version header'
    Assert-Equal 'reviewed' $result.Conclusion 'Claude conclusion'
    Assert-Equal 2 $result.Usage.CachedTokens 'Claude cached tokens normalized'
    Assert-Equal 'unknown' $result.Usage.ProviderReportedCost 'unknown cost preserved'
}

Invoke-AiAnalysisTest 'rejects unsafe hosts routes and malformed keys before transport' {
    $calls = New-Object System.Collections.ArrayList
    $transport = { param($request) [void]$calls.Add($request); New-TestResponse }
    $unsafeProvider = $config.providers.gptStable.PSObject.Copy()
    $unsafeProvider.baseUrl = 'https://example.invalid/gpt-pro-20x-stable'
    Assert-Throws { Invoke-MaxPlusRequest -Provider $unsafeProvider -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport } 'unsafeEndpoint'
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route 'https://example.invalid/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport } 'unsafeEndpoint'
    $badKey = ConvertTo-SecureString ('ccmk-' + ('b' * 64)) -AsPlainText -Force
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $badKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport } 'invalidInferenceKey'
    Assert-Equal 0 $calls.Count 'no transport call for rejected input'
}

Invoke-AiAnalysisTest 'validates account caps and exact model discovery' {
    $requests = New-Object System.Collections.ArrayList
    $transport = {
        param($request)
        [void]$requests.Add($request)
        if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) {
            return New-TestResponse -Body '{"user":{"email":"private@example.test","display_name":"Private"},"credit_usd":12.5,"key":{"id":"private","name":"GPT","key_preview":"ccsk-...","used_usd":3,"limit_usd":20,"limit_period":"daily","limit_used_usd":3,"active":true,"created_at":"2026-08-01T00:00:00Z"}}'
        }
        return New-TestResponse -Body '{"data":[{"id":"gpt-5.6-sol"},{"id":"other-model"}]}'
    }
    $gate = Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport
    Assert-Equal 2 $requests.Count 'one account and one model request'
    Assert-Equal 'https://api.maxplus-ai.cc/v1/me' $requests[0].Uri.AbsoluteUri 'global account endpoint'
    Assert-Equal 'https://api.maxplus-ai.cc/gpt-pro-20x-stable/v1/models' $requests[1].Uri.AbsoluteUri 'pool model endpoint'
    Assert-True $gate.Active 'active gate'
    Assert-True $gate.CreditPositive 'positive credit gate'
    Assert-Equal 'daily' $gate.CapKind 'daily cap selected'
    Assert-Equal 17 $gate.CapRemaining 'remaining cap'
    Assert-True $gate.ModelAvailable 'exact model discovered'
    Assert-Equal @('Active', 'CapKind', 'CapRemaining', 'CreditPositive', 'ModelAvailable') @($gate.PSObject.Properties.Name | Sort-Object) 'identity fields discarded'
}

Invoke-AiAnalysisTest 'validates both exact AWS Lite Ultimate reviewer models in one catalog call' {
    $requests = New-Object System.Collections.ArrayList
    $transport = {
        param($request)
        [void]$requests.Add($request)
        if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) {
            return New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":null,"limit_period":"daily","limit_used_usd":0}}'
        }
        New-TestResponse -Body '{"data":[{"id":"claude-sonnet-5"},{"id":"claude-opus-5"},{"id":"claude-haiku-4-5"}]}'
    }
    $gate = Test-MaxPlusCredential -Provider $config.providers.claudeReviewer -RequiredModels @('claude-sonnet-5', 'claude-opus-5') -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport
    Assert-Equal 2 $requests.Count 'one account and one model request'
    Assert-True $gate.ModelAvailable 'both required models discovered'
}

Invoke-AiAnalysisTest 'reports the missing approved reviewer model without fallback' {
    $cases = @(
        @{ Available='claude-opus-5'; Missing='claude-sonnet-5' },
        @{ Available='claude-sonnet-5'; Missing='claude-opus-5' }
    )
    foreach ($case in $cases) {
        $requests = New-Object System.Collections.ArrayList
        $modelBody = '{"data":[{"id":"' + $case.Available + '"}]}'
        $transport = {
            param($request)
            [void]$requests.Add($request)
            if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) {
                return New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":0}}'
            }
            New-TestResponse -Body $modelBody
        }
        Assert-Throws {
            Test-MaxPlusCredential -Provider $config.providers.claudeReviewer -RequiredModels @('claude-sonnet-5', 'claude-opus-5') -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport
        } "unsupportedModel:$($case.Missing)"
        Assert-Equal 2 $requests.Count "missing $($case.Missing) stops after one catalog call"
    }
}

Invoke-AiAnalysisTest 'accepts an official unlimited key before exact model discovery' {
    $calls = New-Object System.Collections.ArrayList
    $transport = {
        param($request)
        [void]$calls.Add($request)
        if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) {
            return New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":null,"limit_period":"daily","limit_used_usd":0}}'
        }
        New-TestResponse -Body '{"data":[{"id":"gpt-5.6-sol"}]}'
    }
    $gate = Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport
    Assert-Equal 2 $calls.Count 'unlimited key continues to model discovery'
    Assert-Equal 'unlimited' $gate.CapKind 'official null cap classified as unlimited'
    Assert-Equal $null $gate.CapRemaining 'unlimited key has no finite remaining cap'
    Assert-True $gate.ModelAvailable 'exact configured model discovered'
}

Invoke-AiAnalysisTest 'classifies malformed account fields as malformed response' {
    $accountBodies = @(
        '{"credit_usd":5}',
        '{"credit_usd":5,"key":{"active":"true","limit_usd":10,"limit_period":"daily","limit_used_usd":1}}',
        '{"credit_usd":"not-a-number","key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":"not-a-number","limit_period":"daily","limit_used_usd":1}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"weekly","limit_used_usd":1}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":"not-a-number"}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":-1,"limit_period":"daily","limit_used_usd":-2}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":1000001,"limit_period":"daily","limit_used_usd":0}}',
        '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":-1}}'
    )
    foreach ($accountBody in $accountBodies) {
        $calls = New-Object System.Collections.ArrayList
        $transport = { param($request) [void]$calls.Add($request); New-TestResponse -Body $accountBody }
        Assert-Throws { Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport } 'malformedResponse'
        Assert-Equal 1 $calls.Count 'malformed account stops before model discovery'
    }
}

Invoke-AiAnalysisTest 'classifies a missing models array as malformed response' {
    $transport = {
        param($request)
        if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"daily","limit_used_usd":1}}' }
        New-TestResponse -Body '{}'
    }
    Assert-Throws { Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport } 'malformedResponse'
}

Invoke-AiAnalysisTest 'reports unsupported configured model without substitution' {
    $calls = New-Object System.Collections.ArrayList
    $transport = {
        param($request)
        [void]$calls.Add($request)
        if ($request.Uri.AbsolutePath.EndsWith('/v1/me')) { return New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"lifetime","limit_used_usd":1}}' }
        New-TestResponse -Body '{"data":[{"id":"different-model"}]}'
    }
    Assert-Throws { Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport } 'unsupportedModel'
    Assert-Equal 2 $calls.Count 'no model fallback call'
}

Invoke-AiAnalysisTest 'rejects an exhausted official account cap' {
    $transport = {
        param($request)
        New-TestResponse -Body '{"credit_usd":5,"key":{"active":true,"limit_usd":10,"limit_period":"lifetime","limit_used_usd":10}}'
    }
    Assert-Throws { Test-MaxPlusCredential -Provider $config.providers.gptStable -SecureKey $fakeKey -TimeoutSeconds 30 -Transport $transport } 'quota'
}

Invoke-AiAnalysisTest 'maps provider errors and never retries' {
    $cases = @(
        @{ Status = 400; Body = '{"error":{"message":"unsupported effort xhigh"}}'; Category = 'unsupportedEffort' },
        @{ Status = 400; Body = '{"error":{"message":"unknown model"}}'; Category = 'unsupportedModel' },
        @{ Status = 401; Body = '{}'; Category = 'invalidKey' },
        @{ Status = 402; Body = '{"error":{"type":"insufficient_credit"}}'; Category = 'quota' },
        @{ Status = 403; Body = '{}'; Category = 'invalidKey' },
        @{ Status = 408; Body = '{}'; Category = 'timeout' },
        @{ Status = 409; Body = '{"error":{"message":"pool shape mismatch"}}'; Category = 'poolMismatch' },
        @{ Status = 429; Body = '{"error":{"message":"quota exhausted"}}'; Category = 'quota' },
        @{ Status = 429; Body = '{"error":{"message":"too many requests"}}'; Category = 'rateLimit' },
        @{ Status = 503; Body = '{}'; Category = 'unavailable' },
        @{ Status = 504; Body = '{}'; Category = 'timeout' }
    )
    foreach ($case in $cases) {
        $calls = New-Object System.Collections.ArrayList
        $transport = { param($request) [void]$calls.Add($request); New-TestResponse -StatusCode $case.Status -Body $case.Body }
        Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport } $case.Category
        Assert-Equal 1 $calls.Count "$($case.Category) one attempt"
    }
}

Invoke-AiAnalysisTest 'blocks redirects without following another host' {
    $calls = New-Object System.Collections.ArrayList
    $transport = { param($request) [void]$calls.Add($request); New-TestResponse -StatusCode 302 -Body '{}' }
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport } 'unsafeRedirect'
    Assert-Equal 1 $calls.Count 'redirect response not retried'
    $clientSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maxplus-client.ps1') -Raw -Encoding utf8
    Assert-Match 'AllowAutoRedirect\s*=\s*\$false' $clientSource 'default HTTP transport disables redirects'
}

Invoke-AiAnalysisTest 'uses the linked cancellation source as the only timeout authority' {
    $clientSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maxplus-client.ps1') -Raw -Encoding utf8
    Assert-Match '\$client\.Timeout\s*=\s*\[Threading\.Timeout\]::InfiniteTimeSpan' $clientSource 'HttpClient default timeout disabled'
    Assert-Match '\$linkedSource\.CancelAfter\(' $clientSource 'bounded linked timeout configured'
}

Invoke-AiAnalysisTest 'maps timeout cancellation and malformed response distinctly' {
    $timeoutCalls = New-Object System.Collections.ArrayList
    $timeoutTransport = { param($request) [void]$timeoutCalls.Add($request); throw [TimeoutException]::new('bounded timeout') }
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 5 -CancellationToken $none -Transport $timeoutTransport } 'timeout'
    Assert-Equal 1 $timeoutCalls.Count 'timeout not retried'

    $cancelCalls = New-Object System.Collections.ArrayList
    $cancelTransport = { param($request) [void]$cancelCalls.Add($request); New-TestResponse }
    $source = New-Object Threading.CancellationTokenSource
    $source.Cancel()
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 5 -CancellationToken $source.Token -Transport $cancelTransport } 'cancelled'
    Assert-Equal 0 $cancelCalls.Count 'pre-cancelled request not sent'
    $source.Dispose()

    $malformedCalls = New-Object System.Collections.ArrayList
    $malformedTransport = { param($request) [void]$malformedCalls.Add($request); New-TestResponse -Body 'not-json' }
    Assert-Throws { Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 5 -CancellationToken $none -Transport $malformedTransport } 'malformedResponse'
    Assert-Equal 1 $malformedCalls.Count 'malformed response not retried'
}

Invoke-AiAnalysisTest 'clears live authorization and account envelope references' {
    $script:CapturedLiveRequest = $null
    $transport = {
        param($request)
        $script:CapturedLiveRequest = $request
        New-TestResponse -Body '{}'
    }
    $null = Invoke-MaxPlusRequest -Provider $config.providers.gptStable -Route '/v1/me' -Method GET -SecureKey $fakeKey -Body $null -TimeoutSeconds 30 -CancellationToken $none -Transport $transport
    Assert-Equal 0 $script:CapturedLiveRequest.Headers.Count 'authorization headers cleared after transport'

    $clientSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\lib\maxplus-client.ps1') -Raw -Encoding utf8
    Assert-Match '\$request\s*=\s*\$null' $clientSource 'request reference cleared'
    $clearIndex = $clientSource.IndexOf('$account = $null', [StringComparison]::Ordinal)
    $modelsIndex = $clientSource.IndexOf('$models = Invoke-MaxPlusRequest', [StringComparison]::Ordinal)
    Assert-True ($clearIndex -ge 0 -and $clearIndex -lt $modelsIndex) 'account envelope cleared before model discovery'
}

Invoke-AiAnalysisTest 'rejects unstructured generation output' {
    $payload = New-GptSseBody -ResponseJson '{"output":[{"content":[{"type":"output_text","text":"free text"}]}]}'
    $transport = { param($request) New-TestResponse -Body $payload }.GetNewClosure()
    Assert-Throws { Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort low -MaxOutputTokens 2048 -TimeoutSeconds 30 -Transport $transport } 'malformedResponse'
}

Invoke-AiAnalysisTest 'rejects tool calls before structured result projection' {
    $payload = New-GptSseBody -ResponseJson '{"output":[{"content":[{"type":"output_text","text":"{\"conclusion\":\"ok\",\"findings\":[],\"tool_calls\":[{\"name\":\"shell\"}]}"}]}]}'
    $transport = {
        param($request)
        New-TestResponse -Body $payload
    }.GetNewClosure()
    Assert-Throws { Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort low -MaxOutputTokens 2048 -TimeoutSeconds 30 -Transport $transport } 'unsafeModelOutput'
}

Invoke-AiAnalysisTest 'rejects null empty and invalid finding fields' {
    $cases = @(
        [pscustomobject]@{ id = $null; severity = 'high'; category = 'correctness'; message = 'message'; file = 'lib/a.dart'; line = 1; evidence = 'evidence' },
        [pscustomobject]@{ id = 'P1'; severity = 'urgent'; category = 'correctness'; message = 'message'; file = 'lib/a.dart'; line = 1; evidence = 'evidence' },
        [pscustomobject]@{ id = 'P1'; severity = 'high'; category = ''; message = 'message'; file = 'lib/a.dart'; line = 1; evidence = 'evidence' },
        [pscustomobject]@{ id = 'P1'; severity = 'high'; category = 'correctness'; message = ''; file = 'lib/a.dart'; line = 1; evidence = 'evidence' },
        [pscustomobject]@{ id = 'P1'; severity = 'high'; category = 'correctness'; message = 'message'; file = 'lib/a.dart'; line = 0; evidence = 'evidence' }
    )
    foreach ($finding in $cases) {
        $structured = [pscustomobject]@{ conclusion = 'checked'; findings = @($finding) } | ConvertTo-Json -Depth 10 -Compress
        $envelope = [pscustomobject]@{ output = @([pscustomobject]@{ content = @([pscustomobject]@{ type = 'output_text'; text = $structured }) }) } | ConvertTo-Json -Depth 10 -Compress
        $payload = New-GptSseBody -ResponseJson $envelope
        $transport = { param($request) New-TestResponse -Body $payload }.GetNewClosure()
        Assert-Throws { Invoke-GptAnalysis -Provider $config.providers.gptStable -SecureKey $fakeKey -Prompt 'fixed' -Effort low -MaxOutputTokens 2048 -TimeoutSeconds 30 -Transport $transport } 'malformedResponse'
    }
}

Invoke-AiAnalysisTest 'initialization accepts no key argument and validates before saving' {
    $path = Join-Path $PSScriptRoot '..\initialize-secrets.ps1'
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) 'initializer exists'
    $command = Get-Command -Name $path
    Assert-False ($command.Parameters.ContainsKey('Key')) 'no plaintext key parameter'
    Assert-False ($command.Parameters.ContainsKey('ApiKey')) 'no API key parameter'
    $source = Get-Content -LiteralPath $path -Raw -Encoding utf8
    Assert-Match 'Read-Host\s+-AsSecureString' $source 'secure interactive prompt'
    Assert-Match 'models\.routine' $source 'initializer requires routine model'
    Assert-Match 'models\.deep' $source 'initializer requires deep model'
    Assert-Match 'Test-MaxPlusCredential[^\r\n]+-RequiredModels' $source 'initializer passes exact required models before save'
    Assert-True ($source.IndexOf('Test-MaxPlusCredential', [StringComparison]::Ordinal) -lt $source.IndexOf('Save-AiAnalysisSecret', [StringComparison]::Ordinal)) 'validate before write order'
}

Complete-AiAnalysisTests -Suite 'MaxPlus client'

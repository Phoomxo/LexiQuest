Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Net.Http -ErrorAction Stop

function Get-AiAnalysisObjectProperty {
    param($Object, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function ConvertFrom-AiAnalysisJson {
    param($Value)
    if ($Value -isnot [string]) { return $Value }
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'malformedResponse' }
    try { return $Value | ConvertFrom-Json } catch { throw 'malformedResponse' }
}

function ConvertFrom-AiAnalysisSseResponse {
    param([Parameter(Mandatory)][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'malformedResponse' }

    $completedResponse = $null
    $completedCount = 0
    $completedSeen = $false
    foreach ($block in [Text.RegularExpressions.Regex]::Split($Value, '\r?\n\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($block)) { continue }
        $eventName = $null
        $dataLines = New-Object System.Collections.ArrayList
        foreach ($line in [Text.RegularExpressions.Regex]::Split($block, '\r?\n')) {
            if ($line.StartsWith(':')) { continue }
            if ($line.StartsWith('event:')) {
                if ($null -ne $eventName) { throw 'malformedResponse' }
                $eventName = $line.Substring(6).Trim()
            } elseif ($line.StartsWith('data:')) {
                $data = $line.Substring(5)
                if ($data.StartsWith(' ')) { $data = $data.Substring(1) }
                [void]$dataLines.Add($data)
            } elseif (-not [string]::IsNullOrWhiteSpace($line) -and
                -not $line.StartsWith('id:') -and -not $line.StartsWith('retry:')) {
                throw 'malformedResponse'
            }
        }
        if ($null -eq $eventName) {
            if ($dataLines.Count -gt 0) { throw 'malformedResponse' }
            continue
        }
        if ($eventName -cin @('response.failed', 'response.cancelled', 'error')) { throw 'unavailable' }
        if ($eventName -ceq 'response.incomplete') { throw 'malformedResponse' }
        if ($completedSeen) { throw 'malformedResponse' }
        if ($eventName -cne 'response.completed') { continue }
        if ($completedCount -gt 0) { throw 'malformedResponse' }
        if ($dataLines.Count -eq 0) { throw 'malformedResponse' }
        $eventEnvelope = ConvertFrom-AiAnalysisJson -Value ([string]::Join("`n", @($dataLines)))
        if ([string](Get-AiAnalysisObjectProperty -Object $eventEnvelope -Name 'type') -cne 'response.completed') {
            throw 'malformedResponse'
        }
        $response = Get-AiAnalysisObjectProperty -Object $eventEnvelope -Name 'response'
        if ($null -eq $response -or $response -is [string] -or $response -is [ValueType] -or
            $response -is [System.Array]) { throw 'malformedResponse' }
        $completedCount++
        $completedSeen = $true
        $completedResponse = $response
    }
    if ($completedCount -ne 1) { throw 'malformedResponse' }
    return $completedResponse
}

function ConvertTo-AiAnalysisDecimal {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [string]) { throw 'malformedResponse' }
    try { return [decimal]$Value } catch { throw 'malformedResponse' }
}

function Test-AiAnalysisForbiddenProviderOutput {
    param($Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if ([string]$key -match '^(?i:tool_calls?|function_calls?|shell_command|patch)$') { return $true }
            if (Test-AiAnalysisForbiddenProviderOutput $Value[$key]) { return $true }
        }
        return $false
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { if (Test-AiAnalysisForbiddenProviderOutput $item) { return $true } }
        return $false
    }
    foreach ($property in @($Value.PSObject.Properties)) {
        if ($property.Name -match '^(?i:tool_calls?|function_calls?|shell_command|patch)$') { return $true }
        if ($property.Name -ceq 'type' -and [string]$property.Value -match '^(?i:function_call|computer_call|shell_call|tool_call)$') { return $true }
        if (Test-AiAnalysisForbiddenProviderOutput $property.Value) { return $true }
    }
    return $false
}

function Invoke-AiAnalysisDefaultTransport {
    param([Parameter(Mandatory)]$Request)

    $handler = $null
    $client = $null
    $message = $null
    $content = $null
    $response = $null
    $linkedSource = $null
    try {
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $false
        $client = New-Object System.Net.Http.HttpClient($handler, $true)
        $client.Timeout = [Threading.Timeout]::InfiniteTimeSpan
        $message = New-Object System.Net.Http.HttpRequestMessage(
            (New-Object System.Net.Http.HttpMethod($Request.Method)),
            $Request.Uri
        )
        foreach ($headerName in @($Request.Headers.Keys)) {
            [void]$message.Headers.TryAddWithoutValidation($headerName, [string]$Request.Headers[$headerName])
        }
        if ($null -ne $Request.Body) {
            $json = $Request.Body | ConvertTo-Json -Depth 30 -Compress
            $content = New-Object System.Net.Http.StringContent($json, [System.Text.Encoding]::UTF8, 'application/json')
            $message.Content = $content
        }

        $linkedSource = [Threading.CancellationTokenSource]::CreateLinkedTokenSource($Request.CancellationToken)
        $linkedSource.CancelAfter([TimeSpan]::FromSeconds($Request.TimeoutSeconds))
        try {
            $response = $client.SendAsync($message, [System.Net.Http.HttpCompletionOption]::ResponseContentRead, $linkedSource.Token).GetAwaiter().GetResult()
        } catch [OperationCanceledException] {
            if ($Request.CancellationToken.IsCancellationRequested) { throw }
            throw [TimeoutException]::new('request timeout')
        }
        $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return [pscustomobject]@{
            StatusCode = [int]$response.StatusCode
            Body = $responseBody
        }
    } finally {
        $json = $null
        $responseBody = $null
        if ($response) { $response.Dispose() }
        if ($content) { $content.Dispose() }
        if ($message) { $message.Dispose() }
        if ($linkedSource) { $linkedSource.Dispose() }
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
}

function Invoke-MaxPlusRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][string]$Route,
        [Parameter(Mandatory)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory)][Security.SecureString]$SecureKey,
        $Body,
        [Parameter(Mandatory)][ValidateRange(5, 600)][int]$TimeoutSeconds,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None,
        [scriptblock]$Transport
    )

    if ($CancellationToken.IsCancellationRequested) { throw 'cancelled' }
    if (-not (Test-AiAnalysisInferenceKey -SecureKey $SecureKey)) { throw 'invalidInferenceKey' }

    try {
        $baseUri = [Uri]$Provider.baseUrl
        $accountBaseUri = [Uri]$Provider.accountBaseUrl
    } catch { throw 'unsafeEndpoint' }
    foreach ($approvedBaseUri in @($baseUri, $accountBaseUri)) {
        if ($approvedBaseUri.Scheme -cne 'https' -or $approvedBaseUri.Host -cne 'api.maxplus-ai.cc' -or
            -not [string]::IsNullOrEmpty($approvedBaseUri.Query) -or -not [string]::IsNullOrEmpty($approvedBaseUri.Fragment) -or
            -not [string]::IsNullOrEmpty($approvedBaseUri.UserInfo)) { throw 'unsafeEndpoint' }
    }
    if ($Provider.baseUrl -cnotin @(
        'https://api.maxplus-ai.cc/gpt-pro-20x-stable',
        'https://api.maxplus-ai.cc/aws-lite-ultimate'
    )) { throw 'unsafeEndpoint' }
    if ($Provider.accountBaseUrl -cne 'https://api.maxplus-ai.cc') { throw 'unsafeEndpoint' }
    if ($Route -cnotin @([string]$Provider.accountRoute, [string]$Provider.modelsRoute, [string]$Provider.generationRoute)) {
        throw 'unsafeEndpoint'
    }

    $requestBaseUrl = if ($Route -ceq [string]$Provider.accountRoute) {
        [string]$Provider.accountBaseUrl
    } else {
        [string]$Provider.baseUrl
    }
    $requestUri = [Uri]($requestBaseUrl.TrimEnd('/') + $Route)
    if ($requestUri.Scheme -cne 'https' -or $requestUri.Host -cne 'api.maxplus-ai.cc') { throw 'unsafeEndpoint' }
    if ($null -eq $Transport) { $Transport = ${function:Invoke-AiAnalysisDefaultTransport} }

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureKey)
    $keyText = $null
    $headers = @{}
    $request = $null
    try {
        $keyText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ($Provider.authStyle -ceq 'bearer') {
            $headers.Authorization = "Bearer $keyText"
        } elseif ($Provider.authStyle -ceq 'anthropic') {
            $headers.'x-api-key' = $keyText
            $headers.'anthropic-version' = [string]$Provider.anthropicVersion
        } else {
            throw 'invalidConfig'
        }

        $request = [pscustomobject]@{
            Uri = $requestUri
            Method = $Method
            Headers = $headers
            Body = $Body
            TimeoutSeconds = $TimeoutSeconds
            CancellationToken = $CancellationToken
        }
        try {
            $response = & $Transport $request
        } catch [TimeoutException] {
            throw 'timeout'
        } catch [OperationCanceledException] {
            if ($CancellationToken.IsCancellationRequested) { throw 'cancelled' }
            throw 'timeout'
        } catch {
            if ($_.Exception.Message -in @('cancelled', 'timeout')) { throw }
            throw 'unavailable'
        }
    } finally {
        if ($null -ne $headers) {
            foreach ($headerName in @($headers.Keys)) { $headers[$headerName] = $null }
            $headers.Clear()
        }
        $request = $null
        $headers = $null
        $keyText = $null
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }

    if ($null -eq $response -or $null -eq $response.PSObject.Properties['StatusCode'] -or
        $null -eq $response.PSObject.Properties['Body']) { throw 'malformedResponse' }
    $status = [int]$response.StatusCode
    $responseText = [string]$response.Body
    if ($status -lt 200 -or $status -ge 300) {
        if ($status -ge 300 -and $status -lt 400) { throw 'unsafeRedirect' }
        $lower = $responseText.ToLowerInvariant()
        switch ($status) {
            { $_ -eq 400 } {
                if ($lower -match 'effort|reasoning') { throw 'unsupportedEffort' }
                if ($lower -match 'model') { throw 'unsupportedModel' }
                throw 'malformedResponse'
            }
            { $_ -eq 401 -or $_ -eq 403 } { throw 'invalidKey' }
            402 { throw 'quota' }
            { $_ -eq 408 -or $_ -eq 504 } { throw 'timeout' }
            409 { throw 'poolMismatch' }
            429 {
                if ($lower -match 'quota|credit|spend|cap|limit exhausted') { throw 'quota' }
                throw 'rateLimit'
            }
            { $_ -ge 500 } { throw 'unavailable' }
            default { throw 'unavailable' }
        }
    }

    if ($Route -ceq '/v1/responses') {
        return ConvertFrom-AiAnalysisSseResponse -Value $responseText
    }
    return ConvertFrom-AiAnalysisJson -Value $responseText
}

function Test-MaxPlusCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][Security.SecureString]$SecureKey,
        [Parameter(Mandatory)][ValidateRange(5, 600)][int]$TimeoutSeconds,
        [string[]]$RequiredModels = @(),
        [scriptblock]$Transport
    )

    $account = Invoke-MaxPlusRequest -Provider $Provider -Route $Provider.accountRoute -Method GET -SecureKey $SecureKey -Body $null -TimeoutSeconds $TimeoutSeconds -Transport $Transport
    $credit = Get-AiAnalysisObjectProperty -Object $account -Name 'credit_usd'
    $accountKey = Get-AiAnalysisObjectProperty -Object $account -Name 'key'
    if ($null -eq $accountKey -or $accountKey -is [string] -or $accountKey -is [ValueType] -or
        $accountKey -is [System.Array]) { throw 'malformedResponse' }
    $active = Get-AiAnalysisObjectProperty -Object $accountKey -Name 'active'
    if ($active -isnot [bool]) { throw 'malformedResponse' }
    if (-not $active) { throw 'inactiveKey' }
    $creditValue = ConvertTo-AiAnalysisDecimal -Value $credit
    if ($creditValue -le 0) { throw 'quota' }

    $limitProperty = $accountKey.PSObject.Properties['limit_usd']
    $usedProperty = $accountKey.PSObject.Properties['limit_used_usd']
    $periodProperty = $accountKey.PSObject.Properties['limit_period']
    if ($null -eq $limitProperty -or $null -eq $usedProperty -or $null -eq $periodProperty) { throw 'malformedResponse' }
    $capKind = $periodProperty.Value
    if ($capKind -isnot [string] -or $capKind -cnotin @('daily', 'lifetime')) { throw 'malformedResponse' }
    $usedValue = ConvertTo-AiAnalysisDecimal -Value $usedProperty.Value
    if ($usedValue -lt 0) { throw 'malformedResponse' }
    if ($null -eq $limitProperty.Value) {
        $capKind = 'unlimited'
        $capRemaining = $null
    } else {
        $limitValue = ConvertTo-AiAnalysisDecimal -Value $limitProperty.Value
        if ($limitValue -lt 0 -or $limitValue -gt 1000000) { throw 'malformedResponse' }
        $capRemaining = $limitValue - $usedValue
        if ($capRemaining -le 0) { throw 'quota' }
    }
    $accountKey = $null
    $account = $null

    if (@($RequiredModels).Count -eq 0) {
        $providerModel = Get-AiAnalysisObjectProperty -Object $Provider -Name 'model'
        if ($providerModel -isnot [string] -or [string]::IsNullOrWhiteSpace($providerModel)) { throw 'malformedResponse' }
        $RequiredModels = @($providerModel)
    }
    $requiredModelSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($requiredModel in @($RequiredModels)) {
        if ($requiredModel -isnot [string] -or [string]::IsNullOrWhiteSpace($requiredModel) -or
            -not $requiredModelSet.Add($requiredModel)) { throw 'malformedResponse' }
    }

    $models = Invoke-MaxPlusRequest -Provider $Provider -Route $Provider.modelsRoute -Method GET -SecureKey $SecureKey -Body $null -TimeoutSeconds $TimeoutSeconds -Transport $Transport
    $modelDataProperty = $models.PSObject.Properties['data']
    if ($null -eq $modelDataProperty -or $modelDataProperty.Value -isnot [System.Array]) { throw 'malformedResponse' }
    $modelData = @($modelDataProperty.Value)
    $availableModels = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($model in $modelData) {
        $modelId = Get-AiAnalysisObjectProperty -Object $model -Name 'id'
        if ($modelId -isnot [string] -or [string]::IsNullOrWhiteSpace($modelId)) { throw 'malformedResponse' }
        [void]$availableModels.Add($modelId)
    }
    foreach ($requiredModel in @($RequiredModels)) {
        if (-not $availableModels.Contains($requiredModel)) { throw "unsupportedModel:$requiredModel" }
    }
    $models = $null
    $modelData = $null
    $availableModels = $null
    $requiredModelSet = $null
    $RequiredModels = $null

    [pscustomobject]@{
        Active = $true
        CreditPositive = $true
        CapKind = $capKind
        CapRemaining = $capRemaining
        ModelAvailable = $true
    }
}

function ConvertTo-AiAnalysisStructuredResult {
    param(
        [Parameter(Mandatory)]$Envelope,
        [Parameter(Mandatory)][ValidateSet('gpt', 'claude')][string]$ProviderKind,
        [Parameter(Mandatory)][string]$ProviderName,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$Effort,
        [Parameter(Mandatory)][long]$LatencyMs
    )

    if (Test-AiAnalysisForbiddenProviderOutput $Envelope) { throw 'unsafeModelOutput' }
    if ($ProviderKind -eq 'gpt') {
        $text = $null
        foreach ($output in @(Get-AiAnalysisObjectProperty -Object $Envelope -Name 'output')) {
            foreach ($item in @(Get-AiAnalysisObjectProperty -Object $output -Name 'content')) {
                if ([string](Get-AiAnalysisObjectProperty -Object $item -Name 'type') -eq 'output_text') {
                    $text = [string](Get-AiAnalysisObjectProperty -Object $item -Name 'text')
                    break
                }
            }
            if ($null -ne $text) { break }
        }
    } else {
        $text = $null
        foreach ($item in @(Get-AiAnalysisObjectProperty -Object $Envelope -Name 'content')) {
            if ([string](Get-AiAnalysisObjectProperty -Object $item -Name 'type') -eq 'text') {
                $text = [string](Get-AiAnalysisObjectProperty -Object $item -Name 'text')
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($text)) { throw 'malformedResponse' }
    $structured = ConvertFrom-AiAnalysisJson -Value $text
    if (Test-AiAnalysisForbiddenProviderOutput $structured) { throw 'unsafeModelOutput' }
    foreach ($property in @($structured.PSObject.Properties)) {
        if ($property.Name -cnotin @('conclusion', 'findings', 'agreement')) { throw 'malformedResponse' }
    }
    $conclusion = Get-AiAnalysisObjectProperty -Object $structured -Name 'conclusion'
    $findingsProperty = $structured.PSObject.Properties['findings']
    if ($conclusion -isnot [string] -or [string]::IsNullOrWhiteSpace($conclusion) -or
        $null -eq $findingsProperty -or $findingsProperty.Value -isnot [System.Array]) { throw 'malformedResponse' }
    $findings = @($findingsProperty.Value)
    foreach ($finding in $findings) {
        foreach ($required in @('id', 'severity', 'category', 'message', 'file', 'line', 'evidence')) {
            if ($null -eq $finding.PSObject.Properties[$required]) { throw 'malformedResponse' }
        }
        foreach ($requiredString in @('id', 'severity', 'category', 'message', 'file', 'evidence')) {
            $value = $finding.PSObject.Properties[$requiredString].Value
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) { throw 'malformedResponse' }
        }
        if (([string]$finding.severity).ToLowerInvariant() -cnotin @('critical', 'high', 'medium', 'low', 'info')) {
            throw 'malformedResponse'
        }
        $line = 0
        if (-not [int]::TryParse([string]$finding.line, [ref]$line) -or $line -le 0) { throw 'malformedResponse' }
    }
    $agreement = Get-AiAnalysisObjectProperty -Object $structured -Name 'agreement'
    if ($null -ne $agreement -and ($agreement -isnot [string] -or $agreement -cnotin @('agree', 'disagree'))) {
        throw 'malformedResponse'
    }

    $usageEnvelope = Get-AiAnalysisObjectProperty -Object $Envelope -Name 'usage'
    $inputTokens = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'input_tokens'
    $outputTokens = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'output_tokens'
    $totalTokens = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'total_tokens'
    $cachedTokens = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'cached_tokens'
    if ($null -eq $cachedTokens) { $cachedTokens = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'cache_read_input_tokens' }
    $cost = Get-AiAnalysisObjectProperty -Object $usageEnvelope -Name 'cost'
    if ($null -eq $cost) { $cost = Get-AiAnalysisObjectProperty -Object $Envelope -Name 'cost' }
    if ($null -eq $cost) { $cost = 'unknown' }

    $result = [ordered]@{
        Conclusion = [string]$conclusion
        Findings = $findings
        Usage = [pscustomobject]@{
            InputTokens = $inputTokens
            OutputTokens = $outputTokens
            TotalTokens = $totalTokens
            CachedTokens = $cachedTokens
            ProviderReportedCost = $cost
        }
        Provider = $ProviderName
        Model = $Model
        Effort = $Effort
        LatencyMs = $LatencyMs
    }
    if ($null -ne $agreement) { $result.Agreement = [string]$agreement }
    return [pscustomobject]$result
}

function Invoke-GptAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][Security.SecureString]$SecureKey,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Effort,
        [Parameter(Mandatory)][int]$MaxOutputTokens,
        [Parameter(Mandatory)][ValidateRange(5, 600)][int]$TimeoutSeconds,
        [scriptblock]$Transport
    )

    if ($Effort -cnotin @($Provider.efforts)) { throw 'unsupportedEffort' }
    $body = [pscustomobject]@{
        model = [string]$Provider.model
        input = @([pscustomobject]@{ role = 'user'; content = @([pscustomobject]@{ type = 'input_text'; text = $Prompt }) })
        stream = $true
        store = $false
        reasoning = [pscustomobject]@{ effort = $Effort }
        max_output_tokens = $MaxOutputTokens
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $envelope = Invoke-MaxPlusRequest -Provider $Provider -Route $Provider.generationRoute -Method POST -SecureKey $SecureKey -Body $body -TimeoutSeconds $TimeoutSeconds -Transport $Transport
    } finally {
        $watch.Stop()
    }
    return ConvertTo-AiAnalysisStructuredResult -Envelope $envelope -ProviderKind gpt -ProviderName $Provider.pool -Model $Provider.model -Effort $Effort -LatencyMs $watch.ElapsedMilliseconds
}

function Invoke-ClaudeReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][Security.SecureString]$SecureKey,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$Effort,
        [Parameter(Mandatory)][int]$MaxOutputTokens,
        [Parameter(Mandatory)][ValidateRange(5, 600)][int]$TimeoutSeconds,
        [scriptblock]$Transport
    )

    if ($Effort -cnotin @($Provider.efforts)) { throw 'unsupportedEffort' }
    $body = [pscustomobject]@{
        model = [string]$Provider.model
        messages = @([pscustomobject]@{ role = 'user'; content = $Prompt })
        thinking = [pscustomobject]@{ type = 'adaptive' }
        output_config = [pscustomobject]@{ effort = $Effort }
        max_tokens = $MaxOutputTokens
    }
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $envelope = Invoke-MaxPlusRequest -Provider $Provider -Route $Provider.generationRoute -Method POST -SecureKey $SecureKey -Body $body -TimeoutSeconds $TimeoutSeconds -Transport $Transport
    } finally {
        $watch.Stop()
    }
    return ConvertTo-AiAnalysisStructuredResult -Envelope $envelope -ProviderKind claude -ProviderName $Provider.pool -Model $Provider.model -Effort $Effort -LatencyMs $watch.ElapsedMilliseconds
}

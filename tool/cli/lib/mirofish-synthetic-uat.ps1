#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Get-LexiQuestObjectProperty {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-LexiQuestSyntheticText {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    $patterns = [ordered]@{
        'email address' = '(?i)(?<![\w.+-])[\w.+-]+@[\w.-]+\.[a-z]{2,}(?![\w.-])'
        'phone number' = '(?<!\d)0\d{1,2}[- ]?\d{3}[- ]?\d{4}(?!\d)'
        'Thai national ID-shaped value' = '(?<!\d)\d{13}(?!\d)'
        'bearer token' = '(?i)authorization\s*:\s*bearer\s+\S+'
        'API key or access token' = '(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*\S+'
        'private key material' = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
        'device serial' = '(?i)device[_-]?serial\s*[:=]\s*\S+'
        'raw API credential' = '(?i)(?<![A-Za-z0-9])(?:cc)?sk-[A-Za-z0-9_-]{20,}'
        'Google API key' = '(?<![A-Za-z0-9])AIza[A-Za-z0-9_-]{20,}'
        'JSON web token' = '(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}(?![A-Za-z0-9_-])'
    }

    foreach ($entry in $patterns.GetEnumerator()) {
        if ($Text -match $entry.Value) {
            Write-Output ("Synthetic-only input contains {0}." -f $entry.Key)
        }
    }
}
function Test-LexiQuestAllowedProperties {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [Parameter(Mandatory)]
        [string]$Context
    )

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.Name -notin $Allowed) {
            Write-Output (
                "{0} contains unsupported property: {1}." -f `
                    $Context, $property.Name
            )
        }
    }
}
function ConvertFrom-LexiQuestJsonTree {
    param(
        [Parameter(Mandatory)]
        [string]$Json
    )

    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 1MB
    return ,$serializer.DeserializeObject($Json)
}

function Test-LexiQuestMiroFishManifestTypes {
    param(
        [Parameter(Mandatory)]
        [object]$Manifest
    )

    if ($Manifest -isnot [System.Collections.IDictionary]) {
        Write-Output 'Manifest root must be a JSON object.'
        return
    }
    if ($Manifest['schemaVersion'] -isnot [int]) {
        Write-Output 'Manifest schemaVersion must be a JSON integer.'
    }
    if ($Manifest['generatedAtUtc'] -isnot [string]) {
        Write-Output 'Manifest generatedAtUtc must be a JSON string.'
    }
    if ($Manifest['advisoryOnly'] -isnot [bool]) {
        Write-Output 'Manifest advisoryOnly must be a JSON boolean.'
    }
    if ($Manifest['dataClassification'] -isnot [string] -or
        $Manifest['sourceCommit'] -isnot [string]) {
        Write-Output 'Manifest classification and sourceCommit must be strings.'
    }

    $engine = $Manifest['engine']
    if ($engine -isnot [System.Collections.IDictionary] -or
        $engine['name'] -isnot [string] -or
        $engine['version'] -isnot [string] -or
        $engine['commit'] -isnot [string]) {
        Write-Output 'Manifest engine must contain string metadata.'
    }
    $scenario = $Manifest['scenario']
    if ($scenario -isnot [System.Collections.IDictionary] -or
        $scenario['personaCount'] -isnot [int] -or
        $scenario['maxRounds'] -isnot [int] -or
        $scenario['containsRealUserData'] -isnot [bool]) {
        Write-Output 'Manifest scenario has invalid JSON types.'
    }
    $artifacts = $Manifest['artifacts']
    if ($artifacts -isnot [System.Collections.IDictionary] -or
        $artifacts['seedFile'] -isnot [string] -or
        $artifacts['seedSha256'] -isnot [string] -or
        $artifacts['simulationRequestFile'] -isnot [string] -or
        $artifacts['simulationRequestSha256'] -isnot [string]) {
        Write-Output 'Manifest artifacts have invalid JSON types.'
    }
}

function Test-LexiQuestMiroFishReportTypes {
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    if ($Report -isnot [System.Collections.IDictionary]) {
        Write-Output 'Report root must be a JSON object.'
        return
    }
    if ($Report['schemaVersion'] -isnot [int]) {
        Write-Output 'Report schemaVersion must be a JSON integer.'
    }
    if ($Report['advisoryOnly'] -isnot [bool]) {
        Write-Output 'Report advisoryOnly must be a JSON boolean.'
    }
    if ($Report['dataClassification'] -isnot [string] -or
        $Report['seedSha256'] -isnot [string]) {
        Write-Output 'Report classification and seedSha256 must be strings.'
    }

    $engine = $Report['engine']
    if ($engine -isnot [System.Collections.IDictionary] -or
        $engine['name'] -isnot [string] -or
        $engine['version'] -isnot [string] -or
        $engine['commit'] -isnot [string]) {
        Write-Output 'Report engine must contain string metadata.'
    }
    $scenario = $Report['scenario']
    if ($scenario -isnot [System.Collections.IDictionary] -or
        $scenario['personaCount'] -isnot [int] -or
        $scenario['maxRounds'] -isnot [int] -or
        $scenario['containsRealUserData'] -isnot [bool]) {
        Write-Output 'Report scenario has invalid JSON types.'
    }

    $findings = $Report['findings']
    if ($findings -isnot [System.Collections.IList] -or
        $findings -is [string] -or
        $findings -is [System.Collections.IDictionary]) {
        Write-Output 'Report findings must be a JSON array.'
        return
    }
    $textFields = @(
        'id',
        'severity',
        'surface',
        'persona',
        'observation',
        'evidence',
        'recommendation',
        'verification'
    )
    foreach ($finding in $findings) {
        if ($finding -isnot [System.Collections.IDictionary]) {
            Write-Output 'Every finding must be a JSON object.'
            continue
        }
        foreach ($field in $textFields) {
            $value = $finding[$field]
            if ($value -isnot [string]) {
                Write-Output ("Finding {0} must be a JSON string." -f $field)
            } elseif ($value.Length -gt 4000) {
                Write-Output ("Finding {0} exceeds 4000 characters." -f $field)
            }
        }
    }
}

function Test-LexiQuestMiroFishManifest {
    param(
        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string]$ActualSeedSha256,

        [Parameter(Mandatory)]
        [string]$ActualSimulationRequestSha256
    )

    foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
            -InputObject $Manifest `
            -Allowed @(
                'schemaVersion',
                'generatedAtUtc',
                'advisoryOnly',
                'dataClassification',
                'sourceCommit',
                'engine',
                'scenario',
                'artifacts'
            ) `
            -Context 'Manifest')) {
        Write-Output $errorMessage
    }

    if ((Get-LexiQuestObjectProperty $Manifest 'schemaVersion') -ne 1) {
        Write-Output 'Manifest schemaVersion must be 1.'
    }
    if ((Get-LexiQuestObjectProperty $Manifest 'advisoryOnly') -ne $true) {
        Write-Output 'Manifest must remain advisoryOnly=true.'
    }
    if ((Get-LexiQuestObjectProperty $Manifest 'dataClassification') -ne `
            'synthetic') {
        Write-Output 'Manifest dataClassification must be synthetic.'
    }
    if ([string](Get-LexiQuestObjectProperty $Manifest 'sourceCommit') -notmatch `
            '^[A-Fa-f0-9]{40}$') {
        Write-Output 'Manifest sourceCommit must be a Git commit hash.'
    }

    $engine = Get-LexiQuestObjectProperty $Manifest 'engine'
    if ($null -eq $engine) {
        Write-Output 'Manifest engine metadata is required.'
    } else {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $engine `
                -Allowed @('name', 'version', 'commit') `
                -Context 'Manifest engine')) {
            Write-Output $errorMessage
        }
        if ((Get-LexiQuestObjectProperty $engine 'name') -ne 'MiroFish' -or
            (Get-LexiQuestObjectProperty $engine 'version') -ne 'v0.1.2' -or
            (Get-LexiQuestObjectProperty $engine 'commit') -ne `
                '985f89f49acbb44ee14d9d680682c741a44eeebe') {
            Write-Output 'Manifest engine does not match the approved MiroFish pin.'
        }
    }

    $scenario = Get-LexiQuestObjectProperty $Manifest 'scenario'
    if ($null -eq $scenario) {
        Write-Output 'Manifest scenario metadata is required.'
    } else {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $scenario `
                -Allowed @('personaCount', 'maxRounds', 'containsRealUserData') `
                -Context 'Manifest scenario')) {
            Write-Output $errorMessage
        }
        if ((Get-LexiQuestObjectProperty $scenario 'personaCount') -ne 6) {
            Write-Output 'Manifest personaCount must be 6.'
        }
        if ((Get-LexiQuestObjectProperty $scenario 'maxRounds') -ne 10) {
            Write-Output 'Manifest maxRounds must be 10.'
        }
        if ((Get-LexiQuestObjectProperty $scenario 'containsRealUserData') -ne `
                $false) {
            Write-Output 'Manifest must declare containsRealUserData=false.'
        }
    }

    $artifacts = Get-LexiQuestObjectProperty $Manifest 'artifacts'
    if ($null -eq $artifacts) {
        Write-Output 'Manifest artifacts metadata is required.'
    } else {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $artifacts `
                -Allowed @(
                    'seedFile',
                    'seedSha256',
                    'simulationRequestFile',
                    'simulationRequestSha256'
                ) `
                -Context 'Manifest artifacts')) {
            Write-Output $errorMessage
        }
        $manifestSeedSha256 = [string](
            Get-LexiQuestObjectProperty $artifacts 'seedSha256'
        )
        if ($manifestSeedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            Write-Output 'Manifest seedSha256 must be a SHA-256 value.'
        } elseif ($manifestSeedSha256 -ne $ActualSeedSha256) {
            Write-Output 'Manifest seedSha256 does not match the supplied seed.'
        }
        if ((Get-LexiQuestObjectProperty $artifacts 'seedFile') -ne 'seed.md') {
            Write-Output 'Manifest seedFile must be seed.md.'
        }
        if ((Get-LexiQuestObjectProperty $artifacts 'simulationRequestFile') -ne `
                'simulation-request.md') {
            Write-Output 'Manifest simulationRequestFile is invalid.'
        }
        $manifestRequestSha256 = [string](
            Get-LexiQuestObjectProperty $artifacts 'simulationRequestSha256'
        )
        if ($manifestRequestSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            Write-Output 'Manifest simulationRequestSha256 must be a SHA-256 value.'
        } elseif ($manifestRequestSha256 -ne $ActualSimulationRequestSha256) {
            Write-Output (
                'Manifest simulationRequestSha256 does not match the supplied request.'
            )
        }
    }
}

function Test-LexiQuestMiroFishReport {
    param(
        [Parameter(Mandatory)]
        [object]$Report,

        [Parameter(Mandatory)]
        [object]$Manifest,

        [Parameter(Mandatory)]
        [string]$RawText
    )

    foreach ($textError in @(Test-LexiQuestSyntheticText -Text $RawText)) {
        Write-Output $textError
    }

    foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
            -InputObject $Report `
            -Allowed @(
                'schemaVersion',
                'advisoryOnly',
                'dataClassification',
                'seedSha256',
                'engine',
                'scenario',
                'findings'
            ) `
            -Context 'Report')) {
        Write-Output $errorMessage
    }

    if ((Get-LexiQuestObjectProperty $Report 'schemaVersion') -ne 1) {
        Write-Output 'Report schemaVersion must be 1.'
    }
    if ((Get-LexiQuestObjectProperty $Report 'advisoryOnly') -ne $true) {
        Write-Output 'Report must remain advisoryOnly=true.'
    }
    if ((Get-LexiQuestObjectProperty $Report 'dataClassification') -ne 'synthetic') {
        Write-Output 'Report dataClassification must be synthetic.'
    }

    $seedSha256 = [string](Get-LexiQuestObjectProperty $Report 'seedSha256')
    $manifestArtifacts = Get-LexiQuestObjectProperty $Manifest 'artifacts'
    $manifestSeedSha256 = if ($null -eq $manifestArtifacts) {
        ''
    } else {
        [string](Get-LexiQuestObjectProperty $manifestArtifacts 'seedSha256')
    }
    if ($seedSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
        Write-Output 'Report seedSha256 must be a 64-character SHA-256 value.'
    } elseif ($seedSha256 -ne $manifestSeedSha256) {
        Write-Output 'Report seedSha256 does not match the pack manifest.'
    }

    $engine = Get-LexiQuestObjectProperty $Report 'engine'
    if ($null -eq $engine) {
        Write-Output 'Report engine metadata is required.'
    } else {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $engine `
                -Allowed @('name', 'version', 'commit') `
                -Context 'Report engine')) {
            Write-Output $errorMessage
        }
        if ((Get-LexiQuestObjectProperty $engine 'name') -ne 'MiroFish') {
            Write-Output 'Report engine.name must be MiroFish.'
        }
        if ((Get-LexiQuestObjectProperty $engine 'version') -ne 'v0.1.2') {
            Write-Output 'Report engine.version must be v0.1.2.'
        }
        if ((Get-LexiQuestObjectProperty $engine 'commit') -ne `
                '985f89f49acbb44ee14d9d680682c741a44eeebe') {
            Write-Output 'Report engine.commit does not match the approved pin.'
        }
    }

    $scenario = Get-LexiQuestObjectProperty $Report 'scenario'
    if ($null -eq $scenario) {
        Write-Output 'Report scenario metadata is required.'
    } else {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $scenario `
                -Allowed @('personaCount', 'maxRounds', 'containsRealUserData') `
                -Context 'Report scenario')) {
            Write-Output $errorMessage
        }
        if ((Get-LexiQuestObjectProperty $scenario 'containsRealUserData') -ne $false) {
            Write-Output 'Report must declare containsRealUserData=false.'
        }
        $personaCount = Get-LexiQuestObjectProperty $scenario 'personaCount'
        if ($personaCount -ne 6) {
            Write-Output 'Pilot report must contain exactly six synthetic personas.'
        }
        $maxRounds = Get-LexiQuestObjectProperty $scenario 'maxRounds'
        if ($maxRounds -lt 1 -or $maxRounds -gt 10) {
            Write-Output 'Pilot maxRounds must be between 1 and 10.'
        }
    }

    $findingsProperty = $Report.PSObject.Properties['findings']
    if ($null -eq $findingsProperty) {
        Write-Output 'Report findings array is required.'
        return
    }
    $findings = @($findingsProperty.Value)
    if ($findings.Count -gt 100) {
        Write-Output 'Report findings exceed the 100-item review bound.'
        return
    }

    $allowedSeverities = @('P0', 'P1', 'P2', 'P3')
    $allowedVerification = @(
        'flutter_widget',
        'flutter_integration',
        'adb_device',
        'talkback_manual',
        'human_uat'
    )
    $requiredFindingText = @(
        'id',
        'surface',
        'persona',
        'observation',
        'evidence',
        'recommendation'
    )

    foreach ($finding in $findings) {
        foreach ($errorMessage in @(Test-LexiQuestAllowedProperties `
                -InputObject $finding `
                -Allowed @(
                    'id',
                    'severity',
                    'surface',
                    'persona',
                    'observation',
                    'evidence',
                    'recommendation',
                    'verification'
                ) `
                -Context 'Finding')) {
            Write-Output $errorMessage
        }
        foreach ($name in $requiredFindingText) {
            $value = [string](Get-LexiQuestObjectProperty $finding $name)
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Output ("Finding is missing {0}." -f $name)
            }
        }
        $severity = [string](Get-LexiQuestObjectProperty $finding 'severity')
        if ($severity -notin $allowedSeverities) {
            Write-Output ("Finding has unsupported severity: {0}." -f $severity)
        }
        $verification = [string](
            Get-LexiQuestObjectProperty $finding 'verification'
        )
        if ($verification -notin $allowedVerification) {
            Write-Output (
                "Finding has unsupported verification target: {0}." -f `
                    $verification
            )
        }
    }
}

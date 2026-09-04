#Requires -Version 5.1
[CmdletBinding()]
param(
    [AllowEmptyString()][string]$DeviceId = '',
    [string]$OutputDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ObjectPropertyValue {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-NullableBoolean {
    param([AllowNull()]$Value)

    if ($Value -is [bool]) {
        return $Value
    }
    if ($Value -is [string]) {
        $parsed = $false
        if ([bool]::TryParse($Value, [ref]$parsed)) {
            return $parsed
        }
    }
    return $null
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    if ($fullPath.Equals(
        $fullRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        return $true
    }
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith(
        $rootPrefix,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-RunnerError {
    param([Parameter(Mandatory = $true)][string]$Message)
    [Console]::Error.WriteLine($Message)
}

function Get-CommittedSourceState {
    $state = [ordered]@{
        inspectionSucceeded = $false
        inspectionError = $null
        commitSha = $null
        stagedContentDiff = $null
        unstagedContentDiff = $null
        nonIgnoredUntrackedCount = $null
        statusOnlyTrackedPathCount = $null
        statusOnlyTrackedPaths = @()
        contentClean = $false
    }

    $commitOutput = @(& git rev-parse HEAD)
    if ($LASTEXITCODE -ne 0 -or $commitOutput.Count -ne 1) {
        $state.inspectionError = 'Unable to resolve the build commit identity.'
        return [pscustomobject]$state
    }
    $commitSha = ([string]$commitOutput[0]).Trim().ToLowerInvariant()
    if ($commitSha -notmatch '^[0-9a-f]{40}$') {
        $state.inspectionError = 'Git returned a non-canonical commit identity.'
        return [pscustomobject]$state
    }
    $state.commitSha = $commitSha

    & git diff --cached --quiet --exit-code
    $stagedDiffExitCode = $LASTEXITCODE
    if ($stagedDiffExitCode -notin @(0, 1)) {
        $state.inspectionError = 'Unable to inspect staged source content.'
        return [pscustomobject]$state
    }
    $state.stagedContentDiff = $stagedDiffExitCode -eq 1

    & git diff --quiet --exit-code
    $unstagedDiffExitCode = $LASTEXITCODE
    if ($unstagedDiffExitCode -notin @(0, 1)) {
        $state.inspectionError = 'Unable to inspect unstaged source content.'
        return [pscustomobject]$state
    }
    $state.unstagedContentDiff = $unstagedDiffExitCode -eq 1

    $untrackedOutput = @(& git ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        $state.inspectionError = `
            'Unable to inspect non-ignored untracked files.'
        return [pscustomobject]$state
    }
    $nonIgnoredUntrackedPaths = @(
        $untrackedOutput | ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $state.nonIgnoredUntrackedCount = $nonIgnoredUntrackedPaths.Count

    $trackedStatus = @(& git status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0) {
        $state.inspectionError = 'Unable to inspect tracked worktree status.'
        return [pscustomobject]$state
    }
    $statusOnlyTrackedPaths = @(
        $trackedStatus | ForEach-Object {
            $line = [string]$_
            if ($line.Length -ge 4) {
                $line.Substring(3).Trim()
            }
            elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                $line.Trim()
            }
        }
    )
    $state.statusOnlyTrackedPathCount = $statusOnlyTrackedPaths.Count
    $state.statusOnlyTrackedPaths = $statusOnlyTrackedPaths
    $state.contentClean =
        -not $state.stagedContentDiff -and
        -not $state.unstagedContentDiff -and
        $state.nonIgnoredUntrackedCount -eq 0
    $state.inspectionSucceeded = $true
    return [pscustomobject]$state
}

function Format-DirtySourceMessage {
    param([Parameter(Mandatory = $true)]$State)

    return ((
        'Committed source is not reproducible: staged content diff={0}; ' +
        'unstaged content diff={1}; non-ignored untracked files={2}.'
    ) -f
        $State.stagedContentDiff,
        $State.unstagedContentDiff,
        $State.nonIgnoredUntrackedCount)
}

function Test-IntegerValue {
    param([AllowNull()]$Value)

    return (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]
    )
}

function Test-FiniteNumber {
    param([AllowNull()]$Value)

    if (
        -not (Test-IntegerValue $Value) -and
        $Value -isnot [single] -and
        $Value -isnot [double] -and
        $Value -isnot [decimal]
    ) {
        return $false
    }
    $number = [double]$Value
    return -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)
}

function Add-ProfileValidationError {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $Errors.Add($Message) | Out-Null
}

function Get-RequiredProfileProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    if ($null -eq $InputObject) {
        Add-ProfileValidationError $Errors "$Path is missing."
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        Add-ProfileValidationError $Errors "$Path.$Name is missing."
        return $null
    }
    return ,$property.Value
}

function Get-RequiredProfileBoolean {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $value = Get-RequiredProfileProperty $InputObject $Name $Path $Errors
    if ($null -ne $value -and $value -isnot [bool]) {
        Add-ProfileValidationError $Errors "$Path.$Name must be boolean."
        return $null
    }
    return $value
}

function Get-RequiredProfileString {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $value = Get-RequiredProfileProperty $InputObject $Name $Path $Errors
    if ($null -ne $value -and $value -isnot [string]) {
        Add-ProfileValidationError $Errors "$Path.$Name must be a string."
        return $null
    }
    return $value
}

function Get-RequiredProfileInteger {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $value = Get-RequiredProfileProperty $InputObject $Name $Path $Errors
    if ($null -ne $value -and -not (Test-IntegerValue $value)) {
        Add-ProfileValidationError $Errors "$Path.$Name must be an integer."
        return $null
    }
    return $value
}

function Get-RequiredProfileNumber {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Errors
    )

    $value = Get-RequiredProfileProperty $InputObject $Name $Path $Errors
    if ($null -ne $value -and -not (Test-FiniteNumber $value)) {
        Add-ProfileValidationError $Errors "$Path.$Name must be a finite number."
        return $null
    }
    return $value
}

function Test-AdventurePerformanceProfile {
    param([AllowNull()]$Profile)

    $errors = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Profile) {
        Add-ProfileValidationError $errors 'adventurePerformance is missing.'
        return [pscustomobject]@{
            IsValid = $false
            AllBudgetsPassed = $null
            Errors = @($errors)
        }
    }

    $schemaVersion = Get-RequiredProfileInteger `
        $Profile 'schemaVersion' 'adventurePerformance' $errors
    if ($null -ne $schemaVersion -and $schemaVersion -ne 1) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.schemaVersion must equal 1.'
    }
    $profileId = Get-RequiredProfileString `
        $Profile 'profileId' 'adventurePerformance' $errors
    if ($null -ne $profileId -and $profileId -cne 'adventure-performance-v1') {
        Add-ProfileValidationError $errors `
            'adventurePerformance.profileId is not the required profile.'
    }
    $buildMode = Get-RequiredProfileString `
        $Profile 'buildMode' 'adventurePerformance' $errors
    if ($null -ne $buildMode -and $buildMode -cne 'profile') {
        Add-ProfileValidationError $errors `
            'adventurePerformance.buildMode must equal profile.'
    }
    $percentileMethod = Get-RequiredProfileString `
        $Profile 'percentileMethod' 'adventurePerformance' $errors
    if ($null -ne $percentileMethod -and $percentileMethod -cne 'nearest-rank') {
        Add-ProfileValidationError $errors `
            'adventurePerformance.percentileMethod must equal nearest-rank.'
    }

    $sampleCounts = Get-RequiredProfileProperty `
        $Profile 'sampleCounts' 'adventurePerformance' $errors
    $exactSampleNames = @(
        'localEntryResolution',
        'journeyProjection',
        'firstMeaningfulRender',
        'standardSessionStart',
        'adventureSessionStart',
        'pairedSessionStartOverhead',
        'mapListTransitions',
        'timelineTransitionMarkers'
    )
    $sampleValues = @{}
    foreach ($name in $exactSampleNames) {
        $value = Get-RequiredProfileInteger `
            $sampleCounts $name 'adventurePerformance.sampleCounts' $errors
        $sampleValues[$name] = $value
        if ($null -ne $value -and $value -ne 20) {
            Add-ProfileValidationError $errors `
                "adventurePerformance.sampleCounts.$name must equal 20."
        }
    }
    $frameCount = Get-RequiredProfileInteger `
        $sampleCounts `
        'mapListFrames' `
        'adventurePerformance.sampleCounts' `
        $errors
    if ($null -ne $frameCount -and $frameCount -lt 20) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.sampleCounts.mapListFrames must be at least 20.'
    }
    $transitionsWithFrames = Get-RequiredProfileInteger `
        $sampleCounts `
        'mapListTransitionsWithFrames' `
        'adventurePerformance.sampleCounts' `
        $errors
    if ($null -ne $transitionsWithFrames -and $transitionsWithFrames -ne 20) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.sampleCounts.mapListTransitionsWithFrames must equal 20.'
    }
    $minimumFramesPerTransition = Get-RequiredProfileInteger `
        $sampleCounts `
        'mapListMinimumFramesPerTransition' `
        'adventurePerformance.sampleCounts' `
        $errors
    if (
        $null -ne $minimumFramesPerTransition -and
        $minimumFramesPerTransition -lt 1
    ) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.sampleCounts.mapListMinimumFramesPerTransition must be positive.'
    }

    $budgets = Get-RequiredProfileProperty `
        $Profile 'budgets' 'adventurePerformance' $errors
    $approvedBudgets = [ordered]@{
        localEntryResolutionP95Ms = 50.0
        journeyProjectionP95Ms = 100.0
        firstMeaningfulRenderP95Ms = 1500.0
        adventureSessionStartOverheadP95Ms = 150.0
        mapListFrameP95Ms = 16.7
        longFrameOrTaskMs = 100.0
    }
    $budgetValues = @{}
    foreach ($entry in $approvedBudgets.GetEnumerator()) {
        $value = Get-RequiredProfileNumber `
            $budgets `
            $entry.Key `
            'adventurePerformance.budgets' `
            $errors
        $budgetValues[$entry.Key] = $value
        if (
            $null -ne $value -and
            [math]::Abs(([double]$value) - ([double]$entry.Value)) -gt 0.000001
        ) {
            Add-ProfileValidationError $errors `
                "adventurePerformance.budgets.$($entry.Key) is not approved."
        }
    }

    $metrics = Get-RequiredProfileProperty `
        $Profile 'metrics' 'adventurePerformance' $errors
    $metricNames = @(
        'localEntryResolutionP95Ms',
        'journeyProjectionP95Ms',
        'firstMeaningfulRenderP95Ms',
        'standardSessionStartP95Ms',
        'adventureSessionStartP95Ms',
        'adventureSessionStartOverheadP95Ms',
        'mapListFrameP95Ms',
        'mapListFrameMaxMs',
        'timelineSynchronousTaskP95Ms',
        'timelineSynchronousTaskMaxMs'
    )
    $metricValues = @{}
    foreach ($name in $metricNames) {
        $value = Get-RequiredProfileNumber `
            $metrics $name 'adventurePerformance.metrics' $errors
        $metricValues[$name] = $value
        if (
            $null -ne $value -and
            $name -ne 'adventureSessionStartOverheadP95Ms' -and
            [double]$value -lt 0
        ) {
            Add-ProfileValidationError $errors `
                "adventurePerformance.metrics.$name must be non-negative."
        }
    }
    $longFrameCount = Get-RequiredProfileInteger `
        $metrics `
        'mapListLongFrameCount' `
        'adventurePerformance.metrics' `
        $errors
    $timelineLongTaskCount = Get-RequiredProfileInteger `
        $metrics `
        'timelineLongTaskCount' `
        'adventurePerformance.metrics' `
        $errors
    $timelineSynchronousTaskCount = Get-RequiredProfileInteger `
        $metrics `
        'timelineSynchronousTaskCount' `
        'adventurePerformance.metrics' `
        $errors
    $timelineSourceEventCount = Get-RequiredProfileInteger `
        $metrics `
        'timelineSourceEventCount' `
        'adventurePerformance.metrics' `
        $errors
    foreach ($countEntry in @(
        @{ Name = 'mapListLongFrameCount'; Value = $longFrameCount },
        @{ Name = 'timelineLongTaskCount'; Value = $timelineLongTaskCount }
    )) {
        if ($null -ne $countEntry.Value -and $countEntry.Value -lt 0) {
            Add-ProfileValidationError $errors `
                "adventurePerformance.metrics.$($countEntry.Name) must be non-negative."
        }
    }
    if (
        $null -ne $timelineSynchronousTaskCount -and
        $timelineSynchronousTaskCount -lt 1
    ) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.metrics.timelineSynchronousTaskCount must be positive.'
    }
    if (
        $null -ne $timelineSourceEventCount -and
        ($timelineSourceEventCount -lt 1 -or $timelineSourceEventCount -gt 100000)
    ) {
        Add-ProfileValidationError $errors `
            'adventurePerformance.metrics.timelineSourceEventCount must be between 1 and 100000.'
    }
    if (
        $null -ne $timelineSynchronousTaskCount -and
        $null -ne $timelineSourceEventCount -and
        $timelineSynchronousTaskCount -gt $timelineSourceEventCount
    ) {
        Add-ProfileValidationError $errors `
            'Synchronous timeline task count cannot exceed source event count.'
    }
    if (
        $null -ne $metricValues.mapListFrameP95Ms -and
        $null -ne $metricValues.mapListFrameMaxMs -and
        [double]$metricValues.mapListFrameP95Ms -gt
            [double]$metricValues.mapListFrameMaxMs
    ) {
        Add-ProfileValidationError $errors `
            'Map/list frame p95 cannot exceed its maximum.'
    }
    if (
        $null -ne $metricValues.timelineSynchronousTaskP95Ms -and
        $null -ne $metricValues.timelineSynchronousTaskMaxMs -and
        [double]$metricValues.timelineSynchronousTaskP95Ms -gt
            [double]$metricValues.timelineSynchronousTaskMaxMs
    ) {
        Add-ProfileValidationError $errors `
            'Timeline synchronous task p95 cannot exceed its maximum.'
    }

    $authority = Get-RequiredProfileProperty `
        $Profile 'authorityInvariants' 'adventurePerformance' $errors
    $invariantNames = @(
        'threeNodeProjection',
        'standardAdventureCommandsEquivalent',
        'canonicalSnapshotPinned',
        'evidenceAuthorityUnchanged',
        'pairedSessionStartInputsEquivalent'
    )
    $invariantValues = @{}
    foreach ($name in $invariantNames) {
        $invariantValues[$name] = Get-RequiredProfileBoolean `
            $authority `
            $name `
            'adventurePerformance.authorityInvariants' `
            $errors
    }

    $viewport = Get-RequiredProfileProperty `
        $Profile 'deviceViewport' 'adventurePerformance' $errors
    $viewportValues = @{}
    foreach ($name in @(
        'physicalWidthPx',
        'physicalHeightPx',
        'logicalWidth',
        'logicalHeight',
        'devicePixelRatio'
    )) {
        $viewportValues[$name] = Get-RequiredProfileNumber `
            $viewport `
            $name `
            'adventurePerformance.deviceViewport' `
            $errors
        if (
            $null -ne $viewportValues[$name] -and
            [double]$viewportValues[$name] -le 0
        ) {
            Add-ProfileValidationError $errors `
                "adventurePerformance.deviceViewport.$name must be positive."
        }
    }
    $viewportCaptured = $false
    if (
        $null -ne $viewportValues.physicalWidthPx -and
        $null -ne $viewportValues.physicalHeightPx -and
        $null -ne $viewportValues.logicalWidth -and
        $null -ne $viewportValues.logicalHeight -and
        $null -ne $viewportValues.devicePixelRatio
    ) {
        $widthDelta = [math]::Abs(
            [double]$viewportValues.physicalWidthPx -
            ([double]$viewportValues.logicalWidth *
                [double]$viewportValues.devicePixelRatio)
        )
        $heightDelta = [math]::Abs(
            [double]$viewportValues.physicalHeightPx -
            ([double]$viewportValues.logicalHeight *
                [double]$viewportValues.devicePixelRatio)
        )
        $viewportCaptured =
            [double]$viewportValues.physicalWidthPx -gt 0 -and
            [double]$viewportValues.physicalHeightPx -gt 0 -and
            [double]$viewportValues.logicalWidth -gt 0 -and
            [double]$viewportValues.logicalHeight -gt 0 -and
            [double]$viewportValues.devicePixelRatio -gt 0 -and
            $widthDelta -le 0.5 -and
            $heightDelta -le 0.5
        if (-not $viewportCaptured) {
            Add-ProfileValidationError $errors `
                'Device viewport physical/logical dimensions and DPR are inconsistent.'
        }
    }

    $pause = Get-RequiredProfileProperty `
        $Profile 'learnerPause' 'adventurePerformance' $errors
    $timeoutPolicy = Get-RequiredProfileString `
        $pause 'timeoutPolicy' 'adventurePerformance.learnerPause' $errors
    $sessionTiming = Get-RequiredProfileString `
        $pause 'sessionTiming' 'adventurePerformance.learnerPause' $errors
    $maximumActiveEffortMs = Get-RequiredProfileInteger `
        $pause `
        'maximumActiveEffortMs' `
        'adventurePerformance.learnerPause' `
        $errors
    $fakeClockAdvanceMs = Get-RequiredProfileInteger `
        $pause `
        'fakeClockAdvanceMs' `
        'adventurePerformance.learnerPause' `
        $errors
    $clockSource = Get-RequiredProfileString `
        $pause `
        'clockSource' `
        'adventurePerformance.learnerPause' `
        $errors
    $appObservedMonotonicMs = Get-RequiredProfileInteger `
        $pause `
        'appObservedMonotonicMs' `
        'adventurePerformance.learnerPause' `
        $errors
    $configurationActiveEffortMs = Get-RequiredProfileInteger `
        $pause `
        'configurationActiveEffortMs' `
        'adventurePerformance.learnerPause' `
        $errors
    $excludedIdleMs = Get-RequiredProfileInteger `
        $pause `
        'excludedIdleMs' `
        'adventurePerformance.learnerPause' `
        $errors
    $idleTimeExcluded = Get-RequiredProfileBoolean `
        $pause `
        'idleTimeExcluded' `
        'adventurePerformance.learnerPause' `
        $errors
    $configurationIdle = Get-RequiredProfileBoolean `
        $pause `
        'configurationIdle' `
        'adventurePerformance.learnerPause' `
        $errors
    $sessionStatus = Get-RequiredProfileString `
        $pause `
        'sessionStatus' `
        'adventurePerformance.learnerPause' `
        $errors
    $configurationAcceptsOperations = Get-RequiredProfileBoolean `
        $pause `
        'configurationAcceptsOperations' `
        'adventurePerformance.learnerPause' `
        $errors
    $boundaryExceeded = Get-RequiredProfileBoolean `
        $pause `
        'boundaryExceeded' `
        'adventurePerformance.learnerPause' `
        $errors
    $missionAvailableAfterPause = Get-RequiredProfileBoolean `
        $pause `
        'missionAvailableAfterPause' `
        'adventurePerformance.learnerPause' `
        $errors
    $pauseExpected =
        $timeoutPolicy -ceq 'none' -and
        $sessionTiming -ceq 'untimedAlternative' -and
        $maximumActiveEffortMs -eq 600000 -and
        $null -ne $fakeClockAdvanceMs -and
        $fakeClockAdvanceMs -gt $maximumActiveEffortMs -and
        $clockSource -ceq 'configurationMonotonicMicros' -and
        $appObservedMonotonicMs -eq $fakeClockAdvanceMs -and
        $configurationActiveEffortMs -eq 300000 -and
        $excludedIdleMs -eq (
            $appObservedMonotonicMs - $configurationActiveEffortMs
        ) -and
        $excludedIdleMs -eq 301000 -and
        $idleTimeExcluded -eq $true -and
        $configurationIdle -eq $false -and
        $sessionStatus -ceq 'active' -and
        $configurationAcceptsOperations -eq $true -and
        $boundaryExceeded -eq $true -and
        $missionAvailableAfterPause -eq $true

    $passes = Get-RequiredProfileProperty `
        $Profile 'passes' 'adventurePerformance' $errors
    $passNames = @(
        'profileMode',
        'localAssetsValid',
        'localEntryResolution',
        'threeNodeJourneyProjection',
        'firstMeaningfulRender',
        'adventureSessionStartOverhead',
        'mapListFrameCoverage',
        'mapListTransitions',
        'timelineLongTasks',
        'learnerPause',
        'deviceViewportCaptured'
    )
    $passValues = @{}
    foreach ($name in $passNames) {
        $passValues[$name] = Get-RequiredProfileBoolean `
            $passes $name 'adventurePerformance.passes' $errors
    }

    $canCompute =
        $null -ne $budgetValues.localEntryResolutionP95Ms -and
        $null -ne $budgetValues.journeyProjectionP95Ms -and
        $null -ne $budgetValues.firstMeaningfulRenderP95Ms -and
        $null -ne $budgetValues.adventureSessionStartOverheadP95Ms -and
        $null -ne $budgetValues.mapListFrameP95Ms -and
        $null -ne $budgetValues.longFrameOrTaskMs -and
        $null -ne $metricValues.localEntryResolutionP95Ms -and
        $null -ne $metricValues.journeyProjectionP95Ms -and
        $null -ne $metricValues.firstMeaningfulRenderP95Ms -and
        $null -ne $metricValues.adventureSessionStartOverheadP95Ms -and
        $null -ne $metricValues.mapListFrameP95Ms -and
        $null -ne $metricValues.mapListFrameMaxMs -and
        $null -ne $metricValues.timelineSynchronousTaskMaxMs -and
        $null -ne $longFrameCount -and
        $null -ne $timelineLongTaskCount -and
        $null -ne $timelineSynchronousTaskCount -and
        $null -ne $timelineSourceEventCount -and
        $null -ne $frameCount -and
        $null -ne $transitionsWithFrames -and
        $null -ne $minimumFramesPerTransition
    $expectedPasses = @{}
    if ($canCompute) {
        $expectedPasses.profileMode = $buildMode -ceq 'profile'
        $expectedPasses.localAssetsValid = $true
        $expectedPasses.localEntryResolution =
            [double]$metricValues.localEntryResolutionP95Ms -le
                [double]$budgetValues.localEntryResolutionP95Ms
        $expectedPasses.threeNodeJourneyProjection =
            [double]$metricValues.journeyProjectionP95Ms -le
                [double]$budgetValues.journeyProjectionP95Ms -and
            $invariantValues.threeNodeProjection -eq $true
        $expectedPasses.firstMeaningfulRender =
            [double]$metricValues.firstMeaningfulRenderP95Ms -le
                [double]$budgetValues.firstMeaningfulRenderP95Ms
        $expectedPasses.adventureSessionStartOverhead =
            [double]$metricValues.adventureSessionStartOverheadP95Ms -le
                [double]$budgetValues.adventureSessionStartOverheadP95Ms -and
            $invariantValues.standardAdventureCommandsEquivalent -eq $true -and
            $invariantValues.canonicalSnapshotPinned -eq $true -and
            $invariantValues.evidenceAuthorityUnchanged -eq $true -and
            $invariantValues.pairedSessionStartInputsEquivalent -eq $true
        $expectedPasses.mapListFrameCoverage =
            $frameCount -ge 20 -and
            $transitionsWithFrames -eq 20 -and
            $minimumFramesPerTransition -ge 1
        $expectedPasses.mapListTransitions =
            $expectedPasses.mapListFrameCoverage -and
            [double]$metricValues.mapListFrameP95Ms -le
                [double]$budgetValues.mapListFrameP95Ms -and
            [double]$metricValues.mapListFrameMaxMs -le
                [double]$budgetValues.longFrameOrTaskMs -and
            $longFrameCount -eq 0
        $expectedPasses.timelineLongTasks =
            $sampleValues.timelineTransitionMarkers -eq 20 -and
            $timelineSynchronousTaskCount -gt 0 -and
            $timelineSourceEventCount -le 100000 -and
            [double]$metricValues.timelineSynchronousTaskMaxMs -le
                [double]$budgetValues.longFrameOrTaskMs -and
            $timelineLongTaskCount -eq 0
        $expectedPasses.learnerPause = $pauseExpected
        $expectedPasses.deviceViewportCaptured = $viewportCaptured

        foreach ($name in $passNames) {
            if (
                $null -ne $passValues[$name] -and
                $passValues[$name] -ne $expectedPasses[$name]
            ) {
                Add-ProfileValidationError $errors `
                    "adventurePerformance.passes.$name is inconsistent with evidence."
            }
        }
    }

    $reportedAllBudgetsPassed = Get-RequiredProfileBoolean `
        $Profile 'allBudgetsPassed' 'adventurePerformance' $errors
    $computedAllBudgetsPassed = $null
    if ($canCompute -and $passNames.Where({ $null -eq $passValues[$_] }).Count -eq 0) {
        $computedAllBudgetsPassed = $true
        foreach ($name in $passNames) {
            if ($passValues[$name] -ne $true) {
                $computedAllBudgetsPassed = $false
            }
        }
        if ($reportedAllBudgetsPassed -ne $computedAllBudgetsPassed) {
            Add-ProfileValidationError $errors `
                'adventurePerformance.allBudgetsPassed is inconsistent with pass flags.'
        }
    }

    return [pscustomobject]@{
        IsValid = $errors.Count -eq 0
        AllBudgetsPassed = $reportedAllBudgetsPassed
        Errors = @($errors)
    }
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {
    Write-RunnerError 'Select an Android device explicitly with -DeviceId.'
    exit 64
}

$repositoryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\..')
).TrimEnd('\', '/')
$requiredEvidenceRoot = Join-Path `
    $repositoryRoot `
    'build\adventure-performance'
$selectedOutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $requiredEvidenceRoot
}
else {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
if (-not (Test-PathWithinRoot `
    -Path $selectedOutputDirectory `
    -Root $requiredEvidenceRoot
)) {
    Write-RunnerError (
        'Evidence output must stay beneath build/adventure-performance.'
    )
    exit 67
}

Push-Location $repositoryRoot
try {
    $preRunSource = Get-CommittedSourceState
    if (-not $preRunSource.inspectionSucceeded) {
        Write-RunnerError $preRunSource.inspectionError
        exit 68
    }
    if (-not $preRunSource.contentClean) {
        Write-RunnerError (Format-DirtySourceMessage $preRunSource)
        exit 71
    }
    $commitSha = $preRunSource.commitSha
    $shortCommit = $commitSha.Substring(0, 12)

    $devicesOutput = @(& flutter devices --machine)
    if ($LASTEXITCODE -ne 0) {
        Write-RunnerError 'Unable to enumerate Flutter devices.'
        exit 65
    }
    try {
        $parsedDevices = ConvertFrom-Json -InputObject (
            $devicesOutput -join [Environment]::NewLine
        )
        $devices = @($parsedDevices)
    }
    catch {
        Write-RunnerError 'Flutter device output was not valid JSON.'
        exit 65
    }

    $selectedDevice = @(
        $devices | Where-Object {
            [string](Get-ObjectPropertyValue $_ 'id') -eq $DeviceId
        }
    ) | Select-Object -First 1
    if ($null -eq $selectedDevice) {
        Write-RunnerError "Selected device is not connected: $DeviceId"
        exit 65
    }

    $targetPlatform = [string](
        Get-ObjectPropertyValue $selectedDevice 'targetPlatform'
    )
    $platformType = [string](
        Get-ObjectPropertyValue $selectedDevice 'platformType'
    )
    if (
        [string]::IsNullOrWhiteSpace($targetPlatform) -or
        -not $targetPlatform.ToLowerInvariant().StartsWith('android') -or
        (
            -not [string]::IsNullOrWhiteSpace($platformType) -and
            $platformType.ToLowerInvariant() -ne 'android'
        )
    ) {
        Write-RunnerError 'The selected device is not consistently Android.'
        exit 66
    }

    $isEmulator = Get-NullableBoolean (
        Get-ObjectPropertyValue $selectedDevice 'emulator'
    )
    $evidenceClass = if ($isEmulator -eq $true) {
        'emulator_rehearsal'
    }
    elseif ($isEmulator -eq $false) {
        'physical_device_measurement'
    }
    else {
        'unclassified_android_rehearsal'
    }
    $eligibleForPhysicalCertification = $isEmulator -eq $false

    $versionMatch = Select-String `
        -LiteralPath (Join-Path $repositoryRoot 'pubspec.yaml') `
        -Pattern '^version:\s*(?<value>\S+)\s*$' | Select-Object -First 1
    if ($null -eq $versionMatch) {
        Write-RunnerError 'Unable to resolve the application build version.'
        exit 68
    }
    $applicationVersion = $versionMatch.Matches[0].Groups['value'].Value

    $flutterVersionOutput = @(& flutter --version --machine)
    if ($LASTEXITCODE -ne 0) {
        Write-RunnerError 'Unable to resolve the Flutter toolchain identity.'
        exit 68
    }
    try {
        $flutterVersion = ConvertFrom-Json -InputObject (
            $flutterVersionOutput -join [Environment]::NewLine
        )
    }
    catch {
        Write-RunnerError 'Flutter version output was not valid JSON.'
        exit 68
    }

    New-Item `
        -ItemType Directory `
        -Path $selectedOutputDirectory `
        -Force | Out-Null
    $timestamp = [DateTime]::UtcNow.ToString(
        'yyyyMMddTHHmmssfffZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
    $safeDeviceId = [regex]::Replace($DeviceId, '[^A-Za-z0-9._-]', '_')
    $artifactStem = "adventure-performance-$timestamp-$shortCommit-$safeDeviceId"
    $integrationOutputPath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.integration.json"
    $driveLogPath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.drive.log"
    $evidencePath = Join-Path `
        $selectedOutputDirectory `
        "$artifactStem.evidence.json"

    $driveArguments = @(
        'drive',
        '--profile',
        '--no-dds',
        '-d',
        $DeviceId,
        '--no-pub',
        '--driver=test_driver/adventure_performance_profile_driver.dart',
        '--target=integration_test/adventure_performance_profile_test.dart'
    )
    $priorDriverOutput = $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT
    $priorDriveErrorActionPreference = $ErrorActionPreference
    $driveOutput = @()
    $driveExitCode = 69
    try {
        $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT = `
            $integrationOutputPath
        $ErrorActionPreference = 'Continue'
        $driveOutput = @(& flutter @driveArguments 2>&1)
        $driveExitCode = $LASTEXITCODE
    }
    catch {
        $driveOutput = @($_.Exception.ToString())
        $driveExitCode = 69
    }
    finally {
        $ErrorActionPreference = $priorDriveErrorActionPreference
        if ($null -eq $priorDriverOutput) {
            Remove-Item `
                -LiteralPath 'Env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT' `
                -ErrorAction SilentlyContinue
        }
        else {
            $env:LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT = `
                $priorDriverOutput
        }
    }
    $driveOutputText = @($driveOutput | ForEach-Object { [string]$_ }) `
        -join [Environment]::NewLine
    Write-Utf8NoBom -Path $driveLogPath -Content $driveOutputText
    foreach ($line in $driveOutput) {
        Write-Output ([string]$line)
    }

    $integrationOutputExists = Test-Path -LiteralPath $integrationOutputPath
    $integrationOutputError = $null
    $integrationResponse = $null
    $profile = $null
    $allBudgetsPassed = $null
    $profileValidationErrors = @()
    if ($integrationOutputExists) {
        try {
            $integrationResponse = Get-Content `
                -Raw `
                -LiteralPath $integrationOutputPath | ConvertFrom-Json
            $profile = Get-ObjectPropertyValue `
                $integrationResponse `
                'adventurePerformance'
            $profileValidation = Test-AdventurePerformanceProfile $profile
            $allBudgetsPassed = $profileValidation.AllBudgetsPassed
            if (-not $profileValidation.IsValid) {
                $profileValidationErrors = @(
                    $profileValidation.Errors | Select-Object -First 50
                )
                $integrationOutputError = $profileValidationErrors -join ' '
            }
        }
        catch {
            $integrationOutputError = $_.Exception.Message
        }
    }
    else {
        $integrationOutputError = 'Integration response file was not written.'
    }

    $profileResultStatus = if (
        $null -ne $integrationOutputError -or
        $null -eq $profile
    ) {
        'invalid_output'
    }
    elseif ($allBudgetsPassed -ne $true) {
        'budget_failed'
    }
    elseif ($driveExitCode -ne 0) {
        'test_failed'
    }
    else {
        'passed'
    }

    $integrationHash = $null
    $integrationBytes = 0
    if ($integrationOutputExists) {
        $integrationHash = (
            Get-FileHash -LiteralPath $integrationOutputPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $integrationBytes = (
            Get-Item -LiteralPath $integrationOutputPath
        ).Length
    }
    $deviceName = [string](Get-ObjectPropertyValue $selectedDevice 'name')
    $deviceOs = [string](Get-ObjectPropertyValue $selectedDevice 'sdk')
    if ([string]::IsNullOrWhiteSpace($deviceOs)) {
        $deviceOs = [string](
            Get-ObjectPropertyValue $selectedDevice 'operatingSystem'
        )
    }
    if ([string]::IsNullOrWhiteSpace($deviceOs)) {
        $deviceOs = 'unknown'
    }

    $postRunSource = Get-CommittedSourceState
    $headUnchanged =
        $postRunSource.inspectionSucceeded -and
        $postRunSource.commitSha -ceq $commitSha
    $sourceReproducible =
        $preRunSource.inspectionSucceeded -and
        $preRunSource.contentClean -and
        $postRunSource.inspectionSucceeded -and
        $postRunSource.contentClean -and
        $headUnchanged
    $resultStatus = if (-not $postRunSource.inspectionSucceeded) {
        'source_inspection_failed'
    }
    elseif (-not $sourceReproducible) {
        'source_changed'
    }
    else {
        $profileResultStatus
    }

    $evidence = [ordered]@{
        schemaVersion = 1
        recordedAtUtc = [DateTime]::UtcNow.ToString('o')
        evidenceClass = $evidenceClass
        certificationStatus = 'not_certified'
        eligibleForPhysicalCertification = $eligibleForPhysicalCertification
        source = [ordered]@{
            commitSha = $commitSha
            postRunCommitSha = $postRunSource.commitSha
            applicationVersion = $applicationVersion
            headUnchanged = $headUnchanged
            reproducible = $sourceReproducible
            stagedContentDiff = $postRunSource.stagedContentDiff
            unstagedContentDiff = $postRunSource.unstagedContentDiff
            nonIgnoredUntrackedCount = `
                $postRunSource.nonIgnoredUntrackedCount
            statusOnlyTrackedPathCount = `
                $postRunSource.statusOnlyTrackedPathCount
            statusOnlyTrackedPaths = $postRunSource.statusOnlyTrackedPaths
            preRun = $preRunSource
            postRun = $postRunSource
        }
        device = [ordered]@{
            id = $DeviceId
            name = $deviceName
            os = $deviceOs
            targetPlatform = $targetPlatform
            platformType = $platformType
            isEmulator = $isEmulator
        }
        build = [ordered]@{
            mode = 'profile'
            flutterVersion = Get-ObjectPropertyValue `
                $flutterVersion `
                'frameworkVersion'
            flutterChannel = Get-ObjectPropertyValue $flutterVersion 'channel'
            flutterRevision = Get-ObjectPropertyValue `
                $flutterVersion `
                'frameworkRevision'
            dartSdkVersion = Get-ObjectPropertyValue `
                $flutterVersion `
                'dartSdkVersion'
        }
        command = [ordered]@{
            executable = 'flutter'
            arguments = $driveArguments
        }
        integrationOutput = [ordered]@{
            fileName = [System.IO.Path]::GetFileName($integrationOutputPath)
            sha256 = $integrationHash
            byteLength = $integrationBytes
            error = $integrationOutputError
            validationErrors = $profileValidationErrors
        }
        profile = $profile
        result = [ordered]@{
            status = $resultStatus
            flutterDriveExitCode = $driveExitCode
            allBudgetsPassed = $allBudgetsPassed
        }
    }
    $evidenceJson = ConvertTo-Json -InputObject $evidence -Depth 30
    Write-Utf8NoBom -Path $evidencePath -Content $evidenceJson

    if ($evidenceClass -eq 'emulator_rehearsal') {
        Write-Output 'EMULATOR REHEARSAL ONLY; not physical-device certification.'
    }
    elseif ($evidenceClass -eq 'unclassified_android_rehearsal') {
        Write-Output (
            'UNCLASSIFIED ANDROID REHEARSAL ONLY; not physical-device ' +
            'certification.'
        )
    }
    else {
        Write-Output 'Physical-device measurement captured; not certified.'
    }
    Write-Output "Adventure performance evidence: $evidencePath"

    if ($resultStatus -eq 'source_inspection_failed') {
        Write-RunnerError $postRunSource.inspectionError
        exit 68
    }
    if ($resultStatus -eq 'source_changed') {
        Write-RunnerError (Format-DirtySourceMessage $postRunSource)
        exit 71
    }
    if ($resultStatus -eq 'invalid_output') {
        exit 69
    }
    if ($resultStatus -eq 'budget_failed') {
        exit 70
    }
    if ($resultStatus -eq 'test_failed') {
        exit $driveExitCode
    }
    exit 0
}
finally {
    Pop-Location
}

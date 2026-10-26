[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$IncludeBoundaryProfiles
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$consoleCandidates = @(
  'C:\LDPlayer\LDPlayer9\ldconsole.exe',
  'C:\LDPlayer\LDPlayer9\dnconsole.exe',
  'C:\Program Files\LDPlayer\LDPlayer9\ldconsole.exe'
)
$ldConsole = $consoleCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $ldConsole) {
  throw 'LDPlayer 9 console was not found.'
}

$profiles = @(
  [pscustomobject]@{ Name = 'LQ-P1-Vivo-393x876'; Resolution = '1080,2408,440'; Manufacturer = 'vivo'; Model = 'V2041'; WindowDp = '393x876'; Purpose = 'Phase 1 canonical Vivo' },
  [pscustomobject]@{ Name = 'LQ-P1-Compact-360x800'; Resolution = '1080,2400,480'; Manufacturer = 'vivo'; Model = 'V2041'; WindowDp = '360x800'; Purpose = 'Phase 1 compact lower check' },
  [pscustomobject]@{ Name = 'LQ-P1-Compact-412x915'; Resolution = '824,1830,320'; Manufacturer = 'vivo'; Model = 'V2041'; WindowDp = '412x915'; Purpose = 'Phase 1 compact upper check' },
  [pscustomobject]@{ Name = 'LQ-P3-Tablet-S-600x960'; Resolution = '1200,1920,320'; Manufacturer = 'samsung'; Model = 'SM-X210'; WindowDp = '600x960'; Purpose = 'Phase 3 small tablet lower boundary' },
  [pscustomobject]@{ Name = 'LQ-P3-Tablet-SU-800x1280'; Resolution = '1600,2560,320'; Manufacturer = 'samsung'; Model = 'SM-X710'; WindowDp = '800x1280'; Purpose = 'Phase 3 small tablet upper check' },
  [pscustomobject]@{ Name = 'LQ-P3-Tablet-M-1024x1366'; Resolution = '2048,2732,320'; Manufacturer = 'samsung'; Model = 'SM-X810'; WindowDp = '1024x1366'; Purpose = 'Phase 3 medium tablet' },
  [pscustomobject]@{ Name = 'LQ-P3-Tablet-L-1280x800'; Resolution = '2560,1600,320'; Manufacturer = 'samsung'; Model = 'SM-X910'; WindowDp = '1280x800'; Purpose = 'Phase 3 large tablet landscape' }
)

if ($IncludeBoundaryProfiles) {
  $profiles += @(
    [pscustomobject]@{ Name = 'LQ-Boundary-H479'; Resolution = '1600,958,320'; Manufacturer = 'google'; Model = 'LexiQuest_H479'; WindowDp = '800x479'; Purpose = 'Compact-height boundary' },
    [pscustomobject]@{ Name = 'LQ-Boundary-H480'; Resolution = '1600,960,320'; Manufacturer = 'google'; Model = 'LexiQuest_H480'; WindowDp = '800x480'; Purpose = 'Medium-height boundary' }
  )
}

if (-not $Apply) {
  $profiles | Select-Object Name, WindowDp, Resolution, Purpose | Format-Table -AutoSize
  Write-Host 'Plan only. Re-run with -Apply to create or update these named instances.'
  exit 0
}

function Get-LdInstances {
  $rows = & $ldConsole list2
  if ($LASTEXITCODE -ne 0) { throw "LDPlayer list2 failed with exit code $LASTEXITCODE." }
  foreach ($row in $rows) {
    $parts = $row -split ','
    if ($parts.Count -ge 2) {
      [pscustomobject]@{
        Index = [int]$parts[0]
        Name = $parts[1]
        Width = if ($parts.Count -ge 10) { [int]$parts[7] } else { $null }
        Height = if ($parts.Count -ge 10) { [int]$parts[8] } else { $null }
        Dpi = if ($parts.Count -ge 10) { [int]$parts[9] } else { $null }
        Raw = $row
      }
    }
  }
}

foreach ($profile in $profiles) {
  $existing = @(Get-LdInstances)
  if ($profile.Name -notin $existing.Name) {
    & $ldConsole add --name $profile.Name | Out-Null
    if ($profile.Name -notin @(Get-LdInstances).Name) { throw "Could not create LDPlayer instance $($profile.Name)." }
  }

  & $ldConsole modify --name $profile.Name --resolution $profile.Resolution --manufacturer $profile.Manufacturer --model $profile.Model --autorotate 1 | Out-Null
  $expected = $profile.Resolution -split ','
  $actual = @(Get-LdInstances) | Where-Object Name -eq $profile.Name | Select-Object -First 1
  if (-not $actual -or $actual.Width -ne [int]$expected[0] -or $actual.Height -ne [int]$expected[1] -or $actual.Dpi -ne [int]$expected[2]) {
    throw "Could not verify LDPlayer resolution for $($profile.Name)."
  }

  $configPath = Join-Path (Split-Path -Parent $ldConsole) "vms\config\leidian$($actual.Index).config"
  $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
  if ($config.PSObject.Properties.Name -contains 'basicSettings.adbDebug') {
    $config.'basicSettings.adbDebug' = 1
  } else {
    $config | Add-Member -NotePropertyName 'basicSettings.adbDebug' -NotePropertyValue 1
  }
  $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding utf8
  if ((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).'basicSettings.adbDebug' -ne 1) {
    throw "Could not enable ADB for $($profile.Name)."
  }
}

$configured = @(Get-LdInstances) | Where-Object { $_.Name -like 'LQ-*' }
$profiles | ForEach-Object {
  $profile = $_
  $instance = $configured | Where-Object Name -eq $profile.Name | Select-Object -First 1
  [pscustomobject]@{
    Name = $profile.Name
    Index = $instance.Index
    WindowDp = $profile.WindowDp
    Resolution = $profile.Resolution
    Purpose = $profile.Purpose
  }
} | Format-Table -AutoSize

#Requires -Version 5.1
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:PassedCount = 0
$script:FailedCount = 0

function Write-Pass {
    param([string]$Message)
    $script:PassedCount++
}

function Write-Fail {
    param([string]$Message)
    $script:FailedCount++
    Write-Host ('  [FAIL] ' + $Message) -ForegroundColor Red
}

function Assert-True {
    param([object]$Value, [string]$Message)
    if ($Value) { Write-Pass $Message } else { Write-Fail $Message }
}

function Assert-False {
    param([object]$Value, [string]$Message)
    if (-not $Value) { Write-Pass $Message } else { Write-Fail $Message }
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ($Expected -eq $Actual) {
        Write-Pass $Message
    } else {
        Write-Fail ($Message + " (expected '$Expected', got '$Actual')")
    }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try {
        & $Action
        Write-Fail ($Message + ' (did not throw)')
    } catch {
        Write-Pass $Message
    }
}

function Assert-DoesNotThrow {
    param([scriptblock]$Action, [string]$Message)
    try {
        & $Action
        Write-Pass $Message
    } catch {
        Write-Fail ($Message + ' (' + $_.Exception.Message + ')')
    }
}

function Get-TestRawSha256 {
    param([byte[]]$Bytes)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Set-UInt16LittleEndian {
    param([byte[]]$Bytes, [int]$Offset, [UInt16]$Value)
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}

function Set-UInt32LittleEndian {
    param([byte[]]$Bytes, [int]$Offset, [UInt32]$Value)
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}

function Set-UInt64LittleEndian {
    param([byte[]]$Bytes, [int]$Offset, [UInt64]$Value)
    [BitConverter]::GetBytes($Value).CopyTo($Bytes, $Offset)
}

function Get-AlignedOffset {
    param([int]$Value, [int]$Alignment)
    return [int](($Value + $Alignment - 1) -band (-bnot ($Alignment - 1)))
}

function New-TestElf64 {
    param(
        [byte]$BuildIdSeed = 1,
        [UInt16]$Machine = 62
    )

    $strings = [Text.Encoding]::ASCII.GetBytes(
        "`0.shstrtab`0.note.gnu.build-id`0.data`0"
    )
    $stringOffset = 64
    $noteOffset = Get-AlignedOffset ($stringOffset + $strings.Length) 4
    $noteSize = 36
    $dataOffset = $noteOffset + $noteSize
    $dataSize = 4
    $sectionOffset = Get-AlignedOffset ($dataOffset + $dataSize) 8
    $sectionCount = 4
    $sectionSize = 64
    $bytes = New-Object byte[] ($sectionOffset + ($sectionCount * $sectionSize))

    $bytes[0] = 0x7f
    $bytes[1] = [byte][char]'E'
    $bytes[2] = [byte][char]'L'
    $bytes[3] = [byte][char]'F'
    $bytes[4] = 2 # ELFCLASS64
    $bytes[5] = 1 # ELFDATA2LSB
    $bytes[6] = 1 # EV_CURRENT
    Set-UInt16LittleEndian $bytes 16 3 # ET_DYN
    Set-UInt16LittleEndian $bytes 18 $Machine
    Set-UInt64LittleEndian $bytes 40 ([UInt64]$sectionOffset)
    Set-UInt16LittleEndian $bytes 52 64
    Set-UInt16LittleEndian $bytes 58 ([UInt16]$sectionSize)
    Set-UInt16LittleEndian $bytes 60 ([UInt16]$sectionCount)
    Set-UInt16LittleEndian $bytes 62 1

    $strings.CopyTo($bytes, $stringOffset)

    $stringHeader = $sectionOffset + $sectionSize
    Set-UInt32LittleEndian $bytes $stringHeader 1
    Set-UInt32LittleEndian $bytes ($stringHeader + 4) 3 # SHT_STRTAB
    Set-UInt64LittleEndian $bytes ($stringHeader + 24) ([UInt64]$stringOffset)
    Set-UInt64LittleEndian $bytes ($stringHeader + 32) ([UInt64]$strings.Length)
    Set-UInt64LittleEndian $bytes ($stringHeader + 48) 1

    $noteHeader = $sectionOffset + (2 * $sectionSize)
    Set-UInt32LittleEndian $bytes $noteHeader 11
    Set-UInt32LittleEndian $bytes ($noteHeader + 4) 7 # SHT_NOTE
    Set-UInt64LittleEndian $bytes ($noteHeader + 24) ([UInt64]$noteOffset)
    Set-UInt64LittleEndian $bytes ($noteHeader + 32) ([UInt64]$noteSize)
    Set-UInt64LittleEndian $bytes ($noteHeader + 48) 4

    Set-UInt32LittleEndian $bytes $noteOffset 4
    Set-UInt32LittleEndian $bytes ($noteOffset + 4) 20
    Set-UInt32LittleEndian $bytes ($noteOffset + 8) 3 # NT_GNU_BUILD_ID
    [Text.Encoding]::ASCII.GetBytes("GNU`0").CopyTo($bytes, $noteOffset + 12)
    for ($index = 0; $index -lt 20; $index++) {
        $bytes[$noteOffset + 16 + $index] = [byte]($BuildIdSeed + $index)
    }

    $dataHeader = $sectionOffset + (3 * $sectionSize)
    Set-UInt32LittleEndian $bytes $dataHeader 30
    Set-UInt32LittleEndian $bytes ($dataHeader + 4) 1 # SHT_PROGBITS
    Set-UInt64LittleEndian $bytes ($dataHeader + 24) ([UInt64]$dataOffset)
    Set-UInt64LittleEndian $bytes ($dataHeader + 32) ([UInt64]$dataSize)
    Set-UInt64LittleEndian $bytes ($dataHeader + 48) 1
    $bytes[$dataOffset] = 0x10
    $bytes[$dataOffset + 1] = 0x20
    $bytes[$dataOffset + 2] = 0x30
    $bytes[$dataOffset + 3] = 0x40

    return [pscustomobject]@{
        Bytes = $bytes
        DataOffset = $dataOffset
        NoteOffset = $noteOffset
        SectionOffset = $sectionOffset
        SectionSize = $sectionSize
    }
}

function New-TestElf32 {
    param(
        [byte]$BuildIdSeed = 1,
        [UInt16]$Machine = 40
    )

    $strings = [Text.Encoding]::ASCII.GetBytes(
        "`0.shstrtab`0.note.gnu.build-id`0.data`0"
    )
    $stringOffset = 52
    $noteOffset = Get-AlignedOffset ($stringOffset + $strings.Length) 4
    $noteSize = 36
    $dataOffset = $noteOffset + $noteSize
    $dataSize = 4
    $sectionOffset = Get-AlignedOffset ($dataOffset + $dataSize) 4
    $sectionCount = 4
    $sectionSize = 40
    $bytes = New-Object byte[] ($sectionOffset + ($sectionCount * $sectionSize))

    $bytes[0] = 0x7f
    $bytes[1] = [byte][char]'E'
    $bytes[2] = [byte][char]'L'
    $bytes[3] = [byte][char]'F'
    $bytes[4] = 1 # ELFCLASS32
    $bytes[5] = 1 # ELFDATA2LSB
    $bytes[6] = 1 # EV_CURRENT
    Set-UInt16LittleEndian $bytes 16 3 # ET_DYN
    Set-UInt16LittleEndian $bytes 18 $Machine
    Set-UInt32LittleEndian $bytes 32 ([UInt32]$sectionOffset)
    Set-UInt16LittleEndian $bytes 40 52
    Set-UInt16LittleEndian $bytes 46 ([UInt16]$sectionSize)
    Set-UInt16LittleEndian $bytes 48 ([UInt16]$sectionCount)
    Set-UInt16LittleEndian $bytes 50 1

    $strings.CopyTo($bytes, $stringOffset)

    $stringHeader = $sectionOffset + $sectionSize
    Set-UInt32LittleEndian $bytes $stringHeader 1
    Set-UInt32LittleEndian $bytes ($stringHeader + 4) 3
    Set-UInt32LittleEndian $bytes ($stringHeader + 16) ([UInt32]$stringOffset)
    Set-UInt32LittleEndian $bytes ($stringHeader + 20) ([UInt32]$strings.Length)
    Set-UInt32LittleEndian $bytes ($stringHeader + 32) 1

    $noteHeader = $sectionOffset + (2 * $sectionSize)
    Set-UInt32LittleEndian $bytes $noteHeader 11
    Set-UInt32LittleEndian $bytes ($noteHeader + 4) 7
    Set-UInt32LittleEndian $bytes ($noteHeader + 16) ([UInt32]$noteOffset)
    Set-UInt32LittleEndian $bytes ($noteHeader + 20) ([UInt32]$noteSize)
    Set-UInt32LittleEndian $bytes ($noteHeader + 32) 4

    Set-UInt32LittleEndian $bytes $noteOffset 4
    Set-UInt32LittleEndian $bytes ($noteOffset + 4) 20
    Set-UInt32LittleEndian $bytes ($noteOffset + 8) 3
    [Text.Encoding]::ASCII.GetBytes("GNU`0").CopyTo($bytes, $noteOffset + 12)
    for ($index = 0; $index -lt 20; $index++) {
        $bytes[$noteOffset + 16 + $index] = [byte]($BuildIdSeed + $index)
    }

    $dataHeader = $sectionOffset + (3 * $sectionSize)
    Set-UInt32LittleEndian $bytes $dataHeader 30
    Set-UInt32LittleEndian $bytes ($dataHeader + 4) 1
    Set-UInt32LittleEndian $bytes ($dataHeader + 16) ([UInt32]$dataOffset)
    Set-UInt32LittleEndian $bytes ($dataHeader + 20) ([UInt32]$dataSize)
    Set-UInt32LittleEndian $bytes ($dataHeader + 32) 1
    $bytes[$dataOffset] = 0x10
    $bytes[$dataOffset + 1] = 0x20
    $bytes[$dataOffset + 2] = 0x30
    $bytes[$dataOffset + 3] = 0x40

    return [pscustomobject]@{
        Bytes = $bytes
        DataOffset = $dataOffset
        NoteOffset = $noteOffset
        SectionOffset = $sectionOffset
        SectionSize = $sectionSize
    }
}

$repoToolCli = Split-Path $PSScriptRoot -Parent
$libPath = Join-Path (Join-Path $repoToolCli 'lib') 'elf-canonical-hash.ps1'
$scriptPath = Join-Path $repoToolCli 'verify-apk-model-runtime.ps1'

if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) {
    Write-Host ("FAIL: missing production dependency '{0}'." -f $libPath) -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Host ("FAIL: missing verifier '{0}'." -f $scriptPath) -ForegroundColor Red
    exit 1
}

. $libPath

Add-Type -AssemblyName System.IO.Compression

function New-TestRuntimeZipArchive {
    param([string[]]$EntryNames)

    $memory = New-Object System.IO.MemoryStream
    $writer = [System.IO.Compression.ZipArchive]::new(
        $memory,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $true
    )
    try {
        foreach ($entryName in $EntryNames) {
            $entry = $writer.CreateEntry($entryName)
            $stream = $entry.Open()
            try {
                $stream.WriteByte(0x41)
            } finally {
                $stream.Dispose()
            }
        }
    } finally {
        $writer.Dispose()
    }
    $memory.Position = 0
    return [pscustomobject]@{
        Memory = $memory
        Archive = [System.IO.Compression.ZipArchive]::new(
            $memory,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $true
        )
    }
}

Write-Host '-> Canonical GNU build-id hashing' -ForegroundColor Cyan
$first = New-TestElf64 -BuildIdSeed 1
$second = New-TestElf64 -BuildIdSeed 101
$firstHash = Get-LexiQuestCanonicalElfSha256 -Bytes $first.Bytes -ExpectedMachine 62
$secondHash = Get-LexiQuestCanonicalElfSha256 -Bytes $second.Bytes -ExpectedMachine 62
Assert-True ((Get-TestRawSha256 $first.Bytes) -ne (Get-TestRawSha256 $second.Bytes)) 'checkout-path build IDs change the raw ELF hash'
Assert-Equal $firstHash $secondHash 'ELFs differing only by GNU build ID canonicalize equally'

$outsideMutation = [byte[]]$second.Bytes.Clone()
$outsideMutation[$second.DataOffset] = $outsideMutation[$second.DataOffset] -bxor 0xff
$outsideHash = Get-LexiQuestCanonicalElfSha256 -Bytes $outsideMutation -ExpectedMachine 62
Assert-True ($outsideHash -ne $firstHash) 'a byte outside the build-id note changes the canonical hash'

$armFirst = New-TestElf32 -BuildIdSeed 1
$armSecond = New-TestElf32 -BuildIdSeed 101
$armFirstHash = Get-LexiQuestCanonicalElfSha256 -Bytes $armFirst.Bytes -ExpectedMachine 40
$armSecondHash = Get-LexiQuestCanonicalElfSha256 -Bytes $armSecond.Bytes -ExpectedMachine 40
Assert-Equal $armFirstHash $armSecondHash 'ELF32 ARM build-id-only differences canonicalize equally'
$armOutsideMutation = [byte[]]$armSecond.Bytes.Clone()
$armOutsideMutation[$armSecond.DataOffset] = $armOutsideMutation[$armSecond.DataOffset] -bxor 0xff
$armOutsideHash = Get-LexiQuestCanonicalElfSha256 -Bytes $armOutsideMutation -ExpectedMachine 40
Assert-True ($armOutsideHash -ne $armFirstHash) 'ELF32 ARM bytes outside the note remain integrity-sensitive'

$armOutOfRange = [byte[]]$armFirst.Bytes.Clone()
$armNoteHeader = $armFirst.SectionOffset + (2 * $armFirst.SectionSize)
Set-UInt32LittleEndian $armOutOfRange ($armNoteHeader + 16) ([UInt32]::MaxValue)
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $armOutOfRange -ExpectedMachine 40 | Out-Null
} 'ELF32 out-of-range note data fails closed'
$armTruncated = [byte[]]$armFirst.Bytes[0..31]
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $armTruncated -ExpectedMachine 40 | Out-Null
} 'truncated ELF32 fails closed'

Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $first.Bytes -ExpectedMachine 183 | Out-Null
} 'an ELF for the wrong ABI machine fails closed'

$malformed = [byte[]]$first.Bytes.Clone()
$malformed[0] = 0
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $malformed -ExpectedMachine 62 | Out-Null
} 'malformed ELF fails closed'

$malformedNote = [byte[]]$first.Bytes.Clone()
Set-UInt32LittleEndian $malformedNote $first.NoteOffset 5
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $malformedNote -ExpectedMachine 62 | Out-Null
} 'malformed GNU build-id note fails closed'

$missingNote = [byte[]]$first.Bytes.Clone()
$noteHeader = $first.SectionOffset + (2 * $first.SectionSize)
Set-UInt32LittleEndian $missingNote $noteHeader 30
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $missingNote -ExpectedMachine 62 | Out-Null
} 'missing GNU build-id note fails closed'

$duplicateNote = [byte[]]$first.Bytes.Clone()
$duplicateHeader = $first.SectionOffset + (3 * $first.SectionSize)
Set-UInt32LittleEndian $duplicateNote $duplicateHeader 11
Set-UInt32LittleEndian $duplicateNote ($duplicateHeader + 4) 7
Set-UInt64LittleEndian $duplicateNote ($duplicateHeader + 24) ([UInt64]$first.NoteOffset)
Set-UInt64LittleEndian $duplicateNote ($duplicateHeader + 32) 36
Assert-Throws {
    Get-LexiQuestCanonicalElfSha256 -Bytes $duplicateNote -ExpectedMachine 62 | Out-Null
} 'duplicate GNU build-id notes fail closed'

Write-Host '-> Raw-vendor/canonical-custom policy' -ForegroundColor Cyan
$vendorEntry = 'lib/arm64-v8a/libtensorflowlite_jni.so'
$customEntry = 'lib/x86_64/libtflite_custom_ops.so'
$rawPins = @{$vendorEntry = Get-TestRawSha256 $first.Bytes}
$canonicalPins = @{
    Debug = @{$customEntry = $firstHash}
    Release = @{$customEntry = $outsideHash}
}
$vendorOriginal = Test-LexiQuestNativeLibraryIntegrity `
    -EntryName $vendorEntry `
    -Bytes $first.Bytes `
    -BuildMode Debug `
    -ExpectedRawSha256ByEntry $rawPins `
    -ExpectedCanonicalSha256ByMode $canonicalPins
$vendorBuildIdChanged = Test-LexiQuestNativeLibraryIntegrity `
    -EntryName $vendorEntry `
    -Bytes $second.Bytes `
    -BuildMode Debug `
    -ExpectedRawSha256ByEntry $rawPins `
    -ExpectedCanonicalSha256ByMode $canonicalPins
Assert-True $vendorOriginal.Matches 'vendor binaries use their exact raw pin'
Assert-False $vendorBuildIdChanged.Matches 'vendor build-id changes still fail raw integrity'

$customBuildIdChanged = Test-LexiQuestNativeLibraryIntegrity `
    -EntryName $customEntry `
    -Bytes $second.Bytes `
    -BuildMode Debug `
    -ExpectedRawSha256ByEntry $rawPins `
    -ExpectedCanonicalSha256ByMode $canonicalPins
Assert-True $customBuildIdChanged.Matches 'custom-op build-id-only changes use canonical integrity'
$debugUnderRelease = Test-LexiQuestNativeLibraryIntegrity `
    -EntryName $customEntry `
    -Bytes $first.Bytes `
    -BuildMode Release `
    -ExpectedRawSha256ByEntry $rawPins `
    -ExpectedCanonicalSha256ByMode $canonicalPins
$releaseUnderDebug = Test-LexiQuestNativeLibraryIntegrity `
    -EntryName $customEntry `
    -Bytes $outsideMutation `
    -BuildMode Debug `
    -ExpectedRawSha256ByEntry $rawPins `
    -ExpectedCanonicalSha256ByMode $canonicalPins
Assert-False $debugUnderRelease.Matches 'Debug custom-op bytes cannot pass the Release pin'
Assert-False $releaseUnderDebug.Matches 'Release custom-op bytes cannot pass the Debug pin'

foreach ($invalidCustom in @($malformed, $malformedNote, $missingNote, $duplicateNote)) {
    Assert-Throws {
        Test-LexiQuestNativeLibraryIntegrity `
            -EntryName $customEntry `
            -Bytes $invalidCustom `
            -BuildMode Debug `
            -ExpectedRawSha256ByEntry $rawPins `
            -ExpectedCanonicalSha256ByMode $canonicalPins | Out-Null
    } 'malformed custom-op ELF has no raw-hash fallback'
}

Write-Host '-> Per-entry set integration' -ForegroundColor Cyan
$validLibrarySet = @{
    $vendorEntry = $first.Bytes
    $customEntry = $second.Bytes
}
Assert-DoesNotThrow {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $validLibrarySet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'the complete set applies raw and canonical policy per entry'

$vendorMismatchSet = @{
    $vendorEntry = $second.Bytes
    $customEntry = $second.Bytes
}
Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $vendorMismatchSet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'a vendor mismatch throws at set integration'

Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $validLibrarySet `
        -BuildMode Release `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'a mode-crossed custom pin throws at set integration'

$malformedCustomSet = @{
    $vendorEntry = $first.Bytes
    $customEntry = $malformed
}
Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $malformedCustomSet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'a malformed custom ELF throws with no set-level raw fallback'

$missingEntrySet = @{$vendorEntry = $first.Bytes}
Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $missingEntrySet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'a missing expected entry fails closed'

$unexpectedEntrySet = @{
    $vendorEntry = $first.Bytes
    $customEntry = $second.Bytes
    'lib/x86_64/libunexpected.so' = $first.Bytes
}
Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $unexpectedEntrySet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'an unexpected runtime entry fails closed'

$caseMutatedEntrySet = [System.Collections.Generic.Dictionary[string, byte[]]]::new(
    [StringComparer]::Ordinal
)
$caseMutatedEntrySet.Add($vendorEntry, $first.Bytes)
$caseMutatedEntrySet.Add(
    'lib/X86_64/libtflite_custom_ops.so',
    $second.Bytes
)
Assert-Throws {
    Assert-LexiQuestNativeLibrarySetIntegrity `
        -LibraryBytesByEntry $caseMutatedEntrySet `
        -BuildMode Debug `
        -ExpectedRawSha256ByEntry $rawPins `
        -ExpectedCanonicalSha256ByMode $canonicalPins
} 'a case-mutated APK path cannot satisfy an exact expected entry'

Write-Host '-> APK ZIP entry ambiguity' -ForegroundColor Cyan
$zipReader = Get-Command Read-LexiQuestNativeLibraryBytes `
    -CommandType Function `
    -ErrorAction SilentlyContinue
Assert-True ($null -ne $zipReader) 'the production ZIP reader is behaviorally testable'
if ($null -eq $zipReader) {
    Write-Fail 'duplicate allowlisted ZIP entries fail before dictionary construction (reader missing)'
} else {
    $duplicateZip = New-TestRuntimeZipArchive -EntryNames @(
        'lib/x86_64/libtflite_custom_ops.so',
        'lib/x86_64/libtflite_custom_ops.so'
    )
    try {
        Assert-Throws {
            Read-LexiQuestNativeLibraryBytes -Archive $duplicateZip.Archive | Out-Null
        } 'duplicate allowlisted ZIP entries fail before dictionary construction'
    } finally {
        $duplicateZip.Archive.Dispose()
        $duplicateZip.Memory.Dispose()
    }
}

Write-Host '-> Verifier contract' -ForegroundColor Cyan
$source = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$libSource = Get-Content -LiteralPath $libPath -Raw -Encoding utf8
$required = @(
    'A162D1DDBDAD87C002B7EC7EB31A703F2761335E693F292F94091B3569D8AA37',
    'lib/arm64-v8a/libLiteRt.so',
    'lib/armeabi-v7a/libLiteRt.so',
    'lib/x86_64/libLiteRt.so',
    'libtensorflowlite_jni.so',
    'libtensorflowlite_gpu_jni.so',
    'libtflite_custom_ops.so',
    "ValidateSet('Auto', 'Debug', 'Release')",
    'Read-LexiQuestNativeLibraryBytes',
    'Assert-LexiQuestNativeLibrarySetIntegrity',
    'LibraryBytesByEntry',
    'expectedRawLibraries',
    'expectedCanonicalCustomOps',
    '4D57B6CCCB974930E6FAE223020862128F9B411AC2D33455B2C1D566D7186BB1',
    'F414A52EE4200CAF06A411CC089AEE19A829F6A970FA7A6253357D5FB977D427',
    '39C312A9144A9DC9248FACB7D040B3D532921203D3C60E0A02B2EBFD2025B04F',
    'A6E4E4A4B160525E70788CBFD78F4F3D85C3CA93B24A0E9FC61D8F6C293A12E8',
    '6ADAD6189B89023A511A97C95B1BF1532D2509CE0AA4E65207FB13E3928CDAD3',
    '5A1F4249AB30AF158CA9966D6518EB13EEB38AB9DEEFDEDEF7F203E4031AD6ED',
    'Get-FileHash',
    'GPU accelerator libraries must not be packaged'
)
foreach ($needle in $required) {
    Assert-True $source.Contains($needle) ("verifier contains contract marker: {0}" -f $needle)
}
$expectedVendorPins = [ordered]@{
    'lib/arm64-v8a/libLiteRt.so' =
        '366E3E040B00692158F9F8F9105870672C93348A3D8E9024120B40045A074B0B'
    'lib/arm64-v8a/libtensorflowlite_gpu_jni.so' =
        '03D7EAE3457E3805D7173875E777CB7F79CCF9F837E394EBDB555415A3503C58'
    'lib/arm64-v8a/libtensorflowlite_jni.so' =
        '3BA28CE98B0E6AB7E417B9CC8D9AD0E7E1616EF86DD83CF1EA16EF109A029FA4'
    'lib/armeabi-v7a/libLiteRt.so' =
        '836EE7A2321C9453F02658B6774FC4C5951716432B450BA6BC4E9A94FE524E6C'
    'lib/armeabi-v7a/libtensorflowlite_gpu_jni.so' =
        '222374E093DD0BD492F044F04C53CFB383754B4C5B96EF6B2BD266BE9425461E'
    'lib/armeabi-v7a/libtensorflowlite_jni.so' =
        '5C3280CBA72ED9563CFA47C39B79670BC8F4C2ED26FF545874B33DBA805D8E4B'
    'lib/x86_64/libLiteRt.so' =
        '6D5B2F35D536A3B2D38B26D26328CC9C259133EF2AA0413EC554CD7EF84F6604'
    'lib/x86_64/libtensorflowlite_gpu_jni.so' =
        '4960E910A8CEFA4DEDA380D5B4B270BFE2ABBCE0C8D6CE0F5A0E8CCCB32C1186'
    'lib/x86_64/libtensorflowlite_jni.so' =
        'F0B4F69DD1EC93E289A2A47CBF8623FF9403C1C71E72616B12FC25BA2D284A88'
}
$canonicalMapStart = $source.IndexOf('$expectedCanonicalCustomOps = @{')
$canonicalMapEnd = $source.IndexOf('Add-Type -AssemblyName', $canonicalMapStart)
Assert-True (
    $canonicalMapStart -ge 0 -and $canonicalMapEnd -gt $canonicalMapStart
) 'canonical pin-map boundaries are explicit'
$canonicalMapSource = if (
    $canonicalMapStart -ge 0 -and $canonicalMapEnd -gt $canonicalMapStart
) {
    $source.Substring($canonicalMapStart, $canonicalMapEnd - $canonicalMapStart)
} else {
    ''
}
foreach ($vendorPath in $expectedVendorPins.Keys) {
    $rawPairPattern = (
        [regex]::Escape("'$vendorPath'") + '\s*=\s*' +
        [regex]::Escape("'$($expectedVendorPins[$vendorPath])'")
    )
    Assert-True (
        $source -cmatch $rawPairPattern
    ) ("vendor path retains its exact raw SHA-256 pin: {0}" -f $vendorPath)
    Assert-True (
        -not $canonicalMapSource.Contains($vendorPath)
    ) ("vendor path is excluded from canonical pin maps: {0}" -f $vendorPath)
}
$retiredPathSpecificPins = @(
    'DCAF40FC640C99413DCD8652FB6C3B6F65CDAC50AF001922CB162C155B4E407F',
    '43135F9C6E328D6F9597AF213AAF9333ABCCFE2CEECE228817E5854624BF77C6',
    '52143132085C15890859DB7DE74316AF109EC5A95D3F2C131131F33986A8B42F',
    '570E067F5EED5F3EB27C653D7650CB65846FECED0F5A4543CBFF80260493B10E',
    'ED8A789CDE1266E388818DFA259101628942D336AF4B1A2D7D4264571D923FAB',
    'B1E7A49EE12AEF57A65717536F205E4D0E6E17DE857A5BD4B75F02EEF9328D95'
)
foreach ($retiredPin in $retiredPathSpecificPins) {
    Assert-True (-not $source.Contains($retiredPin)) 'path-specific custom-op raw pin is retired'
}
Assert-True (
    $libSource -match (
        '(?s)function Assert-LexiQuestNativeLibrarySetIntegrity.*?' +
        'foreach \(\$entryName in \$expectedNames\).*?' +
        'Test-LexiQuestNativeLibraryIntegrity.*?' +
        'if \(-not \$integrity\.Matches\).*?throw'
    )
) 'set integration invokes the per-entry policy and throws every mismatch'
Assert-True (-not ($source -match '\bwhile\s*\(' -or $source -match '\bfor\s*\(\s*;\s*;')) 'verifier contains no unbounded retry loop'

$total = $script:PassedCount + $script:FailedCount
Write-Host ''
Write-Host ("verify-apk-model-runtime tests: {0} passed, {1} failed (of {2})" -f $script:PassedCount, $script:FailedCount, $total)
if ($script:FailedCount -gt 0) {
    Write-Host 'FAILED' -ForegroundColor Red
    exit 1
}

Write-Host 'verify-apk-model-runtime contract: PASS' -ForegroundColor Green
exit 0

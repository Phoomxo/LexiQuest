#Requires -Version 5.1
Set-StrictMode -Version 3.0

function Assert-LexiQuestElfRange {
    param(
        [byte[]]$Bytes,
        [int]$Offset,
        [int]$Length,
        [string]$Label
    )

    if (
        $Offset -lt 0 -or
        $Length -lt 0 -or
        $Offset -gt ($Bytes.Length - $Length)
    ) {
        throw "Malformed ELF: $Label is outside the file."
    }
}

function ConvertTo-LexiQuestElfOffset {
    param([UInt64]$Value, [string]$Label)

    if ($Value -gt [int]::MaxValue) {
        throw "Malformed ELF: $Label exceeds the supported file size."
    }
    return [int]$Value
}

function Get-LexiQuestElfUInt16 {
    param([byte[]]$Bytes, [int]$Offset, [string]$Label)
    Assert-LexiQuestElfRange $Bytes $Offset 2 $Label
    return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Get-LexiQuestElfUInt32 {
    param([byte[]]$Bytes, [int]$Offset, [string]$Label)
    Assert-LexiQuestElfRange $Bytes $Offset 4 $Label
    return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Get-LexiQuestElfUInt64 {
    param([byte[]]$Bytes, [int]$Offset, [string]$Label)
    Assert-LexiQuestElfRange $Bytes $Offset 8 $Label
    return [BitConverter]::ToUInt64($Bytes, $Offset)
}

function Get-LexiQuestElfSection {
    param(
        [byte[]]$Bytes,
        [int]$SectionTableOffset,
        [int]$SectionEntrySize,
        [int]$Index,
        [int]$ElfClass
    )

    $headerOffset64 = [UInt64]$SectionTableOffset +
        ([UInt64]$SectionEntrySize * [UInt64]$Index)
    $headerOffset = ConvertTo-LexiQuestElfOffset $headerOffset64 'section header'
    Assert-LexiQuestElfRange $Bytes $headerOffset $SectionEntrySize 'section header'

    $nameIndex = Get-LexiQuestElfUInt32 $Bytes $headerOffset 'section name index'
    $type = Get-LexiQuestElfUInt32 $Bytes ($headerOffset + 4) 'section type'
    if ($ElfClass -eq 1) {
        $fileOffset64 = [UInt64](
            Get-LexiQuestElfUInt32 $Bytes ($headerOffset + 16) 'section offset'
        )
        $fileSize64 = [UInt64](
            Get-LexiQuestElfUInt32 $Bytes ($headerOffset + 20) 'section size'
        )
    } else {
        $fileOffset64 = Get-LexiQuestElfUInt64 $Bytes ($headerOffset + 24) 'section offset'
        $fileSize64 = Get-LexiQuestElfUInt64 $Bytes ($headerOffset + 32) 'section size'
    }

    return [pscustomobject]@{
        Index = $Index
        NameIndex = [UInt32]$nameIndex
        Type = [UInt32]$type
        Offset = ConvertTo-LexiQuestElfOffset $fileOffset64 'section offset'
        Size = ConvertTo-LexiQuestElfOffset $fileSize64 'section size'
    }
}

function Get-LexiQuestElfSectionName {
    param(
        [byte[]]$Bytes,
        [object]$StringTable,
        [UInt32]$NameIndex
    )

    if ($NameIndex -ge [UInt32]$StringTable.Size) {
        throw 'Malformed ELF: section name index is outside .shstrtab.'
    }
    $start = $StringTable.Offset + [int]$NameIndex
    $limit = $StringTable.Offset + $StringTable.Size
    $end = $start
    while ($end -lt $limit -and $Bytes[$end] -ne 0) {
        $end++
    }
    if ($end -ge $limit) {
        throw 'Malformed ELF: section name is not null-terminated.'
    }
    return [Text.Encoding]::ASCII.GetString($Bytes, $start, $end - $start)
}

function Test-LexiQuestElfRangesOverlap {
    param([int]$LeftOffset, [int]$LeftSize, [int]$RightOffset, [int]$RightSize)

    if ($LeftSize -eq 0 -or $RightSize -eq 0) { return $false }
    return $LeftOffset -lt ($RightOffset + $RightSize) -and
        $RightOffset -lt ($LeftOffset + $LeftSize)
}

function Get-LexiQuestCanonicalElfSha256 {
    <#
    .SYNOPSIS
        Hashes an ELF after zeroing its sole GNU build-id descriptor.

    .DESCRIPTION
        This is intentionally fail-closed and dependency-free. It accepts
        little-endian ELF32/ELF64 bytes, requires exactly one non-overlapping
        `.note.gnu.build-id` SHT_NOTE section containing the narrow 20-byte
        NT_GNU_BUILD_ID form emitted by the pinned Android toolchain, verifies
        ET_DYN and the caller-supplied ABI machine, zeroes only the descriptor,
        and returns uppercase SHA-256. Immutable vendor binaries must use raw
        hashes through [Test-LexiQuestNativeLibraryIntegrity].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][UInt16]$ExpectedMachine
    )

    if ($null -eq $Bytes -or $Bytes.Length -lt 16) {
        throw 'Malformed ELF: header is truncated.'
    }
    if (
        $Bytes[0] -ne 0x7f -or
        $Bytes[1] -ne [byte][char]'E' -or
        $Bytes[2] -ne [byte][char]'L' -or
        $Bytes[3] -ne [byte][char]'F'
    ) {
        throw 'Malformed ELF: magic is invalid.'
    }
    $elfClass = [int]$Bytes[4]
    if ($elfClass -ne 1 -and $elfClass -ne 2) {
        throw 'Malformed ELF: unsupported class.'
    }
    if ($Bytes[5] -ne 1) {
        throw 'Malformed ELF: only little-endian data is supported.'
    }
    if ($Bytes[6] -ne 1) {
        throw 'Malformed ELF: unsupported identity version.'
    }
    $elfType = Get-LexiQuestElfUInt16 $Bytes 16 'ELF type'
    $elfMachine = Get-LexiQuestElfUInt16 $Bytes 18 'ELF machine'
    if ($elfType -ne 3) {
        throw 'Malformed ELF: packaged native library must be ET_DYN.'
    }
    if ($elfMachine -ne $ExpectedMachine) {
        throw 'Malformed ELF: native library machine does not match its ABI.'
    }

    if ($elfClass -eq 1) {
        Assert-LexiQuestElfRange $Bytes 0 52 'ELF32 header'
        $headerSize = 52
        $sectionTableOffset64 = [UInt64](
            Get-LexiQuestElfUInt32 $Bytes 32 'section table offset'
        )
        $sectionEntrySize = [int](
            Get-LexiQuestElfUInt16 $Bytes 46 'section entry size'
        )
        $sectionCount = [int](
            Get-LexiQuestElfUInt16 $Bytes 48 'section count'
        )
        $stringTableIndex = [int](
            Get-LexiQuestElfUInt16 $Bytes 50 'section string-table index'
        )
        $minimumSectionSize = 40
    } else {
        Assert-LexiQuestElfRange $Bytes 0 64 'ELF64 header'
        $headerSize = 64
        $sectionTableOffset64 = Get-LexiQuestElfUInt64 $Bytes 40 'section table offset'
        $sectionEntrySize = [int](
            Get-LexiQuestElfUInt16 $Bytes 58 'section entry size'
        )
        $sectionCount = [int](
            Get-LexiQuestElfUInt16 $Bytes 60 'section count'
        )
        $stringTableIndex = [int](
            Get-LexiQuestElfUInt16 $Bytes 62 'section string-table index'
        )
        $minimumSectionSize = 64
    }

    if ($sectionCount -le 0) {
        throw 'Malformed ELF: extended or empty section tables are unsupported.'
    }
    if ($sectionEntrySize -lt $minimumSectionSize) {
        throw 'Malformed ELF: section entry is truncated.'
    }
    if ($stringTableIndex -le 0 -or $stringTableIndex -ge $sectionCount) {
        throw 'Malformed ELF: section string-table index is invalid.'
    }

    $sectionTableOffset = ConvertTo-LexiQuestElfOffset $sectionTableOffset64 'section table offset'
    $sectionTableSize64 = [UInt64]$sectionEntrySize * [UInt64]$sectionCount
    $sectionTableSize = ConvertTo-LexiQuestElfOffset $sectionTableSize64 'section table size'
    Assert-LexiQuestElfRange $Bytes $sectionTableOffset $sectionTableSize 'section table'

    $sections = @()
    for ($index = 0; $index -lt $sectionCount; $index++) {
        $section = Get-LexiQuestElfSection `
            -Bytes $Bytes `
            -SectionTableOffset $sectionTableOffset `
            -SectionEntrySize $sectionEntrySize `
            -Index $index `
            -ElfClass $elfClass
        if ($section.Type -ne 8 -and $section.Size -gt 0) { # SHT_NOBITS has no file bytes.
            Assert-LexiQuestElfRange $Bytes $section.Offset $section.Size 'section data'
        }
        $sections += $section
    }

    $stringTable = $sections[$stringTableIndex]
    if ($stringTable.Type -ne 3 -or $stringTable.Size -le 0) {
        throw 'Malformed ELF: section string table is invalid.'
    }

    $buildIdSections = @()
    foreach ($section in $sections) {
        $section | Add-Member -NotePropertyName Name -NotePropertyValue (
            Get-LexiQuestElfSectionName $Bytes $stringTable $section.NameIndex
        )
        if ($section.Name -eq '.note.gnu.build-id') {
            $buildIdSections += $section
        }
    }
    if ($buildIdSections.Count -ne 1) {
        throw 'Malformed ELF: exactly one .note.gnu.build-id section is required.'
    }

    $buildId = $buildIdSections[0]
    if ($buildId.Type -ne 7) {
        throw 'Malformed ELF: .note.gnu.build-id must be SHT_NOTE.'
    }
    if ($buildId.Offset -lt $headerSize -or $buildId.Size -lt 16) {
        throw 'Malformed ELF: GNU build-id note range is invalid.'
    }
    if (
        Test-LexiQuestElfRangesOverlap `
            $buildId.Offset $buildId.Size $sectionTableOffset $sectionTableSize
    ) {
        throw 'Malformed ELF: GNU build-id overlaps the section table.'
    }
    foreach ($section in $sections) {
        if (
            $section.Index -ne $buildId.Index -and
            $section.Type -ne 8 -and
            (Test-LexiQuestElfRangesOverlap `
                $buildId.Offset $buildId.Size $section.Offset $section.Size)
        ) {
            throw 'Malformed ELF: GNU build-id overlaps another section.'
        }
    }

    $nameSize = Get-LexiQuestElfUInt32 $Bytes $buildId.Offset 'GNU note name size'
    $descriptionSize = Get-LexiQuestElfUInt32 `
        $Bytes ($buildId.Offset + 4) 'GNU build-id size'
    $noteType = Get-LexiQuestElfUInt32 $Bytes ($buildId.Offset + 8) 'GNU note type'
    if ($nameSize -ne 4 -or $descriptionSize -ne 20 -or $noteType -ne 3) {
        throw 'Malformed ELF: GNU build-id note header is invalid.'
    }
    $nameOffset = $buildId.Offset + 12
    Assert-LexiQuestElfRange $Bytes $nameOffset 4 'GNU build-id name'
    if (
        $Bytes[$nameOffset] -ne [byte][char]'G' -or
        $Bytes[$nameOffset + 1] -ne [byte][char]'N' -or
        $Bytes[$nameOffset + 2] -ne [byte][char]'U' -or
        $Bytes[$nameOffset + 3] -ne 0
    ) {
        throw 'Malformed ELF: GNU build-id owner is invalid.'
    }
    $alignedNameSize = ([int]$nameSize + 3) -band (-bnot 3)
    $alignedDescriptionSize = ([int]$descriptionSize + 3) -band (-bnot 3)
    $expectedNoteSize = 12 + $alignedNameSize + $alignedDescriptionSize
    if ($expectedNoteSize -ne $buildId.Size) {
        throw 'Malformed ELF: GNU build-id note has trailing or truncated data.'
    }
    $descriptionOffset = $buildId.Offset + 12 + $alignedNameSize
    Assert-LexiQuestElfRange `
        $Bytes $descriptionOffset ([int]$descriptionSize) 'GNU build-id descriptor'

    $canonical = New-Object byte[] $Bytes.Length
    [Array]::Copy($Bytes, $canonical, $Bytes.Length)
    [Array]::Clear($canonical, $descriptionOffset, [int]$descriptionSize)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash($canonical)
        return ([BitConverter]::ToString($hash)).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Get-LexiQuestRawSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($Bytes))).Replace('-', '')
    } finally {
        $sha256.Dispose()
    }
}

function Find-LexiQuestExactDictionaryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Dictionary,
        [Parameter(Mandatory = $true)][string]$Key
    )

    $found = $false
    $value = $null
    foreach ($candidate in $Dictionary.Keys) {
        if (-not [string]::Equals(
            [string]$candidate,
            $Key,
            [StringComparison]::Ordinal
        )) {
            continue
        }
        if ($found) {
            throw "Duplicate exact dictionary key: $Key"
        }
        $found = $true
        $value = $Dictionary[$candidate]
    }
    return [pscustomobject]@{
        Found = $found
        Value = $value
    }
}

function Read-LexiQuestNativeLibraryBytes {
    <#
    .SYNOPSIS
        Reads the exact model-runtime entries from an opened APK archive.

    .DESCRIPTION
        ZIP paths are case-sensitive. The ordinal dictionary deliberately keeps
        case variants distinct, and duplicate exact entry names fail before any
        entry can be collapsed or selected for integrity verification.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Archive)

    $runtimeLibraryBytes =
        [System.Collections.Generic.Dictionary[string, byte[]]]::new(
            [StringComparer]::Ordinal
        )
    foreach ($entry in $Archive.Entries) {
        if (
            $entry.FullName -cnotmatch (
                '^lib/[^/]+/(libLiteRt.*|libtensorflowlite.*|' +
                'libtflite.*)\.so$'
            )
        ) {
            continue
        }
        if ($runtimeLibraryBytes.ContainsKey($entry.FullName)) {
            throw "Duplicate model runtime library: $($entry.FullName)"
        }
        $stream = $entry.Open()
        $memory = New-Object System.IO.MemoryStream
        try {
            $stream.CopyTo($memory)
            $runtimeLibraryBytes.Add(
                $entry.FullName,
                [byte[]]$memory.ToArray()
            )
        } finally {
            $memory.Dispose()
            $stream.Dispose()
        }
    }
    return ,$runtimeLibraryBytes
}

function Test-LexiQuestNativeLibraryIntegrity {
    <#
    .SYNOPSIS
        Applies the raw-vendor/canonical-local integrity policy to one APK entry.

    .DESCRIPTION
        Only the three exact local custom-op ABI entries use canonical ELF
        hashing. Every other allowlisted entry remains raw SHA-256 pinned.
        Missing mode pins, unexpected custom-op ABIs, malformed ELFs, and
        ambiguous raw/canonical maps throw without a raw fallback.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Release')]
        [string]$BuildMode,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ExpectedRawSha256ByEntry,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ExpectedCanonicalSha256ByMode
    )

    $customMachines =
        [System.Collections.Generic.Dictionary[string, UInt16]]::new(
            [StringComparer]::Ordinal
        )
    $customMachines.Add('lib/arm64-v8a/libtflite_custom_ops.so', [UInt16]183)
    $customMachines.Add('lib/armeabi-v7a/libtflite_custom_ops.so', [UInt16]40)
    $customMachines.Add('lib/x86_64/libtflite_custom_ops.so', [UInt16]62)
    $customSuffix = '/libtflite_custom_ops.so'
    $isCustom = $EntryName.EndsWith(
        $customSuffix,
        [StringComparison]::Ordinal
    )

    if ($isCustom) {
        if (-not $customMachines.ContainsKey($EntryName)) {
            throw "Unexpected custom-op ABI entry: $EntryName"
        }
        $rawPin = Find-LexiQuestExactDictionaryEntry `
            -Dictionary $ExpectedRawSha256ByEntry `
            -Key $EntryName
        if ($rawPin.Found) {
            throw "Ambiguous raw/canonical integrity policy: $EntryName"
        }
        if (-not $ExpectedCanonicalSha256ByMode.Contains($BuildMode)) {
            throw "Missing canonical integrity mode: $BuildMode"
        }
        $modePins = $ExpectedCanonicalSha256ByMode[$BuildMode]
        if ($null -eq $modePins -or -not ($modePins -is [System.Collections.IDictionary])) {
            throw "Invalid canonical integrity mode: $BuildMode"
        }
        $canonicalPin = Find-LexiQuestExactDictionaryEntry `
            -Dictionary $modePins `
            -Key $EntryName
        if (-not $canonicalPin.Found) {
            throw "Missing canonical custom-op pin: $BuildMode/$EntryName"
        }
        $actual = Get-LexiQuestCanonicalElfSha256 `
            -Bytes $Bytes `
            -ExpectedMachine $customMachines[$EntryName]
        $expected = [string]$canonicalPin.Value
        return [pscustomobject]@{
            EntryName = $EntryName
            Policy = 'canonical-gnu-build-id-descriptor'
            ExpectedSha256 = $expected
            ActualSha256 = $actual
            Matches = $actual -ceq $expected
        }
    }

    $rawPin = Find-LexiQuestExactDictionaryEntry `
        -Dictionary $ExpectedRawSha256ByEntry `
        -Key $EntryName
    if (-not $rawPin.Found) {
        throw "Missing raw vendor pin: $EntryName"
    }
    $rawActual = Get-LexiQuestRawSha256 -Bytes $Bytes
    $rawExpected = [string]$rawPin.Value
    return [pscustomobject]@{
        EntryName = $EntryName
        Policy = 'raw'
        ExpectedSha256 = $rawExpected
        ActualSha256 = $rawActual
        Matches = $rawActual -ceq $rawExpected
    }
}

function Assert-LexiQuestNativeLibrarySetIntegrity {
    <#
    .SYNOPSIS
        Verifies every expected APK runtime entry and rejects every extra one.

    .DESCRIPTION
        This is the single set-level policy used by the APK verifier. Each
        expected entry is passed through
        [Test-LexiQuestNativeLibraryIntegrity], and any mismatch throws.
        Missing, unexpected, malformed, ambiguous, and mode-crossed inputs are
        fail-closed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$LibraryBytesByEntry,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Debug', 'Release')]
        [string]$BuildMode,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ExpectedRawSha256ByEntry,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$ExpectedCanonicalSha256ByMode
    )

    if (-not $ExpectedCanonicalSha256ByMode.Contains($BuildMode)) {
        throw "Missing canonical integrity mode: $BuildMode"
    }
    $modePins = $ExpectedCanonicalSha256ByMode[$BuildMode]
    if ($null -eq $modePins -or -not ($modePins -is [System.Collections.IDictionary])) {
        throw "Invalid canonical integrity mode: $BuildMode"
    }

    $expectedNames = @($ExpectedRawSha256ByEntry.Keys) + @($modePins.Keys)
    foreach ($entryName in $expectedNames) {
        $libraryEntry = Find-LexiQuestExactDictionaryEntry `
            -Dictionary $LibraryBytesByEntry `
            -Key ([string]$entryName)
        if (-not $libraryEntry.Found) {
            throw "Required model runtime library is missing: $entryName"
        }
        $bytes = $libraryEntry.Value
        if (-not ($bytes -is [byte[]])) {
            throw "Model runtime library bytes are invalid: $entryName"
        }
        $integrity = Test-LexiQuestNativeLibraryIntegrity `
            -EntryName $entryName `
            -Bytes $bytes `
            -BuildMode $BuildMode `
            -ExpectedRawSha256ByEntry $ExpectedRawSha256ByEntry `
            -ExpectedCanonicalSha256ByMode $ExpectedCanonicalSha256ByMode
        if (-not $integrity.Matches) {
            throw (
                'Packaged native checksum mismatch for {0}. Expected {1}, got {2}.' -f
                $entryName,
                $integrity.ExpectedSha256,
                $integrity.ActualSha256
            )
        }
    }

    foreach ($entryName in $LibraryBytesByEntry.Keys) {
        $rawPin = Find-LexiQuestExactDictionaryEntry `
            -Dictionary $ExpectedRawSha256ByEntry `
            -Key ([string]$entryName)
        $canonicalPin = Find-LexiQuestExactDictionaryEntry `
            -Dictionary $modePins `
            -Key ([string]$entryName)
        if (-not $rawPin.Found -and -not $canonicalPin.Found) {
            throw "Unexpected model runtime library or ABI: $entryName"
        }
    }
}

$ErrorActionPreference='Stop'
$failed=$false
& "$PSScriptRoot/device-run-gate.ps1" -SourceCommit '1875a61854490e0493cc084bffb705f5d3bd4b0b' -CheckoutCommit '788e90e62b1694c20945734787723c168b6a6ab2' -SourceFingerprint '50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc' -Label 'media-focused-host-diagnosis' -Executable 'flutter' -ArgumentList @('test','-d','flutter-tester','--no-pub','integration_test/field_trial_media_smoke_test.dart','--reporter','expanded')
if ($LASTEXITCODE -ne 0) { $failed=$true }
& "$PSScriptRoot/device-run-gate.ps1" -SourceCommit '1875a61854490e0493cc084bffb705f5d3bd4b0b' -CheckoutCommit '788e90e62b1694c20945734787723c168b6a6ab2' -SourceFingerprint '50ddab9318080e5dd7cd4b640cfb63dbbf52fb9613d7d61fa8064a59132d22fc' -Label 'temporary-protocol-focused-host-diagnosis' -Executable 'flutter' -ArgumentList @('test','--no-pub','test/features/learning/pair_matching/pair_configured_disposition_test.dart','--plain-name','temporary protocol unavailability keeps exact saved-session retry','--reporter','expanded')
if ($LASTEXITCODE -ne 0) { $failed=$true }
if ($failed) { exit 1 }

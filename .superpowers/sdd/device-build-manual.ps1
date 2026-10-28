param([ValidatePattern('^[a-z0-9-]+$')][string]$Stem='manual-ui-v3')
& "$PSScriptRoot/device-current-source-gate.ps1" -Label "$Stem-build" -Executable 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat' -ArgumentList @('build','apk','--debug','--no-pub','--target-platform','android-arm64','--target','.superpowers/sdd/device-manual-uat.dart','--dart-define=LEXIQUEST_VERSION=1.0.0+14',"--dart-define=LEXIQUEST_BUILD_ID=$Stem")
exit $LASTEXITCODE

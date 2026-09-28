$ErrorActionPreference='Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$manifestPath = Join-Path $root 'android/app/src/nativeBaseline/AndroidManifest.xml'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'RED: isolated native manifest missing' }
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$ns = @{android='http://schemas.android.com/apk/res/android';tools='http://schemas.android.com/tools'}
foreach ($permission in @('INTERNET','ACCESS_NETWORK_STATE','CAMERA','RECORD_AUDIO','POST_NOTIFICATIONS','RECEIVE_BOOT_COMPLETED')) {
    $node = Select-Xml -Xml $manifest -Namespace $ns -XPath "//uses-permission[@android:name='android.permission.$permission'][@tools:node='remove']"
    if (-not $node) { throw "Permission not removed: $permission" }
}
if (@(Select-Xml -Xml $manifest -Namespace $ns -XPath '//application/activity[not(starts-with(@tools:node,"remove"))]').Count -ne 1) { throw 'Expected one harness activity' }
if ((Get-Content $manifestPath -Raw) -notmatch 'FirebaseInitProvider.+tools:node="remove"') { throw 'Firebase startup provider enabled' }
$gradle = Get-Content (Join-Path $root 'android/app/build.gradle.kts') -Raw
foreach ($required in @('nativeBaselineTest','nativeBaselineBm','src/nativeBaseline/AndroidManifest.xml','src/nativeBaseline/kotlin')) {
    if (-not $gradle.Contains($required)) { throw "Missing isolated Gradle setting: $required" }
}
Write-Output 'PASS: native isolation source contract (merged APK inspection still required)'

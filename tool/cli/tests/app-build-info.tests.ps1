$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$fixture=Join-Path $root ('build/build-info-'+[guid]::NewGuid().ToString('N')+'.dart')
[IO.File]::WriteAllText($fixture, @'
import '../lib/runtime/app_build_info.dart';
void main() {
  const info = AppBuildInfo.fromEnvironment();
  if (info.version != '9.8.7+654' || info.buildId != 'injected-build') {
    throw StateError('Explicit build identity was not preserved');
  }
  print('PASS: explicit dart-define version and build id');
}
'@, [Text.UTF8Encoding]::new($false))
& dart '-DLEXIQUEST_VERSION=9.8.7+654' '-DLEXIQUEST_BUILD_ID=injected-build' $fixture
if($LASTEXITCODE -ne 0){throw 'Build identity define contract failed'}

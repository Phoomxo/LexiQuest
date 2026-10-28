/// Immutable, non-sensitive build identity injected through `--dart-define`.
///
/// Only public version/build metadata lives here. It never carries server
/// credentials, provider keys, or anything that must stay out of the bundle.
final class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildId});

  final String version;
  final String buildId;

  const AppBuildInfo.fromEnvironment()
    : version = const String.fromEnvironment(
        'LEXIQUEST_VERSION',
        defaultValue: '1.0.0+1',
      ),
      buildId = const String.fromEnvironment(
        'LEXIQUEST_BUILD_ID',
        defaultValue: 'development',
      );

  @override
  String toString() => 'AppBuildInfo';
}

import 'dart:developer' as developer;
import 'dart:io';

Future<void> writeAutonomousServiceReceipt() async {
  if (const bool.fromEnvironment('AUTONOMOUS_DEVICE_VIEWPORT')) {
    // Some physical devices redact the discovery URL from logcat. Keep the
    // authenticated endpoint in this test package's private cache instead.
    final service = await developer.Service.getInfo();
    final uri = service.serverUri;
    if (uri == null || !uri.hasPort) {
      throw StateError(
        'Autonomous fixture requires an authenticated VM service.',
      );
    }
    await File(
      '${Directory.systemTemp.path}/autonomous-vm-service.txt',
    ).writeAsString(uri.toString(), flush: true);
  }
}

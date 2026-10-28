import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final raw = Platform.environment['LEXIQUEST_DEVICE_RESPONSE_PATH'];
  if (raw == null || raw.isEmpty)
    throw StateError('Explicit response path required');
  final destination = File(raw).absolute;
  if (await destination.exists())
    throw StateError('Preserve existing response evidence');
  if (!await destination.parent.exists())
    throw StateError('Evidence parent must exist');
  final written = <Map<String, Object?>>[];
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) {
        throw StateError('Unsafe screenshot name');
      }
      const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 8 ||
          bytes.length > 20000000 ||
          !List.generate(
            8,
            (i) => bytes[i] == signature[i],
          ).every((same) => same)) {
        throw StateError('Screenshot is not a bounded PNG');
      }
      final file = File(
        '${destination.parent.path}${Platform.pathSeparator}$name.png',
      );
      if (await file.exists()) throw StateError('Preserve existing screenshot');
      await file.writeAsBytes(bytes, flush: true);
      written.add({'name': name, 'path': file.path, 'bytes': bytes.length});
      // Successful PNG persistence is not a visual-appearance acceptance claim.
      return true;
    },
    responseDataCallback: (data) async {
      final payload = Map<String, dynamic>.from(data ?? <String, dynamic>{});
      payload.remove('screenshots');
      payload['screenshotFiles'] = written;
      await destination.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'capturedUtc': DateTime.now().toUtc().toIso8601String(),
          'fixture': '.superpowers/sdd/device-autonomous-ui-suite.dart',
          'responseData': payload,
        }),
        flush: true,
      );
    },
  ).timeout(const Duration(minutes: 15));
}

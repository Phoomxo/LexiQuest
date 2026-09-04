import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

const _outputEnvironmentKey = 'LEXIQUEST_ADVENTURE_PERFORMANCE_DRIVER_OUTPUT';

Future<void> main() => integrationDriver(
  writeResponseOnFailure: true,
  responseDataCallback: (data) async {
    final configuredPath = Platform.environment[_outputEnvironmentKey];
    if (configuredPath == null || configuredPath.trim().isEmpty) {
      throw StateError('$_outputEnvironmentKey must select an output file.');
    }

    final allowedRoot = Directory(
      'build${Platform.pathSeparator}adventure-performance',
    ).absolute.path;
    final output = File(configuredPath).absolute;
    final comparisonRoot = Platform.isWindows
        ? allowedRoot.toLowerCase()
        : allowedRoot;
    final comparisonPath = Platform.isWindows
        ? output.path.toLowerCase()
        : output.path;
    final allowedPrefix = '$comparisonRoot${Platform.pathSeparator}';
    if (!comparisonPath.startsWith(allowedPrefix)) {
      throw StateError(
        'Adventure performance output must stay under $allowedRoot.',
      );
    }

    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  },
);

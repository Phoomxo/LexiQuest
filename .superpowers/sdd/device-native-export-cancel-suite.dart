import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

const _case =
    'native export document picker cancellation returns typed cancelled';
const _runnerMarker = 'lexiquest-autonomous-export-cancel-run-owned.json';
const _fixtureMarker = 'lexiquest-native-export-cancel-owned.json';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  String? runId;
  Map<String, Object?> outcome = {'status': 'not_run'};

  void publishReport() {
    binding.reportData = {
      'schemaVersion': 1,
      'suite': 'native-export-cancel-v1',
      'runId': runId,
      'outcome': outcome,
      // This integration fixture is outside the conventional test/ directory.
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
  }

  testWidgets(_case, (tester) async {
    File? marker;
    var markerCreated = false;
    Future<void> writePhase(String phase) async {
      await marker!.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'runId': runId,
          'phase': phase,
          'syntheticOnly': true,
        }),
        flush: true,
      );
    }

    try {
      expect(Platform.isAndroid, isTrue);
      final directory = Directory.systemTemp;
      expect(
        await directory.resolveSymbolicLinks(),
        await Directory(
          '/data/user/0/com.lexiquest.app/code_cache',
        ).resolveSymbolicLinks(),
      );
      final ownerFile = File('${directory.path}/$_runnerMarker');
      expect(await ownerFile.length(), lessThanOrEqualTo(2048));
      final owner = jsonDecode(await ownerFile.readAsString());
      expect(owner, isA<Map<String, dynamic>>());
      expect(owner['kind'], 'export-cancel');
      runId = owner['runId'] as String;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(runId!),
        isTrue,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Text('Synthetic native export cancellation check'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      marker = File('${directory.path}/$_fixtureMarker');
      await marker.create(exclusive: true);
      markerCreated = true;
      await writePhase('ready-to-open');
      final hostReady = File(
        '${directory.path}/lexiquest-native-export-cancel-host-ready.json',
      );
      final wait = Stopwatch()..start();
      Map<String, dynamic>? ready;
      while (wait.elapsed < const Duration(seconds: 45)) {
        if (await hostReady.exists() && await hostReady.length() <= 2048) {
          try {
            ready =
                jsonDecode(await hostReady.readAsString())
                    as Map<String, dynamic>;
            break;
          } on FormatException {
            /* Host may be between create and flush. */
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready, {'schemaVersion': 1, 'runId': runId, 'openPicker': true});
      final artifact = ExportArtifact(
        format: ExportFormat.csv,
        suggestedFileName: 'lexiquest-synthetic-cancel-$runId.csv',
        mimeType: 'text/csv',
        bytes: Uint8List.fromList(
          utf8.encode('synthetic,value\nfixture,cancel-only\n'),
        ),
        recordCount: 1,
        schemaVersion: 1,
        algorithmVersion: 1,
        generatedAtUtc: DateTime.utc(2026, 9, 8),
        timeZone: 'UTC',
        exclusions: const [],
      );
      final cancellation = ExportCancellation();
      await writePhase('awaiting-picker');
      // Real production store, platform channel and ACTION_CREATE_DOCUMENT.
      // The host observes the owned marker and resolved DocumentsUI, then
      // dispatches one Back. No token cancellation or saver fake is used.
      var typedCancelled = false;
      try {
        await const FileSelectorExportStore()
            .save(artifact, cancellation: cancellation)
            .timeout(const Duration(seconds: 90));
        fail('Native export unexpectedly returned a saved destination.');
      } on ExportException catch (error) {
        expect(error.code, ExportFailureCode.cancelled);
        typedCancelled = true;
      }
      expect(typedCancelled, isTrue);
      expect(cancellation.isCancelled, isFalse);
      outcome = {
        'status': 'cancelled',
        'syntheticOnly': true,
        'productionStore': true,
        'tokenCancelled': false,
        'saveReturned': false,
      };
      await writePhase('cancelled');
      publishReport();
      print('NATIVE_EXPORT_CANCEL_RESULT ${jsonEncode(outcome)}');
    } catch (error) {
      outcome = {'status': 'failed', 'errorType': error.runtimeType.toString()};
      if (markerCreated) await writePhase('failed');
      publishReport();
      rethrow;
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('DEVICE_NATIVE_EXPORT_CANCEL_FINAL_SENTINEL', (tester) async {
    publishReport();
    expect(outcome['status'], 'cancelled');
    print(
      'NATIVE_EXPORT_CANCEL_FINAL_REPORT ${jsonEncode(binding.reportData)}',
    );
  });
  unawaited(_publishService());
}

Future<void> _publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1') {
    throw StateError('Local VM service unavailable');
  }
  final file = File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  );
  await file.create(exclusive: true);
  await file.writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}

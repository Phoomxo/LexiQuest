import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/export');
  const fileSelectorChannel = MethodChannel('plugins.flutter.io/file_selector');
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(fileSelectorChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
  });

  final artifact = ExportArtifact(
    format: ExportFormat.csv,
    suggestedFileName: 'lexiquest.csv',
    mimeType: 'text/csv',
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
    recordCount: 1,
    schemaVersion: 1,
    algorithmVersion: 1,
    generatedAtUtc: DateTime.utc(2026, 7, 30),
    timeZone: 'UTC',
    exclusions: <String>[],
  );

  test('Android validates after selection before sending bytes', () async {
    final calls = <String>[];
    var validations = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          final arguments = call.arguments as Map<Object?, Object?>;
          if (call.method == 'selectExportDestination') {
            expect(arguments, isNot(contains('bytes')));
            return <String, String>{
              'destination': 'content://downloads/lexiquest.csv',
              'selectionToken': 'selection-1',
            };
          }
          if (call.method == 'writeExportFile') {
            expect(
              arguments['destination'],
              'content://downloads/lexiquest.csv',
            );
            expect(arguments['selectionToken'], 'selection-1');
            expect(arguments['bytes'], artifact.bytes);
            return null;
          }
          fail('Unexpected method ${call.method}');
        });
    const store = FileSelectorExportStore(isAndroid: true);

    final result = await store.save(
      artifact,
      cancellation: ExportCancellation(),
      revalidateBeforeWrite: () async {
        validations += 1;
        expect(calls, ['selectExportDestination']);
      },
    );

    expect(validations, 1);
    expect(calls, ['selectExportDestination', 'writeExportFile']);
    expect(result.path, 'content://downloads/lexiquest.csv');
  });

  test('Android document picker cancellation is typed', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    const store = FileSelectorExportStore(isAndroid: true);

    await expectLater(
      store.save(
        artifact,
        cancellation: ExportCancellation(),
        revalidateBeforeWrite: () async {},
      ),
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.cancelled,
        ),
      ),
    );
  });

  test(
    'desktop validates after dialog and immediately before external write',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-export-',
      );
      try {
        final target = File(
          '${directory.path}${Platform.pathSeparator}saved.csv',
        );
        final partial = File(
          '${directory.path}${Platform.pathSeparator}lexiquest.csv.partial',
        );
        var dialogReturned = false;
        var validations = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(fileSelectorChannel, (call) async {
          expect(call.method, 'getSavePath');
          expect(await target.exists(), isFalse);
          dialogReturned = true;
          return target.path;
        });
        messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
          expect(call.method, 'getTemporaryDirectory');
          return directory.path;
        });
        const store = FileSelectorExportStore(isAndroid: false);

        final result = await store.save(
          artifact,
          cancellation: ExportCancellation(),
          revalidateBeforeWrite: () async {
            validations += 1;
            expect(dialogReturned, isTrue);
            expect(await target.exists(), isFalse);
            expect(await partial.exists(), validations == 2);
          },
        );

        expect(validations, 2);
        expect(result.path, target.path);
        expect(await target.readAsBytes(), artifact.bytes);
        expect(await partial.exists(), isFalse);
      } finally {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );

  test(
    'cancellation while Android picker is open discards without writing',
    () async {
      final pickerOpened = Completer<void>();
      final destination = Completer<Object?>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'selectExportDestination') {
              pickerOpened.complete();
              return destination.future;
            }
            if (call.method == 'discardExportDestination') {
              final arguments = call.arguments as Map<Object?, Object?>;
              expect(arguments['selectionToken'], 'selection-1');
              return null;
            }
            fail('Unexpected method ${call.method}');
          });
      const store = FileSelectorExportStore(isAndroid: true);
      final cancellation = ExportCancellation();
      var validations = 0;

      final pending = store.save(
        artifact,
        cancellation: cancellation,
        revalidateBeforeWrite: () async => validations += 1,
      );
      await pickerOpened.future;
      cancellation.cancel();
      destination.complete(<String, String>{
        'destination': 'content://downloads/lexiquest.csv',
        'selectionToken': 'selection-1',
      });

      await expectLater(
        pending,
        throwsA(
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(validations, 0);
      expect(calls, ['selectExportDestination', 'discardExportDestination']);
    },
  );

  test('Android rejects an incomplete destination capability', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => <String, String>{
            'destination': 'content://downloads/lexiquest.csv',
            'selectionToken': '',
          },
        );
    const store = FileSelectorExportStore(isAndroid: true);

    await expectLater(
      store.save(
        artifact,
        cancellation: ExportCancellation(),
        revalidateBeforeWrite: () async {},
      ),
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.unavailable,
        ),
      ),
    );
  });

  test('failed revalidation after Android picker never sends bytes', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'selectExportDestination') {
            return <String, String>{
              'destination': 'content://downloads/lexiquest.csv',
              'selectionToken': 'selection-1',
            };
          }
          if (call.method == 'discardExportDestination') {
            final arguments = call.arguments as Map<Object?, Object?>;
            expect(arguments['selectionToken'], 'selection-1');
            return null;
          }
          fail('Unexpected method ${call.method}');
        });
    const store = FileSelectorExportStore(isAndroid: true);

    await expectLater(
      store.save(
        artifact,
        cancellation: ExportCancellation(),
        revalidateBeforeWrite: () async =>
            throw const ExportException(ExportFailureCode.consentRequired),
      ),
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.consentRequired,
        ),
      ),
    );
    expect(calls, ['selectExportDestination', 'discardExportDestination']);
  });

  test(
    'cancellation after Android write starts does not report false cancel',
    () async {
      final cancellation = ExportCancellation();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'selectExportDestination') {
              return <String, String>{
                'destination': 'content://downloads/lexiquest.csv',
                'selectionToken': 'selection-1',
              };
            }
            if (call.method == 'writeExportFile') {
              cancellation.cancel();
              return null;
            }
            fail('Unexpected method ${call.method}');
          });
      const store = FileSelectorExportStore(isAndroid: true);

      final result = await store.save(
        artifact,
        cancellation: cancellation,
        revalidateBeforeWrite: () async {},
      );

      expect(result.bytesWritten, artifact.bytes.length);
      expect(calls, ['selectExportDestination', 'writeExportFile']);
    },
  );

  test(
    'Android platform write errors are mapped without leaking details',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'selectExportDestination') {
              return <String, String>{
                'destination': 'content://downloads/lexiquest.csv',
                'selectionToken': 'selection-1',
              };
            }
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'private path sentinel',
            );
          });
      const store = FileSelectorExportStore(isAndroid: true);

      await expectLater(
        store.save(
          artifact,
          cancellation: ExportCancellation(),
          revalidateBeforeWrite: () async {},
        ),
        throwsA(
          isA<ExportException>()
              .having(
                (error) => error.code,
                'code',
                ExportFailureCode.permissionDenied,
              )
              .having(
                (error) => error.toString(),
                'safe toString',
                isNot(contains('private path sentinel')),
              ),
        ),
      );
    },
  );
}

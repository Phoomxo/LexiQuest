import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'Android byte limit rejects before saver or channel allocation',
    () async {
      var called = false;
      final large = ExportArtifact(
        format: artifact.format,
        suggestedFileName: artifact.suggestedFileName,
        mimeType: artifact.mimeType,
        bytes: Uint8List(16 * 1024 * 1024 + 1),
        recordCount: 1,
        schemaVersion: 1,
        algorithmVersion: 1,
        generatedAtUtc: artifact.generatedAtUtc,
        timeZone: 'UTC',
        exclusions: [],
      );
      final store = FileSelectorExportStore(
        isAndroid: true,
        androidSaver: (_) async {
          called = true;
          return 'content://test/large';
        },
      );
      await expectLater(
        store.save(large, cancellation: ExportCancellation()),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
      expect(called, isFalse);
    },
  );

  for (final error in [
    StateError('private-picker'),
    PlatformException(code: 'UNAVAILABLE'),
  ]) {
    test(
      'AD desktop picker failure is typed before staging (${error.runtimeType})',
      () async {
        var staging = 0;
        var writes = 0;
        final store = FileSelectorExportStore(
          isAndroid: false,
          desktopLocation: (_) async => throw error,
          temporaryDirectory: () async {
            staging++;
            return Directory.systemTemp;
          },
          desktopSaver: (_, _) async {
            writes++;
          },
        );
        await expectLater(
          store.save(artifact, cancellation: ExportCancellation()),
          throwsA(
            isA<ExportException>().having(
              (e) => e.code,
              'code',
              ExportFailureCode.unavailable,
            ),
          ),
        );
        expect(staging, 0);
        expect(writes, 0);
      },
    );
  }

  test(
    'Android cancellation reaches pending native write and maps CANCELLED',
    () async {
      const channel = MethodChannel('com.lexiquest.app/export');
      final pending = Completer<String?>();
      final cancellation = ExportCancellation();
      String? operation;
      var cancels = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'saveExportFile') {
              operation = (call.arguments as Map)['operationId'] as String?;
              return pending.future;
            }
            if (call.method == 'cancelExportFile') {
              expect((call.arguments as Map)['operationId'], operation);
              cancels++;
              pending.completeError(PlatformException(code: 'CANCELLED'));
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final result = const FileSelectorExportStore(
        isAndroid: true,
      ).save(artifact, cancellation: cancellation);
      final expectation = expectLater(
        result,
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      cancellation.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (!pending.isCompleted) {
        pending.completeError(PlatformException(code: 'CANCELLED'));
      }
      await expectation;
      expect(operation, isNotNull);
      expect(cancels, 1);
    },
  );

  test(
    'Android cancellation discards completed document before reporting cancelled',
    () async {
      final cancellation = ExportCancellation();
      String? discarded;
      final store = FileSelectorExportStore(
        isAndroid: true,
        androidSaver: (_) async {
          cancellation.cancel();
          return 'content://downloads/own-export';
        },
        androidDiscarder: (path) async => discarded = path,
      );
      await expectLater(
        store.save(artifact, cancellation: cancellation),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(discarded, 'content://downloads/own-export');
    },
  );

  test(
    'failed Android cleanup must not claim successful cancellation',
    () async {
      final cancellation = ExportCancellation();
      final store = FileSelectorExportStore(
        isAndroid: true,
        androidSaver: (_) async {
          cancellation.cancel();
          return 'content://downloads/own-export';
        },
        androidDiscarder: (_) async =>
            throw const FileSystemException('cleanup denied'),
      );
      await expectLater(
        store.save(artifact, cancellation: cancellation),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.cleanupFailed,
          ),
        ),
      );
    },
  );

  for (final existing in [false, true]) {
    test(
      'desktop cancelled write restores destination (existing=$existing) and clears staging',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'lexiquest-export-cancel-',
        );
        addTearDown(() => root.delete(recursive: true));
        final target = File('${root.path}/result.csv');
        if (existing) await target.writeAsString('previous-file');
        final cancellation = ExportCancellation();
        final store = FileSelectorExportStore(
          isAndroid: false,
          desktopLocation: (_) async => target.path,
          temporaryDirectory: () async => root,
          desktopSaver: (source, destination) async {
            await File(source).copy(destination);
            cancellation.cancel();
          },
        );
        await expectLater(
          store.save(artifact, cancellation: cancellation),
          throwsA(
            isA<ExportException>().having(
              (e) => e.code,
              'code',
              ExportFailureCode.cancelled,
            ),
          ),
        );
        expect(await target.exists(), existing);
        if (existing) expect(await target.readAsString(), 'previous-file');
        expect(
          await root.list().where((e) => e is Directory).toList(),
          isEmpty,
        );
      },
    );
  }

  test(
    'failed rollback preserves previous bytes for recovery and reports cleanup failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lexiquest-export-recovery-',
      );
      addTearDown(() => root.delete(recursive: true));
      final target = File('${root.path}/result.csv');
      await target.writeAsString('previous-file');
      final store = FileSelectorExportStore(
        isAndroid: false,
        desktopLocation: (_) async => target.path,
        temporaryDirectory: () async => root,
        desktopSaver: (_, destination) async {
          await File(destination).delete();
          await Directory(destination).create();
          throw const FileSystemException('destination became unavailable');
        },
      );
      await expectLater(
        store.save(artifact, cancellation: ExportCancellation()),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.cleanupFailed,
          ),
        ),
      );
      final backups = await root
          .list(recursive: true)
          .where((e) => e is File && e.path.endsWith('previous'))
          .cast<File>()
          .toList();
      expect(backups, hasLength(1));
      expect(await backups.single.readAsString(), 'previous-file');
    },
  );

  test('Android saver writes through the system document flow', () async {
    ExportArtifact? received;
    final store = FileSelectorExportStore(
      isAndroid: true,
      androidSaver: (value) async {
        received = value;
        return 'content://downloads/lexiquest.csv';
      },
    );

    final result = await store.save(
      artifact,
      cancellation: ExportCancellation(),
    );

    expect(received, same(artifact));
    expect(result.path, 'content://downloads/lexiquest.csv');
    expect(result.bytesWritten, 3);
  });

  test(
    'desktop same destination is serialized and successful export leaves no staging',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lexiquest-export-overlap-',
      );
      addTearDown(() => root.delete(recursive: true));
      final started = Completer<void>();
      final release = Completer<void>();
      final target = File('${root.path}/result.csv');
      final store = FileSelectorExportStore(
        isAndroid: false,
        desktopLocation: (_) async => target.path,
        temporaryDirectory: () async => root,
        desktopSaver: (source, destination) async {
          started.complete();
          await release.future;
          await File(source).copy(destination);
        },
      );
      final first = store.save(artifact, cancellation: ExportCancellation());
      await started.future;
      await expectLater(
        store.save(artifact, cancellation: ExportCancellation()),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        ),
      );
      release.complete();
      expect((await first).bytesWritten, 3);
      expect(await target.readAsBytes(), [1, 2, 3]);
      expect(await root.list().toList(), hasLength(1));
    },
  );

  test(
    'real Android channel acknowledges discard after cancellation',
    () async {
      const channel = MethodChannel('com.lexiquest.app/export');
      final cancellation = ExportCancellation();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'saveExportFile') {
              cancellation.cancel();
              return 'content://synthetic/own-export';
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await expectLater(
        const FileSelectorExportStore(
          isAndroid: true,
        ).save(artifact, cancellation: cancellation),
        throwsA(
          isA<ExportException>().having(
            (e) => e.code,
            'code',
            ExportFailureCode.cancelled,
          ),
        ),
      );
      expect(calls.map((c) => c.method), [
        'saveExportFile',
        'finishExportFile',
      ]);
      expect(calls.last.arguments, {
        'location': 'content://synthetic/own-export',
        'discard': true,
      });
    },
  );

  test('Android document picker cancellation is typed', () async {
    final store = FileSelectorExportStore(
      isAndroid: true,
      androidSaver: (_) async => null,
    );

    await expectLater(
      store.save(artifact, cancellation: ExportCancellation()),
      throwsA(
        isA<ExportException>().having(
          (error) => error.code,
          'code',
          ExportFailureCode.cancelled,
        ),
      ),
    );
  });

  test('Android platform write errors are mapped without leaking details', () {
    final store = FileSelectorExportStore(
      isAndroid: true,
      androidSaver: (_) async => throw PlatformException(
        code: 'PERMISSION_DENIED',
        message: 'private path sentinel',
      ),
    );

    expectLater(
      store.save(artifact, cancellation: ExportCancellation()),
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
  });
}

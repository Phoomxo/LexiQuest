import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

void main() {
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

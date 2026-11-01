import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.lexiquest.app/export');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 1]);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'image save preserves explicit picker and owner validation before PNG bytes',
    () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        final data = call.arguments as Map;
        if (call.method == 'selectExportDestination') {
          expect(data, {
            'suggestedName': 'lexiquest-achievement.png',
            'mimeType': 'image/png',
          });
          return {
            'destination': 'content://synthetic/image',
            'selectionToken': 'synthetic-choice',
          };
        }
        expect(methods, [
          'selectExportDestination',
          'validated',
          'writeExportFile',
        ]);
        expect(data['bytes'], png);
        expect(data['selectionToken'], 'synthetic-choice');
        return null;
      });
      final result = await const FileSelectorExportStore(isAndroid: true)
          .saveImage(
            pngBytes: png,
            cancellation: ExportCancellation(),
            revalidateBeforeWrite: () async {
              methods.add('validated');
            },
          );
      expect(result.bytesWritten, png.length);
    },
  );

  test(
    'changed owner after picker discards destination without writing',
    () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return call.method == 'selectExportDestination'
            ? {
                'destination': 'content://synthetic/image',
                'selectionToken': 'synthetic-choice',
              }
            : null;
      });
      await expectLater(
        const FileSelectorExportStore(isAndroid: true).saveImage(
          pngBytes: png,
          cancellation: ExportCancellation(),
          revalidateBeforeWrite: () async {
            throw const ExportException(ExportFailureCode.cancelled);
          },
        ),
        throwsA(isA<ExportException>()),
      );
      expect(methods, ['selectExportDestination', 'discardExportDestination']);
    },
  );

  test('invalid signature and oversized image fail before the picker', () {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return null;
    });
    for (final bytes in [
      Uint8List(0),
      Uint8List(9),
      Uint8List(2 * 1024 * 1024 + 1),
    ]) {
      expect(
        () => const FileSelectorExportStore(isAndroid: true).saveImage(
          pngBytes: bytes,
          cancellation: ExportCancellation(),
          revalidateBeforeWrite: () async {},
        ),
        throwsA(isA<ExportException>()),
      );
    }
    expect(called, isFalse);
  });
}

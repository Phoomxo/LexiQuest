// Isolated native acceptance fixture. JNI 1.0.3 / jni_flutter 1.0.2 are already
// locked transitive dependencies; this does not add product APIs/dependencies.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart';
import 'package:vocab_learning_app/features/export/data/file_selector_export_store.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'native-export-payloads.dart';

const _case =
    'native export saves exact synthetic CSV and deletes its owned receipt';
const _suite = 'native-export-save-v1';
const _markerName = 'lexiquest-native-export-save-owned.json';
const _hostName = 'lexiquest-native-export-save-host-ready.json';
const _ownerName = 'lexiquest-autonomous-export-save-run-owned.json';

String _format = 'csv';
String get _mime =>
    _format == 'csv' ? 'text/csv' : nativeExportPayloads[_format]!['mime']!;
Uint8List _payload(String runId) => _format != 'csv'
    ? base64Decode(nativeExportPayloads[_format]!['base64']!)
    : Uint8List.fromList(
        utf8.encode(
          'synthetic,run_id,english,thai\ntrue,$runId,book,หนังสือ\n',
        ),
      );

String _fileName(String runId) =>
    'lexiquest-synthetic-save-$runId.${_format == 'csv' ? 'csv' : nativeExportPayloads[_format]!['extension']}';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  String? runId;
  Map<String, Object?> outcome = {'status': 'not_run'};
  void report() {
    binding.reportData = {
      'schemaVersion': 1,
      'suite': _suite,
      'runId': runId,
      'outcome': outcome,
      // ignore: invalid_use_of_visible_for_testing_member
      'testResults': binding.results.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    };
  }

  testWidgets(_case, (tester) async {
    File? marker;
    var markerCreated = false;
    String? receiptUri;
    String? verifiedSha;
    var deleteAttempted = false;
    var deleteAcknowledged = false;
    var postDelete = 'notChecked';
    _ReceiptVerifier? verifier;
    late Uint8List bytes;
    late String digest;
    Future<void> phase(String value) async {
      await marker!.writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'runId': runId,
          'syntheticOnly': true,
          'phase': value,
          'fileName': _fileName(runId!),
          'byteCount': bytes.length,
          'expectedSha256': digest,
          'receiptUri': receiptUri,
          'verifiedSha256': verifiedSha,
          'deleteAttempted': deleteAttempted,
          'deleteAcknowledged': deleteAcknowledged,
          'postDeleteObservation': postDelete,
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
      final ownerFile = File('${directory.path}/$_ownerName');
      expect(await ownerFile.length(), lessThanOrEqualTo(2048));
      final owner =
          jsonDecode(await ownerFile.readAsString()) as Map<String, dynamic>;
      expect(owner['kind'], 'export-save');
      _format = owner['exportFormat'] as String? ?? 'csv';
      expect(
        _format == 'csv' || nativeExportPayloads.containsKey(_format),
        isTrue,
      );
      runId = owner['runId'] as String;
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(runId!),
        isTrue,
      );
      bytes = _payload(runId!);
      digest = sha256.convert(bytes).toString();
      // Resolve real app-UID JNI APIs before asking the host to open a picker.
      verifier = _ReceiptVerifier();
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: Center(
                child: Text('Synthetic native export save and readback check'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      marker = File('${directory.path}/$_markerName');
      await marker.create(exclusive: true);
      markerCreated = true;
      await phase('ready-to-open');
      final host = File('${directory.path}/$_hostName');
      final wait = Stopwatch()..start();
      Map<String, dynamic>? ready;
      while (wait.elapsed < const Duration(seconds: 45)) {
        if (await host.exists() && await host.length() <= 2048) {
          try {
            ready =
                jsonDecode(await host.readAsString()) as Map<String, dynamic>;
            break;
          } on FormatException {
            // The host's noclobber signal may still be flushing.
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready, {'schemaVersion': 1, 'runId': runId, 'openPicker': true});
      await phase('awaiting-picker');
      final cancellation = ExportCancellation();
      final saved = await const FileSelectorExportStore()
          .save(
            ExportArtifact(
              format: ExportFormat.values.byName(_format),
              suggestedFileName: _fileName(runId!),
              mimeType: _mime,
              bytes: bytes,
              recordCount: 1,
              schemaVersion: 1,
              algorithmVersion: 1,
              generatedAtUtc: DateTime.utc(2026, 9, 9),
              timeZone: 'UTC',
              exclusions: const [],
            ),
            cancellation: cancellation,
          )
          .timeout(const Duration(seconds: 90));
      receiptUri = saved.path;
      await phase('saved'); // Preserve the real receipt before inspecting it.
      expect(saved.bytesWritten, bytes.length);
      expect(cancellation.isCancelled, isFalse);
      verifier.verify(receiptUri, _fileName(runId!), bytes);
      verifiedSha = digest;
      await phase('verified');
      // Re-read metadata and exact bounded contents immediately before the only
      // deletion. Never enumerate a provider, parent folder or user documents.
      verifier.verify(receiptUri, _fileName(runId!), bytes);
      deleteAttempted = true;
      await phase('delete-intent');
      deleteAcknowledged = verifier.deleteOnce(receiptUri);
      await phase('delete-intent');
      expect(deleteAcknowledged, isTrue);
      postDelete = verifier.observeAfterDelete(receiptUri);
      expect(postDelete, anyOf('notFound', 'grantRevoked'));
      // Android's provider deletes then revokes grants. Grant revocation is
      // reported separately and is not mislabeled filesystem absence.
      await phase('cleaned');
      outcome = {
        'status': 'saved-readback-cleaned',
        'syntheticOnly': true,
        'productionStore': true,
        'fileName': _fileName(runId!),
        'byteCount': bytes.length,
        'sha256': digest,
        'tokenCancelled': false,
        'deleteAttemptCount': 1,
        'deleteAcknowledged': true,
        'postDeleteObservation': postDelete,
      };
      report();
      print('NATIVE_EXPORT_SAVE_RESULT ${jsonEncode(outcome)}');
    } catch (error) {
      outcome = {'status': 'failed', 'errorType': error.runtimeType.toString()};
      if (markerCreated) await phase('failed');
      report();
      // Do not print Java exception details containing a provider's context.
      if (error is JThrowable) {
        error.release();
        throw StateError(
          'Exact owned export JNI operation failed; receipt preserved',
        );
      }
      rethrow;
    } finally {
      verifier?.close();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('DEVICE_NATIVE_EXPORT_SAVE_FINAL_SENTINEL', (tester) async {
    report();
    expect(outcome['status'], 'saved-readback-cleaned');
    print('NATIVE_EXPORT_SAVE_FINAL_REPORT ${jsonEncode(binding.reportData)}');
  });
  unawaited(_publishService());
}

/// Real Android APIs invoked inside the app UID. No injected saver or native
/// implementation changes; only the receipt returned by production is accepted.
final class _ReceiptVerifier {
  _ReceiptVerifier() {
    resolver = contextClass.instanceMethodId(
      'getContentResolver',
      '()Landroid/content/ContentResolver;',
    )(context, JObject.type, []);
  }
  final context = androidApplicationContext;
  final contextClass = JClass.forName('android/content/Context');
  final resolverClass = JClass.forName('android/content/ContentResolver');
  final uriClass = JClass.forName('android/net/Uri');
  final documentsClass = JClass.forName('android/provider/DocumentsContract');
  final cursorClass = JClass.forName('android/database/Cursor');
  final streamClass = JClass.forName('java/io/InputStream');
  late final JObject resolver;
  final Set<String> _verifiedReceipts = {};
  final Set<String> _deleteAttempts = {};

  JObject _uri(String value) {
    final parsed = Uri.parse(value);
    if (value.length > 2048 ||
        parsed.scheme != 'content' ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasPort ||
        !const {
          'com.android.externalstorage.documents',
          'com.android.providers.downloads.documents',
        }.contains(parsed.host) ||
        parsed.pathSegments.length != 2 ||
        parsed.pathSegments.first != 'document' ||
        parsed.pathSegments.last.isEmpty) {
      throw StateError('Receipt is not one exact local document URI');
    }
    final string = value.toJString();
    try {
      return uriClass.staticMethodId(
        'parse',
        '(Ljava/lang/String;)Landroid/net/Uri;',
      )(uriClass, JObject.type, [string]);
    } finally {
      string.release();
    }
  }

  String _stringAt(JObject cursor, int index) {
    final value = cursorClass.instanceMethodId(
      'getString',
      '(I)Ljava/lang/String;',
    )(cursor, JString.type, [JValueInt(index)]);
    try {
      return value.toDartString();
    } finally {
      value.release();
    }
  }

  void verify(String receipt, String name, Uint8List expected) {
    final uri = _uri(receipt);
    final columns = [
      'document_id',
      '_display_name',
      '_size',
      'mime_type',
    ].map((value) => value.toJString()).toList();
    final projection = JArray.of(JString.type, columns);
    JObject? cursor;
    JObject? stream;
    try {
      expect(
        documentsClass.staticMethodId(
          'isDocumentUri',
          '(Landroid/content/Context;Landroid/net/Uri;)Z',
        )(documentsClass, jboolean.type, [context, uri]),
        isTrue,
      );
      final documentId = documentsClass.staticMethodId(
        'getDocumentId',
        '(Landroid/net/Uri;)Ljava/lang/String;',
      )(documentsClass, JString.type, [uri]);
      try {
        final receivedCursor = resolverClass
            .instanceMethodId(
              'query',
              '(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;',
            )
            .callNullable(resolver, JObject.type, [
              uri,
              projection,
              null,
              null,
              null,
            ]);
        if (receivedCursor == null) {
          throw StateError(
            'Exact document provider returned no metadata cursor',
          );
        }
        cursor = receivedCursor;
        expect(
          cursorClass.instanceMethodId('getCount', '()I')(
            receivedCursor,
            jint.type,
            [],
          ),
          1,
        );
        expect(
          cursorClass.instanceMethodId('moveToFirst', '()Z')(
            receivedCursor,
            jboolean.type,
            [],
          ),
          isTrue,
        );
        expect(_stringAt(receivedCursor, 0), documentId.toDartString());
        expect(_stringAt(receivedCursor, 1), name);
        expect(
          cursorClass.instanceMethodId('isNull', '(I)Z')(
            receivedCursor,
            jboolean.type,
            [JValueInt(2)],
          ),
          isFalse,
        );
        expect(
          cursorClass.instanceMethodId('getLong', '(I)J')(
            receivedCursor,
            jlong.type,
            [JValueInt(2)],
          ),
          expected.length,
        );
        expect(
          _stringAt(receivedCursor, 3),
          _format == 'csv'
              ? anyOf('text/csv', 'text/comma-separated-values')
              : equals(_mime),
        );
      } finally {
        documentId.release();
      }
      final receivedStream = resolverClass
          .instanceMethodId(
            'openInputStream',
            '(Landroid/net/Uri;)Ljava/io/InputStream;',
          )
          .callNullable(resolver, JObject.type, [uri]);
      if (receivedStream == null) {
        throw StateError('Exact document provider returned no input stream');
      }
      stream = receivedStream;
      final read = streamClass.instanceMethodId('read', '()I');
      final actual = <int>[];
      // One byte beyond the exact synthetic payload detects appended content.
      for (var i = 0; i <= expected.length; i++) {
        final byte = read(receivedStream, jint.type, []);
        if (byte == -1) break;
        actual.add(byte);
      }
      expect(actual, orderedEquals(expected));
      expect(
        sha256.convert(actual).toString(),
        sha256.convert(expected).toString(),
      );
      _verifiedReceipts.add(receipt);
    } finally {
      if (stream != null) {
        try {
          streamClass.instanceMethodId('close', '()V')(stream, jvoid.type, []);
        } finally {
          stream.release();
        }
      }
      if (cursor != null) {
        try {
          cursorClass.instanceMethodId('close', '()V')(cursor, jvoid.type, []);
        } finally {
          cursor.release();
        }
      }
      projection.release();
      for (final column in columns) {
        column.release();
      }
      uri.release();
    }
  }

  bool deleteOnce(String receipt) {
    if (!_verifiedReceipts.contains(receipt) || !_deleteAttempts.add(receipt)) {
      throw StateError(
        'Deletion requires a verified receipt and is never retried',
      );
    }
    final uri = _uri(receipt);
    try {
      return documentsClass.staticMethodId(
        'deleteDocument',
        '(Landroid/content/ContentResolver;Landroid/net/Uri;)Z',
      )(documentsClass, jboolean.type, [resolver, uri]);
    } finally {
      uri.release();
    }
  }

  String observeAfterDelete(String receipt) {
    if (!_deleteAttempts.contains(receipt))
      throw StateError('No deletion intent');
    final uri = _uri(receipt);
    try {
      final stream = resolverClass
          .instanceMethodId(
            'openInputStream',
            '(Landroid/net/Uri;)Ljava/io/InputStream;',
          )
          .callNullable(resolver, JObject.type, [uri]);
      if (stream == null) {
        return 'unavailable';
      }
      try {
        streamClass.instanceMethodId('close', '()V')(stream, jvoid.type, []);
      } finally {
        stream.release();
      }
      return 'stillReadable';
    } on JThrowable catch (error) {
      final missing = JClass.forName('java/io/FileNotFoundException');
      final denied = JClass.forName('java/lang/SecurityException');
      try {
        if (error.isInstanceOf(missing)) return 'notFound';
        if (error.isInstanceOf(denied)) return 'grantRevoked';
        return 'unavailable';
      } finally {
        missing.release();
        denied.release();
        error.release();
      }
    } finally {
      uri.release();
    }
  }

  void close() {
    resolver.release();
    for (final object in [
      context,
      contextClass,
      resolverClass,
      uriClass,
      documentsClass,
      cursorClass,
      streamClass,
    ]) {
      object.release();
    }
  }
}

Future<void> _publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.host != '127.0.0.1')
    throw StateError('Local VM service unavailable');
  final file = File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  );
  await file.create(exclusive: true);
  await file.writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}

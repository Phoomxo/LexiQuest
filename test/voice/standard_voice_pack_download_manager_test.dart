import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

StandardVoicePackManifest _manifest(List<int> bytes) {
  return StandardVoicePackManifest.fromJson({
    'schemaVersion': 1,
    'packId': 'core-en',
    'version': '1.0.0',
    'locale': 'en',
    'voiceId': 'teacher_female',
    'engine': 'voxcpm2',
    'modelVersion': '2.0.3',
    'license': 'Apache-2.0',
    'licenseUri': 'https://github.com/OpenBMB/VoxCPM/blob/main/LICENSE',
    'minimumAppVersion': '1.0.0+1',
    'baseUri': 'https://assets.example.com/core/',
    'generatedAtUtc': '2026-07-31T00:00:00Z',
    'totalBytes': bytes.length,
    'files': [
      {
        'contentId': 'word-cat',
        'normalizedTextSha256':
            '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045',
        'relativePath': 'words/cat.wav',
        'byteSize': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
    ],
  });
}

final class _Source implements StandardVoicePackByteSource {
  _Source(this.bytes, {this.corrupt = false});

  final List<int> bytes;
  final bool corrupt;
  final starts = <int>[];

  @override
  Future<StandardVoicePackByteResponse> open(
    Uri uri, {
    required int start,
    StandardVoicePackCancellation? cancellation,
  }) async {
    starts.add(start);
    final served = [...bytes];
    if (corrupt) served[0] = served[0] ^ 0xff;
    return StandardVoicePackByteResponse(
      statusCode: start == 0 ? 200 : 206,
      contentRangeStart: start == 0 ? null : start,
      bytes: Stream.value(served.sublist(start)),
    );
  }
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lexiquest-pack-manager-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'resumes a partial file, verifies SHA-256 and atomically activates',
    () async {
      final bytes = utf8.encode('RIFF-standard-pack');
      final manifest = _manifest(bytes);
      final source = _Source(bytes);
      final staging = Directory(
        '${root.path}${Platform.pathSeparator}${manifest.recordId}.partial',
      );
      final partial = File(
        '${staging.path}${Platform.pathSeparator}words'
        '${Platform.pathSeparator}cat.wav.partial',
      );
      await partial.parent.create(recursive: true);
      await partial.writeAsBytes(bytes.sublist(0, 4));
      final manager = StandardVoicePackDownloadManager(
        rootDirectory: () async => root,
        source: source,
        availableBytes: (_) async => 1024 * 1024,
      );

      final installed = await manager.install(manifest);

      expect(source.starts, [4]);
      expect(
        await File(installed.pathFor('words/cat.wav')).readAsBytes(),
        bytes,
      );
      expect(await File(installed.manifestPath).exists(), isTrue);
      expect(await File(installed.activeMarkerPath).readAsString(), '1.0.0');
      expect(await staging.exists(), isFalse);
    },
  );

  test('checksum corruption is rejected and never activated', () async {
    final bytes = utf8.encode('RIFF-standard-pack');
    final manager = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes, corrupt: true),
      availableBytes: (_) async => 1024 * 1024,
    );

    await expectLater(
      manager.install(_manifest(bytes)),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.checksumMismatch,
        ),
      ),
    );

    expect(
      await File(
        '${root.path}${Platform.pathSeparator}core-en.active',
      ).exists(),
      isFalse,
    );
  });

  test('free-space preflight and cancellation fail closed', () async {
    final bytes = utf8.encode('RIFF-standard-pack');
    final manifest = _manifest(bytes);
    final noSpace = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => bytes.length - 1,
    );
    await expectLater(
      noSpace.install(manifest),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.insufficientStorage,
        ),
      ),
    );

    final cancellation = StandardVoicePackCancellation()..cancel();
    final cancelled = StandardVoicePackDownloadManager(
      rootDirectory: () async => root,
      source: _Source(bytes),
      availableBytes: (_) async => 1024,
    );
    await expectLater(
      cancelled.install(manifest, cancellation: cancellation),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.cancelled,
        ),
      ),
    );
  });
}

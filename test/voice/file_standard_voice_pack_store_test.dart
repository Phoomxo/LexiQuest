import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/file_standard_voice_pack_store.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lexiquest-pack-store-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('loads only the active manifest whose files still verify', () async {
    final bytes = utf8.encode('RIFF-pack');
    final hash = sha256.convert(bytes).toString();
    final manifest = StandardVoicePackManifest.fromJson({
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
          'sha256': hash,
        },
      ],
    });
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}${manifest.recordId}',
    );
    final audio = File(
      '${directory.path}${Platform.pathSeparator}words'
      '${Platform.pathSeparator}cat.wav',
    );
    await audio.parent.create(recursive: true);
    await audio.writeAsBytes(bytes);
    await File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    ).writeAsString(jsonEncode(manifest.toJson()));
    final marker = File(
      '${root.path}${Platform.pathSeparator}${manifest.packId}.active',
    );
    await marker.writeAsString(manifest.version);
    final store = FileStandardVoicePackStore(() async => root);

    final loaded = await store.loadActive('core-en');

    expect(loaded?.manifest.recordId, manifest.recordId);
    expect(await File(loaded!.pathFor('words/cat.wav')).readAsBytes(), bytes);

    await audio.writeAsBytes(utf8.encode('corrupt'));
    expect(await store.loadActive('core-en'), isNull);
    expect(await marker.exists(), isFalse);
  });
}

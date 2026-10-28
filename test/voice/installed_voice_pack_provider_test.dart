import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/installed_voice_pack_provider.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

void main() {
  late Directory root;
  late List<int> bytes;
  late InstalledStandardVoicePack installed;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('lexiquest-installed-pack-');
    bytes = utf8.encode('RIFF-pack');
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
          'relativePath': 'cat.wav',
          'byteSize': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
    });
    await File(
      '${root.path}${Platform.pathSeparator}cat.wav',
    ).writeAsBytes(bytes);
    installed = InstalledStandardVoicePack(
      rootPath: root.path,
      manifest: manifest,
      activeMarkerPath: '${root.path}.active',
    );
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  VoiceRequest request({String text = 'Cat', String contentId = 'word-cat'}) {
    return VoiceRequest.create(
      text: text,
      language: 'en',
      voiceId: 'teacher_female',
      speed: 1,
      contentId: contentId,
      contentType: 'word',
      mode: VoiceMode.practice,
    );
  }

  test(
    'returns only content-ID and normalized-text matched verified bytes',
    () async {
      final provider = InstalledVoicePackProvider(installed);

      final audio = await provider.synthesize(request(text: '  Cat '));

      expect(provider.descriptor.engine, VoiceEngine.offlinePack);
      expect(provider.descriptor.capabilities, {
        VoiceCapability.standardTargetSpeech,
      });
      expect(audio.bytes, bytes);
      expect(audio.engine, VoiceEngine.offlinePack);
      expect(audio.modelVersion, 'core-en@1.0.0:2.0.3');
    },
  );

  test('unknown, text-mismatched, and mutated files fail closed', () async {
    final provider = InstalledVoicePackProvider(installed);
    for (final invalid in [
      request(contentId: 'unknown'),
      request(text: 'Dog'),
    ]) {
      await expectLater(
        provider.synthesize(invalid),
        throwsA(isA<VoiceFailure>()),
      );
    }
    await File(
      '${root.path}${Platform.pathSeparator}cat.wav',
    ).writeAsString('mutated');
    await expectLater(
      provider.synthesize(request()),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.checksumMismatch,
        ),
      ),
    );
  });
}

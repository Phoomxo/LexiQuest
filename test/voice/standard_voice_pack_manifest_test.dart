import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';

Map<String, Object?> _validJson() => {
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
  'baseUri': 'https://assets.example.com/voice/core-en/1.0.0/',
  'generatedAtUtc': '2026-07-31T00:00:00Z',
  'totalBytes': 12,
  'files': [
    {
      'contentId': 'word-cat',
      'normalizedTextSha256':
          '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045',
      'relativePath': 'words/cat.wav',
      'byteSize': 12,
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    },
  ],
};

void main() {
  test('parses an immutable trusted pack manifest', () {
    final manifest = StandardVoicePackManifest.fromJson(_validJson());

    expect(manifest.recordId, 'core-en@1.0.0');
    expect(manifest.files.single.contentId, 'word-cat');
    expect(manifest.files.single.uri.toString(), endsWith('/words/cat.wav'));
    expect(
      () => manifest.files.add(manifest.files.single),
      throwsUnsupportedError,
    );
  });

  test('rejects traversal, absolute paths and case-insensitive duplicates', () {
    for (final paths in [
      ['../cat.wav'],
      ['/cat.wav'],
      ['C:\\cat.wav'],
      ['words/cat.wav', 'WORDS/CAT.WAV'],
    ]) {
      final json = _validJson();
      json['totalBytes'] = paths.length * 12;
      json['files'] = [
        for (var index = 0; index < paths.length; index++)
          {
            ...(_validJson()['files']! as List).single as Map<String, Object?>,
            'contentId': 'word-$index',
            'relativePath': paths[index],
          },
      ];
      expect(
        () => StandardVoicePackManifest.fromJson(json),
        throwsArgumentError,
        reason: paths.join(','),
      );
    }
  });

  test(
    'rejects byte totals, hashes, non-HTTPS URLs and unbounded file lists',
    () {
      final wrongTotal = _validJson()..['totalBytes'] = 13;
      final badHash = _validJson();
      (badHash['files']! as List).single['sha256'] = 'not-a-hash';
      final insecure = _validJson()..['baseUri'] = 'http://assets.example.com/';
      final tooMany = _validJson()
        ..['totalBytes'] = 2001
        ..['files'] = [
          for (var index = 0; index < 2001; index++)
            {
              ...(_validJson()['files']! as List).single
                  as Map<String, Object?>,
              'contentId': 'word-$index',
              'relativePath': 'words/$index.wav',
              'byteSize': 1,
            },
        ];

      for (final json in [wrongTotal, badHash, insecure, tooMany]) {
        expect(
          () => StandardVoicePackManifest.fromJson(json),
          throwsArgumentError,
        );
      }
    },
  );

  test('matches normalized request text by SHA-256', () {
    final manifest = StandardVoicePackManifest.fromJson(_validJson());
    final file = manifest.files.single;

    expect(file.matchesText('  Cat  '), isTrue);
    expect(file.matchesText('Dog'), isFalse);
  });
}

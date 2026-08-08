import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

final Matcher _validationFailure = isA<VoiceFailure>().having(
  (failure) => failure.category,
  'category',
  VoiceFailureCategory.validation,
);

VoiceRequest _request({
  String text = 'Hello world.',
  String language = 'en',
  String voiceId = 'teacher_female',
  double speed = 1.0,
}) {
  return VoiceRequest.create(
    text: text,
    language: language,
    voiceId: voiceId,
    speed: speed,
    contentId: 'word-001',
    contentType: 'word',
    mode: VoiceMode.practice,
  );
}

VoiceAudioCacheKey _key({
  String text = 'Hello world.',
  String language = 'en',
  String voiceId = 'teacher_female',
  double speed = 1.0,
  String modelVersion = 'v1',
  VoiceEngine engine = VoiceEngine.omniVoice,
}) {
  return VoiceAudioCacheKey.create(
    request: _request(
      text: text,
      language: language,
      voiceId: voiceId,
      speed: speed,
    ),
    engine: engine,
    modelVersion: modelVersion,
  );
}

Uint8List _bytes(int fill, int length) {
  final data = Uint8List(length);
  for (var i = 0; i < length; i++) {
    data[i] = fill;
  }
  return data;
}

Future<VoiceFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
    fail('Expected a VoiceFailure.');
  } on VoiceFailure catch (failure) {
    return failure;
  }
}

VoiceFailure _captureKeyFailure(String modelVersion) {
  try {
    VoiceAudioCacheKey.create(
      request: _request(),
      engine: VoiceEngine.omniVoice,
      modelVersion: modelVersion,
    );
    fail('Expected a VoiceFailure for a blank model version.');
  } on VoiceFailure catch (failure) {
    return failure;
  }
}

void main() {
  group('VoiceAudioCacheKey equality', () {
    test(
      'is equal for equivalent normalized requests and trimmed model version',
      () {
        final normalized = VoiceAudioCacheKey.create(
          request: VoiceRequest.create(
            text: '  Hello   world.  ',
            language: ' EN ',
            voiceId: ' teacher_female ',
            speed: 1.0,
            contentId: 'word-001',
            contentType: 'word',
            mode: VoiceMode.practice,
          ),
          engine: VoiceEngine.omniVoice,
          modelVersion: '  v1  ',
        );
        final equivalent = VoiceAudioCacheKey.create(
          request: VoiceRequest.create(
            text: 'Hello world.',
            language: 'en',
            voiceId: 'teacher_female',
            speed: 1.0,
            contentId: 'word-999',
            contentType: 'sentence',
            mode: VoiceMode.researchEvaluation,
            assignedEngine: VoiceEngine.omniVoice,
          ),
          engine: VoiceEngine.omniVoice,
          modelVersion: 'v1',
        );

        expect(normalized == equivalent, isTrue);
        expect(normalized.hashCode, equivalent.hashCode);
      },
    );

    test('changes when any synthesis-relevant value changes', () {
      final base = _key();
      final variants = <(String, VoiceAudioCacheKey)>[
        ('text', _key(text: 'Goodbye.')),
        ('language', _key(language: 'th')),
        ('voiceId', _key(voiceId: 'teacher_male')),
        ('speed', _key(speed: 0.75)),
        ('engine', _key(engine: VoiceEngine.voxCpmStandard)),
        ('modelVersion', _key(modelVersion: 'v2')),
      ];

      for (final (label, other) in variants) {
        expect(base == other, isFalse, reason: label);
      }
    });
  });

  test('cache key separates engines that synthesize identical text', () {
    final omni = _key(engine: VoiceEngine.omniVoice, modelVersion: 'shared-1');
    final vox = _key(
      engine: VoiceEngine.voxCpmStandard,
      modelVersion: 'shared-1',
    );

    expect(omni, isNot(vox));
  });

  test('participant transient audio cannot enter standard cache', () {
    final mirrorRequest = VoiceRequest.create(
      text: 'Hello world.',
      language: 'en',
      voiceId: 'session-mirror',
      speed: 1,
      contentId: 'word-001',
      contentType: 'word',
      mode: VoiceMode.practice,
      capability: VoiceCapability.sessionVoiceMirror,
      privacyScope: VoicePrivacyScope.participantTransient,
    );

    expect(
      () => VoiceAudioCacheKey.create(
        request: mirrorRequest,
        engine: VoiceEngine.voxCpmMirror,
        modelVersion: 'vox-1',
      ),
      throwsA(_validationFailure),
    );
  });

  group('VoiceAudioCacheKey modelVersion validation', () {
    final blanks = <(String, String)>[
      ('empty', ''),
      ('spaces', '   '),
      ('tab-newline', '\t\n'),
    ];

    for (final (label, value) in blanks) {
      test('rejects blank modelVersion: $label', () {
        expect(() => _key(modelVersion: value), throwsA(_validationFailure));
      });
    }

    test('uses one fixed safe message that does not echo the input', () {
      final first = _captureKeyFailure(' \t');
      final second = _captureKeyFailure('\n ');

      expect(first.category, VoiceFailureCategory.validation);
      expect(first.toString(), second.toString());
      expect(first.toString(), isNot(contains('\t')));
      expect(first.toString(), isNot(contains('\n')));
    });
  });

  group('MemoryVoiceAudioCache construction', () {
    test('rejects non-positive maxEntries', () {
      expect(
        () => MemoryVoiceAudioCache(maxEntries: 0, maxBytes: 10),
        throwsArgumentError,
      );
      expect(
        () => MemoryVoiceAudioCache(maxEntries: -1, maxBytes: 10),
        throwsArgumentError,
      );
    });

    test('rejects non-positive maxBytes', () {
      expect(
        () => MemoryVoiceAudioCache(maxEntries: 1, maxBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => MemoryVoiceAudioCache(maxEntries: 1, maxBytes: -5),
        throwsArgumentError,
      );
    });
  });

  group('MemoryVoiceAudioCache reads', () {
    test('returns null on a cache miss', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);

      expect(await cache.get(_key(text: 'absent')), isNull);
    });

    test('round-trips equal bytes for distinct keys', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);
      await cache.put(_key(text: 'one'), _bytes(1, 8));
      await cache.put(_key(text: 'two'), _bytes(2, 16));

      expect(await cache.get(_key(text: 'one')), _bytes(1, 8));
      expect(await cache.get(_key(text: 'two')), _bytes(2, 16));
      expect(cache.entryCount, 2);
      expect(cache.totalBytes, 24);
    });
  });

  group('MemoryVoiceAudioCache defensive copies', () {
    test(
      'put copies caller bytes; later mutation cannot corrupt cache',
      () async {
        final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);
        final caller = _bytes(7, 12);
        await cache.put(_key(text: 'one'), caller);

        caller[0] = 0xFE;

        expect(await cache.get(_key(text: 'one')), _bytes(7, 12));
      },
    );

    test('get returns a copy; mutating it cannot corrupt cache', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);
      await cache.put(_key(text: 'one'), _bytes(7, 12));

      final firstRead = (await cache.get(_key(text: 'one')))!;
      firstRead[0] = 0xFD;

      expect(await cache.get(_key(text: 'one')), _bytes(7, 12));
    });

    test(
      'get never returns the caller or internal mutable reference',
      () async {
        final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);
        final caller = _bytes(7, 12);
        await cache.put(_key(text: 'one'), caller);

        final firstRead = (await cache.get(_key(text: 'one')))!;
        final secondRead = (await cache.get(_key(text: 'one')))!;

        expect(identical(firstRead, caller), isFalse);
        expect(identical(firstRead, secondRead), isFalse);
      },
    );
  });

  test(
    'updating an existing key replaces bytes and accounting without a new entry',
    () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);

      await cache.put(_key(text: 'shared'), _bytes(1, 10));
      await cache.put(_key(text: 'shared'), _bytes(2, 20));

      expect(cache.entryCount, 1);
      expect(cache.totalBytes, 20);
      expect(await cache.get(_key(text: 'shared')), _bytes(2, 20));
    },
  );

  group('MemoryVoiceAudioCache eviction', () {
    test('reads refresh least-recently-used order', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 2, maxBytes: 1000);
      final recent = _key(text: 'one');
      final older = _key(text: 'two');
      await cache.put(recent, _bytes(1, 10));
      await cache.put(older, _bytes(2, 10));

      expect(await cache.get(recent), isNotNull);

      await cache.put(_key(text: 'three'), _bytes(3, 10));

      expect(await cache.get(recent), isNotNull);
      expect(await cache.get(older), isNull);
      expect(cache.entryCount, 2);
    });

    test(
      'evicts least-recently-used entries until both limits are satisfied',
      () async {
        final cache = MemoryVoiceAudioCache(maxEntries: 10, maxBytes: 20);
        final recent = _key(text: 'one');
        final older = _key(text: 'two');
        await cache.put(recent, _bytes(1, 10));
        await cache.put(older, _bytes(2, 10));

        await cache.get(recent);

        await cache.put(_key(text: 'three'), _bytes(3, 15));

        expect(await cache.get(recent), isNull);
        expect(await cache.get(older), isNull);
        expect(await cache.get(_key(text: 'three')), isNotNull);
        expect(cache.entryCount, 1);
        expect(cache.totalBytes, 15);
      },
    );

    test('a value larger than maxBytes is not retained', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 10, maxBytes: 20);

      await cache.put(_key(text: 'big'), _bytes(9, 30));

      expect(await cache.get(_key(text: 'big')), isNull);
      expect(cache.entryCount, 0);
      expect(cache.totalBytes, 0);
    });

    test(
      'an oversized update removes an older value for the same key',
      () async {
        final cache = MemoryVoiceAudioCache(maxEntries: 10, maxBytes: 20);
        final key = _key(text: 'shared');

        await cache.put(key, _bytes(1, 10));
        expect(cache.entryCount, 1);
        expect(cache.totalBytes, 10);

        await cache.put(key, _bytes(9, 30));

        expect(await cache.get(key), isNull);
        expect(cache.entryCount, 0);
        expect(cache.totalBytes, 0);
      },
    );
  });

  group('MemoryVoiceAudioCache empty bytes', () {
    test('rejects empty bytes with a validation failure', () async {
      final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);

      final failure = await _captureFailure(
        () => cache.put(_key(text: 'one'), Uint8List(0)),
      );

      expect(failure.category, VoiceFailureCategory.validation);
      expect(cache.entryCount, 0);
      expect(cache.totalBytes, 0);
    });

    test('uses one fixed safe message for empty bytes', () async {
      final first = await _captureFailure(
        () => MemoryVoiceAudioCache(
          maxEntries: 4,
          maxBytes: 1000,
        ).put(_key(text: 'one'), Uint8List(0)),
      );
      final second = await _captureFailure(
        () => MemoryVoiceAudioCache(
          maxEntries: 4,
          maxBytes: 1000,
        ).put(_key(text: 'two'), Uint8List(0)),
      );

      expect(first.toString(), second.toString());
    });
  });

  test('clear resets entries and byte accounting', () async {
    final cache = MemoryVoiceAudioCache(maxEntries: 4, maxBytes: 1000);
    await cache.put(_key(text: 'one'), _bytes(1, 10));
    await cache.put(_key(text: 'two'), _bytes(2, 20));

    await cache.clear();

    expect(cache.entryCount, 0);
    expect(cache.totalBytes, 0);
    expect(await cache.get(_key(text: 'one')), isNull);
  });
}

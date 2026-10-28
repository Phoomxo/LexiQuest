import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

final _validationFailure = isA<VoiceFailure>().having(
  (failure) => failure.category,
  'category',
  VoiceFailureCategory.validation,
);

String _repeat(String value, int count) =>
    List<String>.filled(count, value).join();

VoiceRequest _validRequest({
  String text = 'Hello world.',
  String language = 'en',
  String voiceId = 'teacher_female',
  double speed = 1.0,
  String contentId = 'word-001',
  String contentType = 'word',
  VoiceMode mode = VoiceMode.practice,
  VoiceEngine? assignedEngine,
}) {
  return VoiceRequest.create(
    text: text,
    language: language,
    voiceId: voiceId,
    speed: speed,
    contentId: contentId,
    contentType: contentType,
    mode: mode,
    assignedEngine: assignedEngine,
  );
}

void main() {
  group('voice enums', () {
    test('declares the supported engines and modes', () {
      expect(VoiceEngine.values, [
        VoiceEngine.nativeTts,
        VoiceEngine.omniVoice,
      ]);
      expect(VoiceMode.values, [
        VoiceMode.practice,
        VoiceMode.researchEvaluation,
      ]);
    });

    test('covers required failure categories', () {
      expect(
        VoiceFailureCategory.values,
        containsAll(const <VoiceFailureCategory>[
          VoiceFailureCategory.validation,
          VoiceFailureCategory.authentication,
          VoiceFailureCategory.network,
          VoiceFailureCategory.timeout,
          VoiceFailureCategory.rateLimited,
          VoiceFailureCategory.modelUnavailable,
          VoiceFailureCategory.synthesis,
          VoiceFailureCategory.playback,
          VoiceFailureCategory.cancelled,
          VoiceFailureCategory.configuration,
          VoiceFailureCategory.unknown,
        ]),
      );
    });
  });

  group('VoiceRequest text normalization', () {
    final cases = <(String, String, String)>[
      ('plain', 'hello', 'hello'),
      ('surrounding spaces', '  hello  ', 'hello'),
      ('internal spaces', 'hello   world', 'hello world'),
      ('tabs', 'hello\tworld', 'hello world'),
      ('newlines', 'hello\nworld', 'hello world'),
      ('mixed whitespace', '\thello \n world \r', 'hello world'),
      ('sentence', '  The   cat  is   sleeping.  ', 'The cat is sleeping.'),
    ];

    for (final (label, input, expected) in cases) {
      test('collapses whitespace: $label', () {
        expect(_validRequest(text: input).text, expected);
      });
    }

    final blanks = <(String, String)>[
      ('empty', ''),
      ('spaces', '   '),
      ('tab-newline', '\t\n'),
      ('mixed', ' \t \n '),
    ];

    for (final (label, value) in blanks) {
      test('rejects blank text: $label', () {
        expect(() => _validRequest(text: value), throwsA(_validationFailure));
      });
    }

    test('accepts normalized text of exactly 500 UTF-16 code units', () {
      final exact = _repeat('a', 500);
      expect(_validRequest(text: exact).text.length, 500);
    });

    test('rejects normalized text longer than 500 UTF-16 code units', () {
      expect(
        () => _validRequest(text: _repeat('a', 501)),
        throwsA(_validationFailure),
      );
    });

    test('measures length after whitespace collapse', () {
      final exact = _repeat('a', 500);
      expect(_validRequest(text: '  $exact  ').text, exact);
      expect(
        () => _validRequest(text: '  ${_repeat('a', 501)}  '),
        throwsA(_validationFailure),
      );
    });
  });

  group('VoiceRequest language', () {
    final accepted = <(String, String, String)>[
      ('English', 'en', 'en'),
      ('Thai', 'th', 'th'),
      ('padded English', '  en ', 'en'),
      ('uppercase Thai', 'TH', 'th'),
      ('mixed case Thai', ' Th\t', 'th'),
      ('mixed case English', 'eN', 'en'),
    ];

    for (final (label, input, expected) in accepted) {
      test('accepts and normalizes $label', () {
        expect(_validRequest(language: input).language, expected);
      });
    }

    final rejected = <(String, String)>[
      ('empty', ''),
      ('spaces', '   '),
      ('French', 'fr'),
      ('language name', 'english'),
      ('BCP-47 tag', 'EN-US'),
      ('single character', 'e'),
    ];

    for (final (label, value) in rejected) {
      test('rejects unsupported language: $label', () {
        expect(
          () => _validRequest(language: value),
          throwsA(_validationFailure),
        );
      });
    }
  });

  group('VoiceRequest speed', () {
    for (final value in <double>[0.5, 0.75, 1.0, 1.25, 1.5]) {
      test('accepts speed $value', () {
        expect(_validRequest(speed: value).speed, value);
      });
    }

    final rejected = <(String, double)>[
      ('below minimum', 0.49),
      ('above maximum', 1.51),
      ('zero', 0.0),
      ('negative', -1.0),
      ('NaN', double.nan),
      ('infinity', double.infinity),
      ('negative infinity', double.negativeInfinity),
    ];

    for (final (label, value) in rejected) {
      test('rejects speed $label', () {
        expect(() => _validRequest(speed: value), throwsA(_validationFailure));
      });
    }
  });

  group('VoiceRequest required identifiers', () {
    final fields = <String, VoiceRequest Function(String)>{
      'voiceId': (value) => _validRequest(voiceId: value),
      'contentId': (value) => _validRequest(contentId: value),
      'contentType': (value) => _validRequest(contentType: value),
    };

    const blanks = <(String, String)>[
      ('empty', ''),
      ('spaces', '   '),
      ('tab-newline', '\t\n'),
    ];

    fields.forEach((name, build) {
      for (final (label, value) in blanks) {
        test('rejects blank $name: $label', () {
          expect(() => build(value), throwsA(_validationFailure));
        });
      }
    });
  });

  group('VoiceRequest engine assignment', () {
    test('practice may omit an assigned engine', () {
      final request = _validRequest(mode: VoiceMode.practice);
      expect(request.mode, VoiceMode.practice);
      expect(request.assignedEngine, isNull);
    });

    test('practice accepts an explicit assigned engine', () {
      final request = _validRequest(assignedEngine: VoiceEngine.nativeTts);
      expect(request.assignedEngine, VoiceEngine.nativeTts);
    });

    test('researchEvaluation requires an assigned engine', () {
      expect(
        () => _validRequest(mode: VoiceMode.researchEvaluation),
        throwsA(_validationFailure),
      );
    });

    test('researchEvaluation accepts an assigned engine', () {
      final request = _validRequest(
        mode: VoiceMode.researchEvaluation,
        assignedEngine: VoiceEngine.omniVoice,
      );
      expect(request.assignedEngine, VoiceEngine.omniVoice);
    });
  });

  test('VoiceRequest exposes normalized immutable state', () {
    final request = VoiceRequest.create(
      text: '  Hello   world.  ',
      language: ' EN ',
      voiceId: 'teacher_female',
      speed: 0.9,
      contentId: 'word-001',
      contentType: 'word',
      mode: VoiceMode.researchEvaluation,
      assignedEngine: VoiceEngine.omniVoice,
    );

    expect(request.text, 'Hello world.');
    expect(request.language, 'en');
    expect(request.voiceId, 'teacher_female');
    expect(request.speed, 0.9);
    expect(request.contentId, 'word-001');
    expect(request.contentType, 'word');
    expect(request.mode, VoiceMode.researchEvaluation);
    expect(request.assignedEngine, VoiceEngine.omniVoice);
  });

  group('VoicePlaybackResult', () {
    test('preserves provenance, fallback, and cache fields', () {
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: true,
        cacheHit: false,
        requestId: 'req-123',
        modelVersion: 'omnivoice-server-version',
      );

      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isTrue);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, 'req-123');
      expect(result.modelVersion, 'omnivoice-server-version');
    });

    test('treats requestId and modelVersion as optional', () {
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: true,
      );

      expect(result.requestId, isNull);
      expect(result.modelVersion, isNull);
    });
  });

  group('VoiceFailure', () {
    test('is an Exception carrying a category and safe message', () {
      const message = 'Unable to reach the voice service.';
      final failure = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: message,
      );

      expect(failure, isA<Exception>());
      expect(failure.category, VoiceFailureCategory.network);
      expect(failure.message, message);
    });

    test('toString exposes only the category and safe message', () {
      const message = 'Unable to reach the voice service.';
      final rendered = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: message,
      ).toString();

      expect(rendered, contains('network'));
      expect(rendered, contains(message));
      expect(rendered, isNot(contains('Bearer')));
      expect(rendered, isNot(contains('token')));
      expect(rendered, isNot(contains('password')));
    });

    test('toString never appends hidden variable cause text', () {
      final first = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'Network unavailable.',
      );
      final second = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'Connection timed out.',
      );

      final templateA = first.toString().replaceAll(
        'Network unavailable.',
        '\uFFFF',
      );
      final templateB = second.toString().replaceAll(
        'Connection timed out.',
        '\uFFFF',
      );
      expect(templateA, templateB);
    });
  });

  test('VoiceProvider declares speak and stop', () async {
    final provider = _FakeProvider();
    final request = _validRequest(assignedEngine: VoiceEngine.nativeTts);

    final result = await provider.speak(request);

    expect(result, isA<VoicePlaybackResult>());
    await provider.stop();
    expect(provider.stopCalls, 1);
  });
}

class _FakeProvider implements VoiceProvider {
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return VoicePlaybackResult(
      requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

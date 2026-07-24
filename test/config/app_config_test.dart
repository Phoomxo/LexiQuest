import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';

typedef _AcceptedCase = ({
  String label,
  String input,
  bool isDebug,
  String expected,
});

const _acceptedCases = <_AcceptedCase>[
  (
    label: 'HTTPS release',
    input: 'https://voice.example.com',
    isDebug: false,
    expected: 'https://voice.example.com/',
  ),
  (
    label: 'HTTPS debug',
    input: 'https://voice.example.com/',
    isDebug: true,
    expected: 'https://voice.example.com/',
  ),
  (
    label: 'HTTPS explicit port',
    input: 'https://voice.example.com:8443',
    isDebug: false,
    expected: 'https://voice.example.com:8443/',
  ),
  (
    label: 'debug loopback',
    input: 'http://127.0.0.1:8080',
    isDebug: true,
    expected: 'http://127.0.0.1:8080/',
  ),
  (
    label: 'debug Android emulator host',
    input: 'http://10.0.2.2:8081',
    isDebug: true,
    expected: 'http://10.0.2.2:8081/',
  ),
];

const _structurallyInvalid = <String>[
  '',
  '   ',
  '\t\n',
  'voice.example.com',
  '/v1/speech',
  '//voice.example.com',
  'https://',
  'https:///api',
  'ftp://voice.example.com',
  'ws://voice.example.com',
  'file:///etc/passwd',
  'https://[unclosed',
  'https://voice.example.com:abc',
  'https://user:pass@voice.example.com',
  'https://voice.example.com?',
  'https://voice.example.com?token=x',
  'https://voice.example.com#',
  'https://voice.example.com#section',
  'https://voice.example.com/api',
  'https://voice.example.com/v1/speech',
];

const _nonLocalHttpHosts = <String>[
  'http://example.com',
  'http://localhost',
  'http://192.168.1.1',
  'http://0.0.0.0',
  'http://[::1]',
  'http://127.0.0.1.evil.com',
  'http://10.0.2.2.evil.com',
];

const _debugOnlyHttpHosts = <String>[
  'http://127.0.0.1',
  'http://10.0.2.2',
  'http://127.0.0.1:8080',
  'http://10.0.2.2:8081',
];

const _leakingInputs = <String>[
  'https://token-sentinel-7c9f3a:secret@voice.example.com',
  'https://voice.example.com?code=Bearer-credential-leak-7c9f3a',
  'https://voice.example.com#leak@example.test',
  'https://[api-key-secret-7c9f3a',
  'https://voice.example.com/token-sentinel-7c9f3a',
  'ftp://api-key-secret-7c9f3a.example.com',
  'http://api-key-secret-7c9f3a.example.com',
  'api-key-secret-7c9f3a',
  '',
];

AppConfigException _captureException(String input, {required bool isDebug}) {
  try {
    AppConfig.fromValues(voiceApiUrl: input, isDebug: isDebug);
    fail('Expected AppConfigException.');
  } on AppConfigException catch (exception) {
    return exception;
  }
}

void main() {
  group('accepted voice API origins', () {
    for (final testCase in _acceptedCases) {
      test(testCase.label, () {
        final config = AppConfig.fromValues(
          voiceApiUrl: testCase.input,
          isDebug: testCase.isDebug,
        );
        final uri = config.voiceApiBaseUri;

        expect(uri.toString(), testCase.expected);
        expect(uri.path, '/');
        expect(uri.query, isEmpty);
        expect(uri.fragment, isEmpty);
        expect(uri.userInfo, isEmpty);
        expect(
          uri.resolve('/v1/speech'),
          Uri.parse('${testCase.expected}v1/speech'),
        );
      });
    }
  });

  test('preserves explicit HTTPS port', () {
    final config = AppConfig.fromValues(
      voiceApiUrl: 'https://voice.example.com:8443',
      isDebug: false,
    );

    expect(config.voiceApiBaseUri.port, 8443);
  });

  group('release rejects debug-only HTTP origins', () {
    for (final input in _debugOnlyHttpHosts) {
      test(input, () {
        expect(
          () => AppConfig.fromValues(voiceApiUrl: input, isDebug: false),
          throwsA(isA<AppConfigException>()),
        );
      });
    }
  });

  group('debug rejects every non-allowlisted HTTP host', () {
    for (final input in _nonLocalHttpHosts) {
      test(input, () {
        expect(
          () => AppConfig.fromValues(voiceApiUrl: input, isDebug: true),
          throwsA(isA<AppConfigException>()),
        );
      });
    }
  });

  group('structural validation applies in every mode', () {
    for (final (index, input) in _structurallyInvalid.indexed) {
      for (final isDebug in <bool>[false, true]) {
        test('case $index debug=$isDebug', () {
          expect(
            () => AppConfig.fromValues(voiceApiUrl: input, isDebug: isDebug),
            throwsA(isA<AppConfigException>()),
          );
        });
      }
    }
  });

  test('all invalid configurations use one fixed safe representation', () {
    final representations = <String>{};
    for (final input in _leakingInputs) {
      for (final isDebug in <bool>[false, true]) {
        representations.add(
          _captureException(input, isDebug: isDebug).toString(),
        );
      }
    }

    expect(representations, hasLength(1));
  });

  test('configuration failures never expose credential sentinels', () {
    const sentinels = <String>[
      'api-key-secret-7c9f3a',
      'Bearer-credential-leak-7c9f3a',
      'token-sentinel-7c9f3a',
      'leak@example.test',
    ];

    for (final input in _leakingInputs) {
      final rendered = _captureException(input, isDebug: true).toString();
      for (final sentinel in sentinels) {
        expect(rendered, isNot(contains(sentinel)));
      }
      if (input.isNotEmpty) {
        expect(rendered, isNot(contains(input)));
      }
    }
  });

  test('AppConfig exposes only its sanitized base URI', () {
    final config = AppConfig.fromValues(
      voiceApiUrl: 'https://voice.example.com',
      isDebug: false,
    );

    expect(config.voiceApiBaseUri, Uri.parse('https://voice.example.com/'));
    expect(config.toString(), isNot(contains('api-key-secret-7c9f3a')));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

const _credentialSentinel = 'COINTH_GLM_API_KEY=super-secret-token';
const _bearerSentinel =
    'Bearer eyJhbGciOiJIUzI1NiJ9.'
    'eyJzdWIiOiJzZW50aW5lbCJ9.'
    'long-opaque-credential-payload';

class _RecordedTokenRead {
  const _RecordedTokenRead(this.forceRefresh);

  final bool forceRefresh;

  @override
  bool operator ==(Object other) {
    if (other is! _RecordedTokenRead) return false;
    return other.forceRefresh == forceRefresh;
  }

  @override
  int get hashCode => forceRefresh.hashCode;

  @override
  String toString() => 'readIdToken(forceRefresh: $forceRefresh)';
}

class _RecordingTokenReader implements FirebaseTokenReader {
  _RecordingTokenReader({this.token, this.error});

  final String? token;
  final Object? error;
  final List<_RecordedTokenRead> reads = [];

  @override
  Future<String?> readIdToken({required bool forceRefresh}) async {
    reads.add(_RecordedTokenRead(forceRefresh));
    if (error != null) {
      throw error!;
    }
    return token;
  }
}

Future<VoiceFailure> _captureFailure(_RecordingTokenReader reader) async {
  final provider = FirebaseVoiceAuthTokenProvider(reader);
  try {
    await provider.getIdToken();
    fail('Expected a VoiceFailure while acquiring an ID token.');
  } on VoiceFailure catch (failure) {
    return failure;
  }
}

void main() {
  group('forceRefresh forwarding', () {
    test('defaults forceRefresh to false and reads exactly once', () async {
      final reader = _RecordingTokenReader(token: 'id-token');
      await FirebaseVoiceAuthTokenProvider(reader).getIdToken();

      expect(reader.reads, const [_RecordedTokenRead(false)]);
    });

    test('forwards forceRefresh true exactly', () async {
      final reader = _RecordingTokenReader(token: 'id-token');
      await FirebaseVoiceAuthTokenProvider(
        reader,
      ).getIdToken(forceRefresh: true);

      expect(reader.reads, const [_RecordedTokenRead(true)]);
    });
  });

  test('trims a returned token before exposing it', () async {
    const expected = 'id-token';
    final reader = _RecordingTokenReader(token: '  \t$expected \n');
    final token = await FirebaseVoiceAuthTokenProvider(reader).getIdToken();

    expect(token, expected);
  });

  group('missing token', () {
    for (final (label, token) in <(String, String?)>[
      ('null', null),
      ('empty', ''),
      ('whitespace-only', '   \t\n '),
    ]) {
      test('rejects a $label token as an authentication failure', () async {
        final failure = await _captureFailure(
          _RecordingTokenReader(token: token),
        );

        expect(failure.category, VoiceFailureCategory.authentication);
      });
    }

    test('uses one fixed safe message for every missing token', () async {
      final nullFailure = await _captureFailure(
        _RecordingTokenReader(token: null),
      );
      final emptyFailure = await _captureFailure(
        _RecordingTokenReader(token: ''),
      );
      final whitespaceFailure = await _captureFailure(
        _RecordingTokenReader(token: '  \t '),
      );

      expect(nullFailure.toString(), emptyFailure.toString());
      expect(emptyFailure.toString(), whitespaceFailure.toString());
    });
  });

  group('reader exceptions', () {
    test('any exception becomes a fixed authentication failure', () async {
      final first = await _captureFailure(
        _RecordingTokenReader(error: StateError('user signed out')),
      );
      final second = await _captureFailure(
        _RecordingTokenReader(
          error: Exception('network unavailable during refresh'),
        ),
      );

      expect(first.category, VoiceFailureCategory.authentication);
      expect(second.category, VoiceFailureCategory.authentication);
      expect(first.toString(), second.toString());
    });

    test('never exposes credential or bearer sentinels', () async {
      final credentialFailure = await _captureFailure(
        _RecordingTokenReader(
          error: Exception('refresh failed exposing $_credentialSentinel'),
        ),
      );
      final bearerFailure = await _captureFailure(
        _RecordingTokenReader(error: Exception(_bearerSentinel)),
      );

      expect(
        credentialFailure.toString(),
        isNot(contains(_credentialSentinel)),
      );
      expect(
        credentialFailure.toString(),
        isNot(contains('refresh failed exposing')),
      );
      expect(bearerFailure.toString(), isNot(contains(_bearerSentinel)));
      expect(bearerFailure.toString(), isNot(contains('Bearer')));
    });

    test('matches a missing-token failure exactly', () async {
      final exceptionFailure = await _captureFailure(
        _RecordingTokenReader(error: StateError('boom')),
      );
      final missingFailure = await _captureFailure(
        _RecordingTokenReader(token: null),
      );

      expect(exceptionFailure.toString(), missingFailure.toString());
    });
  });

  test('implements VoiceAuthTokenProvider', () {
    expect(
      FirebaseVoiceAuthTokenProvider(_RecordingTokenReader()),
      isA<VoiceAuthTokenProvider>(),
    );
  });
}

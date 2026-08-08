import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_request_quota.dart';
import 'package:vocab_learning_app/voice/vox_cpm_standard_provider.dart';

final _baseUri = Uri.parse('https://voice.example.com');

VoiceRequest _request({
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) {
  return VoiceRequest.create(
    text: 'Hello world.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1,
    contentId: 'word-1',
    contentType: 'word',
    mode: VoiceMode.practice,
    capability: capability,
    privacyScope: privacyScope,
  );
}

http.Response _wav() => http.Response.bytes(
  Uint8List.fromList(utf8.encode('RIFF-voxcpm')),
  200,
  headers: const {
    'content-type': 'audio/wav',
    'x-request-id': 'req-voxcpm',
    'x-voice-engine': 'voxcpm2',
    'x-model-version': '2.0.3',
    'x-audio-sample-rate': '48000',
  },
);

final class _Tokens implements VoiceAuthTokenProvider {
  final calls = <bool>[];

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    calls.add(forceRefresh);
    return forceRefresh ? 'fresh-token' : 'old-token';
  }
}

void main() {
  test('declares only standard-content target speech capabilities', () {
    final provider = VoxCpmStandardProvider(
      client: MockClient((_) async => _wav()),
      authTokenProvider: _Tokens(),
      baseUri: _baseUri,
    );

    expect(provider.descriptor.engine, VoiceEngine.voxCpmStandard);
    expect(provider.descriptor.capabilities, {
      VoiceCapability.standardTargetSpeech,
      VoiceCapability.dynamicTargetSpeech,
    });
    expect(provider.descriptor.allowsStandardCache, isTrue);
    expect(
      provider.descriptor.supports(VoiceCapability.sessionVoiceMirror),
      isFalse,
    );
  });

  test(
    'posts bounded standard speech fields and parses 48kHz provenance',
    () async {
      http.Request? recorded;
      final tokens = _Tokens();
      final provider = VoxCpmStandardProvider(
        client: MockClient((request) async {
          recorded = request;
          return _wav();
        }),
        authTokenProvider: tokens,
        baseUri: _baseUri,
      );

      final audio = await provider.synthesize(_request());

      expect(recorded?.url, _baseUri.resolve('/v1/speech'));
      expect(recorded?.headers['authorization'], 'Bearer old-token');
      expect(jsonDecode(recorded!.body), {
        'text': 'Hello world.',
        'language': 'en',
        'voice': 'teacher_female',
        'speed': 1.0,
        'format': 'wav',
      });
      expect(tokens.calls, [false]);
      expect(audio.engine, VoiceEngine.voxCpmStandard);
      expect(audio.requestId, 'req-voxcpm');
      expect(audio.modelVersion, '2.0.3');
      expect(audio.sampleRate, 48000);
    },
  );

  test('refreshes authentication exactly once after the first 401', () async {
    var calls = 0;
    final tokens = _Tokens();
    final provider = VoxCpmStandardProvider(
      client: MockClient((request) async {
        calls++;
        return calls == 1 ? http.Response('', 401) : _wav();
      }),
      authTokenProvider: tokens,
      baseUri: _baseUri,
    );

    await provider.synthesize(_request());

    expect(calls, 2);
    expect(tokens.calls, [false, true]);
  });

  test(
    'maps the backend provider kill switch without leaking its body',
    () async {
      const sentinel = 'private-provider-body';
      final provider = VoxCpmStandardProvider(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":{"code":"PROVIDER_DISABLED","message":"$sentinel"}}',
            503,
          ),
        ),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      VoiceFailure? failure;
      try {
        await provider.synthesize(_request());
      } on VoiceFailure catch (error) {
        failure = error;
      }

      expect(failure?.category, VoiceFailureCategory.providerDisabled);
      expect(failure.toString(), isNot(contains(sentinel)));
    },
  );

  test('rejects participant-transient mirror requests before HTTP', () async {
    var sends = 0;
    final provider = VoxCpmStandardProvider(
      client: MockClient((_) async {
        sends++;
        return _wav();
      }),
      authTokenProvider: _Tokens(),
      baseUri: _baseUri,
    );

    await expectLater(
      provider.synthesize(
        _request(
          capability: VoiceCapability.sessionVoiceMirror,
          privacyScope: VoicePrivacyScope.participantTransient,
        ),
      ),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.unsupportedCapability,
        ),
      ),
    );
    expect(sends, 0);
  });

  test('bounds dynamic speech before issuing another HTTP request', () async {
    var sends = 0;
    final provider = VoxCpmStandardProvider(
      client: MockClient((_) async {
        sends++;
        return _wav();
      }),
      authTokenProvider: _Tokens(),
      baseUri: _baseUri,
      quota: VoiceRequestQuota(
        maxRequests: 1,
        maxCharacters: 100,
        maxConcurrent: 1,
      ),
    );
    final request = _request(capability: VoiceCapability.dynamicTargetSpeech);

    await provider.synthesize(request);
    await expectLater(
      provider.synthesize(request),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.rateLimited,
        ),
      ),
    );

    expect(sends, 1);
  });

  test('short-circuits after a transient provider outage', () async {
    var sends = 0;
    final breaker = CircuitBreaker(threshold: 1);
    final provider = VoxCpmStandardProvider(
      client: MockClient((_) async {
        sends++;
        throw http.ClientException('offline');
      }),
      authTokenProvider: _Tokens(),
      baseUri: _baseUri,
      circuitBreaker: breaker,
    );

    await expectLater(
      provider.synthesize(_request()),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.network,
        ),
      ),
    );
    await expectLater(
      provider.synthesize(_request()),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.rateLimited,
        ),
      ),
    );
    expect(sends, 1);
    expect(provider.circuitState, CircuitState.open);
  });
}

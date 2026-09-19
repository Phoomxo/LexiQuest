import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/voice/omni_voice_provider.dart';
import 'package:vocab_learning_app/voice/vox_cpm_standard_provider.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';

final _request = VoiceRequest.create(
  text: 'Hello',
  language: 'en',
  voiceId: 'teacher',
  speed: 1,
  contentId: 'test',
  contentType: 'word',
  mode: VoiceMode.practice,
);

void main() {
  for (final vox in [true, false]) {
    VoiceSynthesisProvider provider(_Client client, {_Tokens? tokens}) => vox
        ? VoxCpmStandardProvider(
            client: client,
            authTokenProvider: tokens ?? _Tokens(),
            baseUri: Uri.parse('https://invalid.example'),
            timeout: const Duration(milliseconds: 50),
          )
        : OmniVoiceProvider(
            client: client,
            authTokenProvider: tokens ?? _Tokens(),
            baseUri: Uri.parse('https://invalid.example'),
            timeout: const Duration(milliseconds: 50),
          );
    Map<String, String> headers() => {
      'content-type': 'audio/wav',
      'x-request-id': 'synthetic',
      'x-voice-engine': vox ? 'voxcpm2' : 'omnivoice',
      'x-model-version': 'test',
      'x-audio-sample-rate': '24000',
    };

    test('$vox accepts the exact WAV byte limit across chunks', () async {
      final bytes = Uint8List(8 * 1024 * 1024);
      final client = _Client(
        (_) async => http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 1024), bytes.sublist(1024)]),
          200,
          headers: headers(),
        ),
      );
      final audio = await provider(client).synthesize(_request);
      expect(audio.bytes.length, bytes.length);
      expect(
        audio.engine,
        vox ? VoiceEngine.voxCpmStandard : VoiceEngine.omniVoice,
      );
    });

    test(
      '$vox rejects oversized declared length without waiting for body',
      () async {
        var cancelled = 0;
        final stream = StreamController<List<int>>(
          onCancel: () {
            cancelled++;
          },
        );
        final client = _Client(
          (_) async => http.StreamedResponse(
            stream.stream,
            200,
            contentLength: 8 * 1024 * 1024 + 1,
            headers: headers(),
          ),
        );
        await expectLater(
          provider(client).synthesize(_request),
          throwsA(
            isA<VoiceFailure>().having(
              (e) => e.category,
              'category',
              VoiceFailureCategory.synthesis,
            ),
          ),
        );
        expect(cancelled, 1);
        await stream.close();
      },
    );

    for (final status in [200, 500]) {
      test('$vox rejects oversized $status body and cancels stream', () async {
        var cancelled = 0;
        final stream = StreamController<List<int>>(
          onCancel: () {
            cancelled++;
          },
        );
        final client = _Client(
          (_) async =>
              http.StreamedResponse(stream.stream, status, headers: headers()),
        );
        final result = provider(client).synthesize(_request);
        final check = expectLater(result, throwsA(isA<VoiceFailure>()));
        stream.add(
          Uint8List((status == 200 ? 8 * 1024 * 1024 : 64 * 1024) + 1),
        );
        await stream.close();
        await check;
        expect(cancelled, 1);
        expect(client.aborted, isTrue);
      });
    }

    test(
      '$vox stalled body timeout cancels subscription and aborts request',
      () async {
        var cancelled = 0;
        final stream = StreamController<List<int>>(
          onCancel: () {
            cancelled++;
          },
        );
        final client = _Client(
          (_) async =>
              http.StreamedResponse(stream.stream, 200, headers: headers()),
        );
        await expectLater(
          provider(client).synthesize(_request),
          throwsA(
            isA<VoiceFailure>().having(
              (e) => e.category,
              'category',
              VoiceFailureCategory.timeout,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, 1);
        expect(client.aborted, isTrue);
        await stream.close();
      },
    );

    test('$vox late response is discarded and its stream cancelled', () async {
      var cancelled = 0;
      final response = Completer<http.StreamedResponse>();
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled++;
        },
      );
      final client = _Client((_) => response.future);
      await expectLater(
        provider(client).synthesize(_request),
        throwsA(isA<VoiceFailure>()),
      );
      response.complete(
        http.StreamedResponse(stream.stream, 200, headers: headers()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(client.aborted, isTrue);
      expect(cancelled, 1);
      await stream.close();
    });

    test('$vox late token never starts a retired request', () async {
      final token = Completer<String>();
      final client = _Client(
        (_) async =>
            http.StreamedResponse(Stream.value([1]), 200, headers: headers()),
      );
      await expectLater(
        provider(client, tokens: _Tokens(token.future)).synthesize(_request),
        throwsA(isA<VoiceFailure>()),
      );
      token.complete('late-token');
      await Future<void>.delayed(Duration.zero);
      expect(client.sends, 0);
    });
  }
}

class _Tokens implements VoiceAuthTokenProvider {
  _Tokens([this.pending]);
  final Future<String>? pending;
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async =>
      pending ?? 'synthetic';
}

class _Client extends http.BaseClient {
  _Client(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  int sends = 0;
  bool aborted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sends++;
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) {
        aborted = true;
      });
    }
    return respond(request);
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_service_factory.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

const _wavBytes = <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x57,
  0x41,
  0x56,
  0x45,
];
const _idToken = 'id-token';
const _requestId = 'req-123';
const _modelVersion = 'voxcpm2-2.0.3';
// Synthetic Pair pronunciation metadata: neither the text nor an owner id is
// embedded in the identifier forwarded to the existing telemetry contract.
const _pairContentId = 'ad738345-64c4-4626-8f32-c55e2f30ac8c';
const _pairText = 'Synthetic blue lantern.';

VoiceRequest _pairRequest({bool localOnly = true}) => VoiceRequest.create(
  text: _pairText,
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1.0,
  contentId: _pairContentId,
  contentType: 'pairPronunciation',
  mode: VoiceMode.practice,
  localOnly: localOnly,
);

AppConfig _config() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  isDebug: true,
);

VoiceRequest _request({
  String text = 'Hello world.',
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  String contentId = 'word-001',
}) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1.0,
  contentId: contentId,
  contentType: 'word',
  mode: VoiceMode.practice,
  capability: capability,
);

http.Response _wavResponse() => http.Response.bytes(
  Uint8List.fromList(_wavBytes),
  200,
  headers: const <String, String>{
    'content-type': 'audio/wav',
    'x-request-id': _requestId,
    'x-voice-engine': 'voxcpm2',
    'x-model-version': _modelVersion,
    'x-audio-sample-rate': '24000',
  },
);

Future<InstalledStandardVoicePack> _installedPack({
  String contentId = 'word-001',
  String text = 'Hello world.',
}) async {
  final root = await Directory.systemTemp.createTemp('factory-pack-');
  addTearDown(() => root.delete(recursive: true));
  final bytes = Uint8List.fromList(_wavBytes);
  final file = File('${root.path}${Platform.pathSeparator}hello.wav');
  await file.writeAsBytes(bytes);
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
        'contentId': contentId,
        'normalizedTextSha256': sha256.convert(utf8.encode(text)).toString(),
        'relativePath': 'hello.wav',
        'byteSize': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
    ],
  });
  return InstalledStandardVoicePack(
    rootPath: root.path,
    manifest: manifest,
    activeMarkerPath: '${root.path}.active',
  );
}

void main() {
  test('factory wires authenticated VoxCPM2 playback and telemetry', () async {
    final config = _config();
    final tokenReader = _RecordingTokenReader(_idToken);
    final client = _RecordingHttpClient((_) async => _wavResponse());
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final sink = _RecordingTelemetrySink();

    final service = VoiceServiceFactory.create(
      config: config,
      client: client,
      firebaseTokenReader: tokenReader,
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
      telemetrySink: sink,
    );

    expect(service, isA<ManagedVoiceService>());
    expect(service, isA<VoiceProvider>());

    final result = await service.speak(_request());

    expect(client.requests, hasLength(1));
    final request = client.requests.single;
    expect(request.method, 'POST');
    expect(request.url, config.voiceApiBaseUri.resolve('/v1/speech'));
    expect(request.headers['authorization'], 'Bearer $_idToken');
    expect(request.headers['content-type'], 'application/json');
    expect(tokenReader.forceRefreshFlags, <bool>[false]);
    expect(jsonDecode(request.body), <String, Object>{
      'text': 'Hello world.',
      'language': 'en',
      'voice': 'teacher_female',
      'speed': 1.0,
      'format': 'wav',
    });

    expect(player.playBytesCalls, hasLength(1));
    expect(player.playBytesCalls.single, Uint8List.fromList(_wavBytes));
    expect(native.speakCalls, isEmpty);
    expect(result.requestedEngine, VoiceEngine.voxCpmStandard);
    expect(result.actualEngine, VoiceEngine.voxCpmStandard);
    expect(result.usedFallback, isFalse);
    expect(result.requestId, _requestId);
    expect(result.modelVersion, _modelVersion);

    expect(sink.events, hasLength(1));
    final event = sink.events.single;
    expect(event.outcome, VoiceTelemetryOutcome.succeeded);
    expect(event.requestedEngine, VoiceEngine.voxCpmStandard);
    expect(event.actualEngine, VoiceEngine.voxCpmStandard);
    expect(event.usedFallback, isFalse);
    expect(event.fallbackReason, isNull);
    expect(event.requestId, _requestId);
    expect(event.modelVersion, _modelVersion);
    // Telemetry v2 stamps the policy-resolved route onto every event.
    expect(event.capability, VoiceCapability.standardTargetSpeech);
    expect(event.privacyScope, VoicePrivacyScope.standardContent);
    expect(event.schemaVersion, 'voice_telemetry_v2');
  });

  test('factory preserves OmniVoice as an explicit rollback engine', () async {
    final client = _RecordingHttpClient((_) async => _wavResponse());
    final native = _RecordingNativeTtsAdapter();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: _RecordingTokenReader(_idToken),
      nativeTtsAdapter: native,
      audioPlayerAdapter: _RecordingAudioPlayerAdapter(),
      useOmniVoiceRollback: true,
      dynamicMaxRequests: 1,
    );

    final result = await service.speak(
      _request(capability: VoiceCapability.dynamicTargetSpeech),
    );

    expect(result.requestedEngine, VoiceEngine.omniVoice);
    expect(result.actualEngine, VoiceEngine.omniVoice);
    expect(result.usedFallback, isFalse);

    final quotaResult = await service.speak(
      _request(
        text: 'Different world.',
        capability: VoiceCapability.dynamicTargetSpeech,
        contentId: 'word-002',
      ),
    );
    expect(client.sendCount, 1);
    expect(quotaResult.requestedEngine, VoiceEngine.omniVoice);
    expect(quotaResult.actualEngine, VoiceEngine.nativeTts);
    expect(quotaResult.usedFallback, isTrue);
    expect(native.speakCalls, <String>['Different world.']);
  });

  test('factory prefers an installed verified pack without HTTP', () async {
    final client = _RecordingHttpClient((_) async => _wavResponse());
    final player = _RecordingAudioPlayerAdapter();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: _RecordingTokenReader(_idToken),
      nativeTtsAdapter: _RecordingNativeTtsAdapter(),
      audioPlayerAdapter: player,
      installedVoicePack: await _installedPack(),
    );

    final result = await service.speak(_request());

    expect(client.sendCount, 0);
    expect(result.requestedEngine, VoiceEngine.offlinePack);
    expect(result.actualEngine, VoiceEngine.offlinePack);
    expect(player.playBytesCalls, hasLength(1));
  });

  group('local-only Pair pronunciation through the full facade', () {
    for (final rollback in <bool>[false, true]) {
      final remoteEngine = rollback
          ? VoiceEngine.omniVoice
          : VoiceEngine.voxCpmStandard;
      test(
        'online ${remoteEngine.name} is skipped locally and remains available '
        'to the default route',
        () async {
          final tokenReader = _RecordingTokenReader(_idToken);
          final client = _RecordingHttpClient((_) async => _wavResponse());
          final native = _RecordingLocalNativeTtsAdapter();
          final player = _RecordingAudioPlayerAdapter();
          final sink = _RecordingTelemetrySink();
          final service = VoiceServiceFactory.create(
            config: _config(),
            client: client,
            firebaseTokenReader: tokenReader,
            nativeTtsAdapter: native,
            audioPlayerAdapter: player,
            telemetrySink: sink,
            useOmniVoiceRollback: rollback,
          );
          final facade = VoiceUseCases(
            provider: service,
            disposeProvider: service.dispose,
          );
          addTearDown(facade.dispose);
          final session = facade.acquireSession();
          addTearDown(session.release);

          final localResult = await session.speak(_pairRequest());

          expect(localResult.requestedEngine, VoiceEngine.nativeTts);
          expect(localResult.actualEngine, VoiceEngine.nativeTts);
          expect(localResult.usedFallback, isFalse);
          expect(client.requests, isEmpty);
          expect(client.sendCount, 0);
          expect(tokenReader.forceRefreshFlags, isEmpty);
          expect(player.playBytesCalls, isEmpty);
          expect(native.speakCalls, <String>[_pairText]);
          // These calls originate in the real NativeTtsProvider after the
          // orchestrator copies the request. Losing localOnly at that boundary
          // would bypass the installed/nonnetwork proof and fail this check.
          expect(native.localCalls, <String>[
            'installed:en-US',
            'voices',
            'language:en-US',
            'select:synthetic-local-en:en-US',
            'speak',
          ]);
          _expectSafePairTelemetry(sink.events.single);

          // A successful ordinary request on this same service proves that
          // the remote route and auth fixture really were enabled and online.
          final ordinaryResult = await session.speak(
            _pairRequest(localOnly: false),
          );

          expect(ordinaryResult.requestedEngine, remoteEngine);
          expect(ordinaryResult.actualEngine, remoteEngine);
          expect(ordinaryResult.usedFallback, isFalse);
          expect(client.sendCount, 1);
          expect(client.requests, hasLength(1));
          expect(
            client.requests.single.headers['authorization'],
            'Bearer $_idToken',
          );
          expect(
            (jsonDecode(client.requests.single.body) as Map)['text'],
            _pairText,
          );
          expect(tokenReader.forceRefreshFlags, <bool>[false]);
          expect(player.playBytesCalls, hasLength(1));
          expect(native.speakCalls, <String>[_pairText]);
          expect(sink.events, hasLength(2));
          _expectSafePairTelemetry(sink.events.last);
        },
      );
    }

    test(
      'verified installed pack plays locally without native or auth',
      () async {
        final tokenReader = _RecordingTokenReader(_idToken);
        final client = _RecordingHttpClient((_) async => _wavResponse());
        final native = _RecordingLocalNativeTtsAdapter();
        final player = _RecordingAudioPlayerAdapter();
        final sink = _RecordingTelemetrySink();
        final service = VoiceServiceFactory.create(
          config: _config(),
          client: client,
          firebaseTokenReader: tokenReader,
          nativeTtsAdapter: native,
          audioPlayerAdapter: player,
          telemetrySink: sink,
          installedVoicePack: await _installedPack(
            contentId: _pairContentId,
            text: _pairText,
          ),
        );
        final facade = VoiceUseCases(
          provider: service,
          disposeProvider: service.dispose,
        );
        addTearDown(facade.dispose);
        final session = facade.acquireSession();
        addTearDown(session.release);

        final result = await session.speak(_pairRequest());

        expect(result.requestedEngine, VoiceEngine.offlinePack);
        expect(result.actualEngine, VoiceEngine.offlinePack);
        expect(result.usedFallback, isFalse);
        expect(player.playBytesCalls, <Uint8List>[
          Uint8List.fromList(_wavBytes),
        ]);
        expect(native.speakCalls, isEmpty);
        expect(native.localCalls, isEmpty);
        expect(client.requests, isEmpty);
        expect(client.sendCount, 0);
        expect(tokenReader.forceRefreshFlags, isEmpty);
        _expectSafePairTelemetry(sink.events.single);
      },
    );

    for (final corruptPack in <bool>[false, true]) {
      final reason = corruptPack
          ? VoiceFailureCategory.checksumMismatch
          : VoiceFailureCategory.modelUnavailable;
      test(
        'installed pack ${reason.name} falls back only to proven native',
        () async {
          final pack = await _installedPack(
            contentId: corruptPack ? _pairContentId : 'word-001',
            text: _pairText,
          );
          if (corruptPack) {
            // Keep the real manifest and byte length, but change the actual file
            // so InstalledVoicePackProvider must reject its SHA-256.
            final corrupted = Uint8List.fromList(_wavBytes)..[0] = 0;
            await File(pack.pathFor('hello.wav')).writeAsBytes(corrupted);
          }
          final tokenReader = _RecordingTokenReader(_idToken);
          final client = _RecordingHttpClient((_) async => _wavResponse());
          final native = _RecordingLocalNativeTtsAdapter();
          final player = _RecordingAudioPlayerAdapter();
          final sink = _RecordingTelemetrySink();
          final service = VoiceServiceFactory.create(
            config: _config(),
            client: client,
            firebaseTokenReader: tokenReader,
            nativeTtsAdapter: native,
            audioPlayerAdapter: player,
            telemetrySink: sink,
            installedVoicePack: pack,
          );
          final facade = VoiceUseCases(
            provider: service,
            disposeProvider: service.dispose,
          );
          addTearDown(facade.dispose);
          final session = facade.acquireSession();
          addTearDown(session.release);

          final result = await session.speak(_pairRequest());

          expect(result.requestedEngine, VoiceEngine.offlinePack);
          expect(result.actualEngine, VoiceEngine.nativeTts);
          expect(result.usedFallback, isTrue);
          expect(sink.events.single.fallbackReason, reason);
          expect(native.speakCalls, <String>[_pairText]);
          expect(native.localCalls, <String>[
            'installed:en-US',
            'voices',
            'language:en-US',
            'select:synthetic-local-en:en-US',
            'speak',
          ]);
          expect(player.playBytesCalls, isEmpty);
          expect(client.requests, isEmpty);
          expect(client.sendCount, 0);
          expect(tokenReader.forceRefreshFlags, isEmpty);
          _expectSafePairTelemetry(sink.events.single);
        },
      );
    }

    for (final unavailable in <String>[
      'unsupported proof capability',
      'language not installed',
      'network-only voice',
      'voice selection not acknowledged',
    ]) {
      test(
        '$unavailable fails safely after a pack miss without remote speech',
        () async {
          final _RecordingNativeTtsAdapter native = switch (unavailable) {
            'unsupported proof capability' => _RecordingNativeTtsAdapter(),
            'language not installed' => _RecordingLocalNativeTtsAdapter(
              languageInstalled: false,
            ),
            'network-only voice' => _RecordingLocalNativeTtsAdapter(
              voices: const <Map<String, String>>[
                <String, String>{
                  'name': 'synthetic-network-en',
                  'locale': 'en-US',
                  'network_required': '1',
                  'features': '',
                },
              ],
            ),
            _ => _RecordingLocalNativeTtsAdapter(selectionResult: 0),
          };
          final tokenReader = _RecordingTokenReader(_idToken);
          final client = _RecordingHttpClient((_) async => _wavResponse());
          final player = _RecordingAudioPlayerAdapter();
          final sink = _RecordingTelemetrySink();
          final service = VoiceServiceFactory.create(
            config: _config(),
            client: client,
            firebaseTokenReader: tokenReader,
            nativeTtsAdapter: native,
            audioPlayerAdapter: player,
            telemetrySink: sink,
            installedVoicePack: await _installedPack(),
          );
          final facade = VoiceUseCases(
            provider: service,
            disposeProvider: service.dispose,
          );
          addTearDown(facade.dispose);
          final session = facade.acquireSession();
          addTearDown(session.release);

          await expectLater(
            session.speak(_pairRequest()),
            throwsA(
              isA<VoiceFailure>()
                  .having(
                    (failure) => failure.category,
                    'category',
                    VoiceFailureCategory.synthesis,
                  )
                  .having(
                    (failure) => failure.message,
                    'privacy-safe message',
                    isNot(contains(_pairText)),
                  ),
            ),
          );

          expect(native.speakCalls, isEmpty);
          expect(player.playBytesCalls, isEmpty);
          expect(client.requests, isEmpty);
          expect(client.sendCount, 0);
          expect(tokenReader.forceRefreshFlags, isEmpty);
          expect(sink.events, hasLength(1));
          expect(sink.events.single.outcome, VoiceTelemetryOutcome.failed);
          expect(
            sink.events.single.failureCategory,
            VoiceFailureCategory.synthesis,
          );
          _expectSafePairTelemetry(sink.events.single);
        },
      );
    }
  });

  test('factory-wired network failure falls back to native TTS', () async {
    final tokenReader = _RecordingTokenReader(_idToken);
    final client = _RecordingHttpClient(
      (_) async => throw http.ClientException('network sentinel'),
    );
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final sink = _RecordingTelemetrySink();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: tokenReader,
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
      telemetrySink: sink,
    );

    final result = await service.speak(_request());

    expect(client.sendCount, 1);
    expect(tokenReader.forceRefreshFlags, <bool>[false]);
    expect(native.speakCalls, <String>['Hello world.']);
    expect(player.playBytesCalls, isEmpty);
    expect(result.requestedEngine, VoiceEngine.voxCpmStandard);
    expect(result.actualEngine, VoiceEngine.nativeTts);
    expect(result.usedFallback, isTrue);
    expect(sink.events, hasLength(1));
    expect(sink.events.single.actualEngine, VoiceEngine.nativeTts);
    expect(sink.events.single.fallbackReason, VoiceFailureCategory.network);
  });

  test('factory without a remote endpoint routes only to native TTS with no '
      'fallback', () async {
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final sink = _RecordingTelemetrySink();

    final service = VoiceServiceFactory.create(
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
      telemetrySink: sink,
    );

    final result = await service.speak(_request());

    // With no remote endpoint, only native is registered and routed: the HTTP
    // client is never used and no remote audio is played back.
    expect(player.playBytesCalls, isEmpty);
    expect(native.speakCalls, <String>['Hello world.']);

    // Native is the requested engine, not a fallback from a missing remote.
    expect(result.requestedEngine, VoiceEngine.nativeTts);
    expect(result.actualEngine, VoiceEngine.nativeTts);
    expect(result.usedFallback, isFalse);

    expect(sink.events, hasLength(1));
    final event = sink.events.single;
    expect(event.outcome, VoiceTelemetryOutcome.succeeded);
    expect(event.requestedEngine, VoiceEngine.nativeTts);
    expect(event.actualEngine, VoiceEngine.nativeTts);
    expect(event.usedFallback, isFalse);
    expect(event.fallbackReason, isNull);
    expect(event.capability, VoiceCapability.standardTargetSpeech);
    expect(event.privacyScope, VoicePrivacyScope.standardContent);

    await service.dispose();
    expect(player.disposeCount, 1);
  });

  test('remote configuration and owned client are an explicit pair', () {
    expect(
      () => VoiceServiceFactory.create(
        config: _config(),
        nativeTtsAdapter: _RecordingNativeTtsAdapter(),
      ),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.configuration,
        ),
      ),
    );
    expect(
      () => VoiceServiceFactory.create(
        client: _RecordingHttpClient((_) async => _wavResponse()),
        nativeTtsAdapter: _RecordingNativeTtsAdapter(),
      ),
      throwsA(isA<VoiceFailure>()),
    );
  });

  test(
    'remote timeout still reaches native fallback within the route budget',
    () async {
      final never = Completer<http.Response>();
      final client = _RecordingHttpClient((_) => never.future);
      final native = _RecordingNativeTtsAdapter();
      final service = VoiceServiceFactory.create(
        config: _config(),
        client: client,
        firebaseTokenReader: _RecordingTokenReader(_idToken),
        nativeTtsAdapter: native,
        audioPlayerAdapter: _RecordingAudioPlayerAdapter(),
        timeout: const Duration(milliseconds: 10),
      );

      final facade = VoiceUseCases(
        provider: service,
        disposeProvider: service.dispose,
        operationTimeout: const Duration(milliseconds: 100),
      );
      final session = facade.acquireSession();
      final result = await session
          .speak(_request())
          .timeout(const Duration(milliseconds: 200));

      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isTrue);
      expect(native.speakCalls, <String>['Hello world.']);
      await session.release();
      await facade.dispose();
    },
  );

  test('dispose owns every resource exactly once and is idempotent', () async {
    final client = _RecordingHttpClient((_) async => _wavResponse());
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: _RecordingTokenReader(_idToken),
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
    );

    await service.dispose();
    await service.dispose();

    expect(client.sendCount, 0);
    expect(native.stopCount, 1);
    // The standard and mirror synthesis handlers each share one audio player
    // and stop it during teardown.
    expect(player.stopCount, 2);
    expect(player.disposeCount, 1);
    expect(client.closeCount, 1);
  });

  test('managed disposal continues after a provider stop deadline', () async {
    final blockedStop = Completer<void>();
    final native = _RecordingNativeTtsAdapter(stopGate: blockedStop.future);
    final player = _RecordingAudioPlayerAdapter();
    final service = VoiceServiceFactory.create(
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
      cleanupTimeout: const Duration(milliseconds: 20),
    );

    final firstDispose = service.dispose();
    await expectLater(
      firstDispose.timeout(const Duration(seconds: 1)),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.cleanupIncomplete,
        ),
      ),
    );
    expect(native.stopCount, 1);
    expect(player.disposeCount, 1);
    await expectLater(service.dispose(), throwsA(isA<VoiceFailure>()));
    expect(player.disposeCount, 1);

    blockedStop.complete();
  });

  group('session voice mirror', () {
    test('does not register the mirror when Cloud config is absent', () {
      final service = VoiceServiceFactory.create(
        nativeTtsAdapter: _RecordingNativeTtsAdapter(),
        audioPlayerAdapter: _RecordingAudioPlayerAdapter(),
        firebaseTokenReader: _RecordingTokenReader(_idToken),
      );

      expect(service.voiceMirrorController, isNull);
    });

    test('registers the mirror controller when Cloud config is present', () {
      final client = _RecordingHttpClient((_) async => _wavResponse());
      final service = VoiceServiceFactory.create(
        config: _config(),
        client: client,
        nativeTtsAdapter: _RecordingNativeTtsAdapter(),
        audioPlayerAdapter: _RecordingAudioPlayerAdapter(),
        firebaseTokenReader: _RecordingTokenReader(_idToken),
      );

      final controller = service.voiceMirrorController;
      expect(controller, isNotNull);
      expect(controller!.hasConsent, isFalse);
      expect(controller.isActive, isFalse);
    });

    test(
      'a mirror request without consent is rejected, not silently routed',
      () async {
        final client = _RecordingHttpClient((_) async => _wavResponse());
        final native = _RecordingNativeTtsAdapter();
        final sink = _RecordingTelemetrySink();
        final service = VoiceServiceFactory.create(
          config: _config(),
          client: client,
          nativeTtsAdapter: native,
          audioPlayerAdapter: _RecordingAudioPlayerAdapter(),
          firebaseTokenReader: _RecordingTokenReader(_idToken),
          telemetrySink: sink,
        );

        // Consent is absent, so the mirror route is unavailable. Privacy policy
        // requires an explicit rejection rather than a silent standard fallback.
        await expectLater(
          service.speak(
            VoiceRequest.create(
              text: 'Cat',
              language: 'en',
              voiceId: 'mirror',
              speed: 1,
              contentId: 'word-cat',
              contentType: 'word',
              mode: VoiceMode.practice,
              capability: VoiceCapability.sessionVoiceMirror,
              privacyScope: VoicePrivacyScope.participantTransient,
            ),
          ),
          throwsA(
            isA<VoiceFailure>().having(
              (failure) => failure.category,
              'category',
              VoiceFailureCategory.consentMissing,
            ),
          ),
        );
        expect(client.sendCount, 0);
        expect(native.speakCalls, isEmpty);
      },
    );
  });
}

void _expectSafePairTelemetry(VoiceTelemetryEvent event) {
  expect(event.contentId, _pairContentId);
  expect(event.contentType, 'pairPronunciation');
  expect(event.privacyScope, VoicePrivacyScope.standardContent);
  final serialized = jsonEncode(event.toMap());
  expect(serialized, isNot(contains(_pairText)));
  expect(serialized, isNot(contains(_idToken)));
  expect(event.toMap().keys, isNot(contains('text')));
  expect(event.toMap().keys, isNot(contains('ownerId')));
}

final class _RecordedRequest {
  _RecordedRequest(http.Request request)
    : method = request.method,
      url = request.url,
      headers = <String, String>{
        for (final entry in request.headers.entries)
          entry.key.toLowerCase(): entry.value,
      },
      body = request.body;

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

final class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  int sendCount = 0;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typedRequest = request as http.Request;
    requests.add(_RecordedRequest(typedRequest));
    sendCount++;
    final response = await _handler(typedRequest);
    return http.StreamedResponse(
      http.ByteStream(Stream<List<int>>.value(response.bodyBytes)),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      headers: response.headers,
    );
  }

  @override
  void close() {
    closeCount++;
  }
}

final class _RecordingTokenReader implements FirebaseTokenReader {
  _RecordingTokenReader(this._token);

  final String _token;
  final List<bool> forceRefreshFlags = <bool>[];

  @override
  Future<String?> readIdToken({required bool forceRefresh}) async {
    forceRefreshFlags.add(forceRefresh);
    return _token;
  }
}

final class _RecordingNativeTtsAdapter implements NativeTtsAdapter {
  _RecordingNativeTtsAdapter({this.stopGate});

  final Future<void>? stopGate;
  final List<String> speakCalls = <String>[];
  int stopCount = 0;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {
    speakCalls.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    await stopGate;
  }
}

final class _RecordingLocalNativeTtsAdapter extends _RecordingNativeTtsAdapter
    implements NativeTtsLocalVoiceAdapter {
  _RecordingLocalNativeTtsAdapter({
    this.languageInstalled = true,
    this.voices = const <Map<String, String>>[
      <String, String>{
        'name': 'synthetic-network-en',
        'locale': 'en-US',
        'network_required': '1',
        'features': '',
      },
      <String, String>{
        'name': 'synthetic-local-en',
        'locale': 'en-US',
        'network_required': '0',
        'features': '',
      },
    ],
    this.selectionResult = 1,
  });

  final Object? languageInstalled;
  final Object? voices;
  final Object? selectionResult;
  final List<String> localCalls = <String>[];

  @override
  Future<Object?> isLanguageInstalled(String language) async {
    localCalls.add('installed:$language');
    return languageInstalled;
  }

  @override
  Future<Object?> loadVoices() async {
    localCalls.add('voices');
    return voices;
  }

  @override
  Future<void> setLanguage(String language) async {
    localCalls.add('language:$language');
    await super.setLanguage(language);
  }

  @override
  Future<Object?> selectVoice({
    required String name,
    required String locale,
  }) async {
    localCalls.add('select:$name:$locale');
    return selectionResult;
  }

  @override
  Future<void> speak(String text) async {
    localCalls.add('speak');
    await super.speak(text);
  }
}

final class _RecordingAudioPlayerAdapter implements AudioPlayerAdapter {
  final List<Uint8List> playBytesCalls = <Uint8List>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playBytesCalls.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

final class _RecordingTelemetrySink implements VoiceTelemetrySink {
  final List<VoiceTelemetryEvent> events = <VoiceTelemetryEvent>[];

  @override
  Future<void> record(VoiceTelemetryEvent event) {
    events.add(event);
    return Future<void>.value();
  }
}

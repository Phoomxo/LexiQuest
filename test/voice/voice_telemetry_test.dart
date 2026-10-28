import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

const _schemaVersion = 'voice_telemetry_v2';

const _allowedKeys = <String>{
  'schemaVersion',
  'outcome',
  'mode',
  'capability',
  'privacyScope',
  'requestedEngine',
  'actualEngine',
  'usedFallback',
  'fallbackReason',
  'failureCategory',
  'cacheHit',
  'latencyMs',
  'contentId',
  'contentType',
  'requestId',
  'modelVersion',
  'occurredAtUtc',
};

const _bannedKeyTokens = <String>[
  'text',
  'token',
  'email',
  'uid',
  'audio',
  'user',
];

VoiceRequest _request({
  String text = 'Hello world.',
  String language = 'en',
  String voiceId = 'teacher_female',
  double speed = 1.0,
  String contentId = 'word-001',
  String contentType = 'word',
  VoiceMode mode = VoiceMode.practice,
  VoiceEngine? assignedEngine,
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) {
  // Respect the VoiceRequest mirror/transient invariant:
  // sessionVoiceMirror must pair with participantTransient, and any other
  // capability must pair with standardContent. Mismatches are rejected by
  // VoiceRequest.create, so surface them as the production validation error.
  final isMirror = capability == VoiceCapability.sessionVoiceMirror;
  final isTransient = privacyScope == VoicePrivacyScope.participantTransient;
  if (isMirror != isTransient) {
    throw ArgumentError(
      'capability and privacyScope must agree on the mirror/transient pairing',
    );
  }

  return VoiceRequest.create(
    text: text,
    language: language,
    voiceId: voiceId,
    speed: speed,
    contentId: contentId,
    contentType: contentType,
    mode: mode,
    assignedEngine: assignedEngine,
    capability: capability,
    privacyScope: privacyScope,
  );
}

void main() {
  group('VoiceTelemetryEvent.succeeded', () {
    test('extracts safe fields, marks outcome succeeded, preserves provenance '
        'and fallback state, normalizes occurredAtUtc to UTC, and serializes '
        'latencyMs', () {
      final request = _request(
        contentId: 'word-001',
        contentType: 'word',
        mode: VoiceMode.practice,
      );
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
        requestId: 'req-abc',
        modelVersion: 'omnivoice-2026-07',
      );
      final local = DateTime(2026, 7, 24, 10, 30, 0);

      final event = VoiceTelemetryEvent.succeeded(
        request: request,
        result: result,
        latency: const Duration(milliseconds: 250),
        occurredAtUtc: local,
      );

      expect(event.schemaVersion, _schemaVersion);
      expect(event.outcome, VoiceTelemetryOutcome.succeeded);
      expect(event.mode, VoiceMode.practice);
      expect(event.capability, VoiceCapability.standardTargetSpeech);
      expect(event.privacyScope, VoicePrivacyScope.standardContent);
      expect(event.requestedEngine, VoiceEngine.omniVoice);
      expect(event.actualEngine, VoiceEngine.omniVoice);
      expect(event.usedFallback, isFalse);
      expect(event.fallbackReason, isNull);
      expect(event.failureCategory, isNull);
      expect(event.cacheHit, isFalse);
      expect(event.contentId, 'word-001');
      expect(event.contentType, 'word');
      expect(event.requestId, 'req-abc');
      expect(event.modelVersion, 'omnivoice-2026-07');
      expect(event.latency, const Duration(milliseconds: 250));
      expect(event.occurredAtUtc, local.toUtc());
      expect(event.occurredAtUtc.isUtc, isTrue);

      final map = event.toMap();
      expect(map['schemaVersion'], _schemaVersion);
      expect(map['outcome'], 'succeeded');
      expect(map['mode'], 'practice');
      expect(map['capability'], 'standardTargetSpeech');
      expect(map['privacyScope'], 'standardContent');
      expect(map['requestedEngine'], 'omniVoice');
      expect(map['actualEngine'], 'omniVoice');
      expect(map['usedFallback'], isFalse);
      expect(map['fallbackReason'], isNull);
      expect(map['failureCategory'], isNull);
      expect(map['cacheHit'], isFalse);
      expect(map['latencyMs'], 250);
      expect(map['contentId'], 'word-001');
      expect(map['contentType'], 'word');
      expect(map['requestId'], 'req-abc');
      expect(map['modelVersion'], 'omnivoice-2026-07');
      expect(map['occurredAtUtc'], local.toUtc().toIso8601String());
      expect(map.containsKey('text'), isFalse);
      expect(map.containsKey('language'), isFalse);
      expect(map.containsKey('voiceId'), isFalse);
      expect(map.containsKey('speed'), isFalse);
    });

    test('derives capability and privacyScope from the request for every '
        'terminal outcome (succeeded, failed, cancelled)', () {
      final request = _request(
        capability: VoiceCapability.sessionVoiceMirror,
        privacyScope: VoicePrivacyScope.participantTransient,
      );
      final succeeded = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );
      final failed = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'Unable to reach the voice service.',
      );
      final cancelled = VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message: 'Playback was cancelled.',
      );
      final occurred = DateTime.utc(2026, 7, 24, 10, 30);

      final succeededEvent = VoiceTelemetryEvent.succeeded(
        request: request,
        result: succeeded,
        latency: const Duration(milliseconds: 100),
        occurredAtUtc: occurred,
      );
      final failedEvent = VoiceTelemetryEvent.failed(
        request: request,
        requestedEngine: VoiceEngine.omniVoice,
        failure: failed,
        latency: const Duration(milliseconds: 100),
        occurredAtUtc: occurred,
      );
      final cancelledEvent = VoiceTelemetryEvent.failed(
        request: request,
        requestedEngine: VoiceEngine.omniVoice,
        failure: cancelled,
        latency: const Duration(milliseconds: 100),
        occurredAtUtc: occurred,
      );

      for (final event in [succeededEvent, failedEvent, cancelledEvent]) {
        expect(event.capability, VoiceCapability.sessionVoiceMirror);
        expect(event.privacyScope, VoicePrivacyScope.participantTransient);
        expect(event.toMap()['capability'], 'sessionVoiceMirror');
        expect(event.toMap()['privacyScope'], 'participantTransient');
      }
    });

    test('native fallback requires and preserves its fallbackReason', () {
      final request = _request(mode: VoiceMode.practice);
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: true,
        cacheHit: false,
      );

      final event = VoiceTelemetryEvent.succeeded(
        request: request,
        result: result,
        fallbackReason: VoiceFailureCategory.authentication,
        latency: const Duration(milliseconds: 320),
        occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
      );

      expect(event.outcome, VoiceTelemetryOutcome.succeeded);
      expect(event.requestedEngine, VoiceEngine.omniVoice);
      expect(event.actualEngine, VoiceEngine.nativeTts);
      expect(event.usedFallback, isTrue);
      expect(event.fallbackReason, VoiceFailureCategory.authentication);
      expect(event.toMap()['fallbackReason'], 'authentication');
    });

    test('rejects usedFallback=true without a fallbackReason', () {
      final request = _request();
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: true,
        cacheHit: false,
      );

      expect(
        () => VoiceTelemetryEvent.succeeded(
          request: request,
          result: result,
          latency: const Duration(milliseconds: 10),
          occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
        ),
        throwsArgumentError,
      );
    });

    test('rejects usedFallback=false with a fallbackReason', () {
      final request = _request();
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );

      expect(
        () => VoiceTelemetryEvent.succeeded(
          request: request,
          result: result,
          fallbackReason: VoiceFailureCategory.authentication,
          latency: const Duration(milliseconds: 10),
          occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative latency', () {
      final request = _request();
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );

      expect(
        () => VoiceTelemetryEvent.succeeded(
          request: request,
          result: result,
          latency: const Duration(milliseconds: -1),
          occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
        ),
        throwsArgumentError,
      );
    });
  });

  group('VoiceTelemetryEvent.failed', () {
    test(
      'maps a non-cancelled failure to outcome failed with no actual engine, '
      'fallback, cache, or provenance',
      () {
        final request = _request(
          mode: VoiceMode.researchEvaluation,
          assignedEngine: VoiceEngine.omniVoice,
        );
        final failure = VoiceFailure(
          category: VoiceFailureCategory.network,
          message: 'Unable to reach the voice service.',
        );

        final event = VoiceTelemetryEvent.failed(
          request: request,
          requestedEngine: VoiceEngine.omniVoice,
          failure: failure,
          latency: const Duration(milliseconds: 500),
          occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
        );

        expect(event.schemaVersion, _schemaVersion);
        expect(event.outcome, VoiceTelemetryOutcome.failed);
        expect(event.requestedEngine, VoiceEngine.omniVoice);
        expect(event.actualEngine, isNull);
        expect(event.failureCategory, VoiceFailureCategory.network);
        expect(event.usedFallback, isFalse);
        expect(event.fallbackReason, isNull);
        expect(event.cacheHit, isFalse);
        expect(event.requestId, isNull);
        expect(event.modelVersion, isNull);

        final map = event.toMap();
        expect(map['outcome'], 'failed');
        expect(map['actualEngine'], isNull);
        expect(map['failureCategory'], 'network');
        expect(map['latencyMs'], 500);
      },
    );

    test('maps a cancelled failure to outcome cancelled', () {
      final request = _request();
      final failure = VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message: 'Playback was cancelled.',
      );

      final event = VoiceTelemetryEvent.failed(
        request: request,
        requestedEngine: VoiceEngine.omniVoice,
        failure: failure,
        latency: const Duration(milliseconds: 0),
        occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
      );

      expect(event.outcome, VoiceTelemetryOutcome.cancelled);
      expect(event.failureCategory, VoiceFailureCategory.cancelled);
      expect(event.toMap()['outcome'], 'cancelled');
    });

    test('rejects negative latency', () {
      final request = _request();
      final failure = VoiceFailure(
        category: VoiceFailureCategory.network,
        message: 'Unable to reach the voice service.',
      );

      expect(
        () => VoiceTelemetryEvent.failed(
          request: request,
          requestedEngine: VoiceEngine.omniVoice,
          failure: failure,
          latency: const Duration(milliseconds: -1),
          occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
        ),
        throwsArgumentError,
      );
    });
  });

  group('privacy allowlist', () {
    const spokenSentinel = 'spoken-secret-phrase-7c2a';
    const credentialSentinel = 'Bearer-credential-secret-7c2a';
    const emailSentinel = 'leak@example.test';
    const audioSentinel = 'audio-clip-bytes-7c2a';

    final deniedValues = <String>[
      spokenSentinel,
      credentialSentinel,
      emailSentinel,
      audioSentinel,
    ];

    test('serializes only allowlisted keys and redacts spoken, credential, '
        'email, and audio sentinels across succeeded, failed, and cancelled '
        'events', () {
      final request = _request(text: spokenSentinel);
      final succeeded = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );
      final leakingFailure = VoiceFailure(
        category: VoiceFailureCategory.network,
        message:
            'creds=$credentialSentinel mail=$emailSentinel '
            'clip=$audioSentinel',
      );
      final cancelledFailure = VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message:
            'creds=$credentialSentinel mail=$emailSentinel '
            'clip=$audioSentinel',
      );
      final occurred = DateTime.utc(2026, 7, 24, 10, 30);

      final events = <VoiceTelemetryEvent>[
        VoiceTelemetryEvent.succeeded(
          request: request,
          result: succeeded,
          latency: const Duration(milliseconds: 100),
          occurredAtUtc: occurred,
        ),
        VoiceTelemetryEvent.failed(
          request: request,
          requestedEngine: VoiceEngine.omniVoice,
          failure: leakingFailure,
          latency: const Duration(milliseconds: 100),
          occurredAtUtc: occurred,
        ),
        VoiceTelemetryEvent.failed(
          request: request,
          requestedEngine: VoiceEngine.omniVoice,
          failure: cancelledFailure,
          latency: const Duration(milliseconds: 100),
          occurredAtUtc: occurred,
        ),
      ];

      for (final event in events) {
        final map = event.toMap();

        expect(map.keys.toSet(), _allowedKeys);

        for (final key in map.keys) {
          final lowered = key.toLowerCase();
          for (final token in _bannedKeyTokens) {
            expect(
              lowered,
              isNot(contains(token)),
              reason: 'telemetry key "$key" leaks banned token "$token"',
            );
          }

          final value = map[key];
          final rendered = value == null ? '' : value.toString();
          for (final sentinel in deniedValues) {
            expect(
              key,
              isNot(contains(sentinel)),
              reason: 'telemetry key "$key" leaks sentinel "$sentinel"',
            );
            expect(
              rendered,
              isNot(contains(sentinel)),
              reason: 'telemetry value for "$key" leaks sentinel "$sentinel"',
            );
          }
        }
      }
    });

    test('serializes sessionVoiceMirror + participantTransient as enum names '
        'only, with no raw participant identity, voice clone id, or token', () {
      final request = _request(
        capability: VoiceCapability.sessionVoiceMirror,
        privacyScope: VoicePrivacyScope.participantTransient,
        // Private fields that must never surface in telemetry.
        text: 'mirror-secret-spoken-phrase-7c2a',
        voiceId: 'clone-id-secret-7c2a',
      );
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
        requestId: 'req-mirror',
        modelVersion: 'omnivoice-2026-07',
      );
      final occurred = DateTime.utc(2026, 7, 24, 10, 30);

      final event = VoiceTelemetryEvent.succeeded(
        request: request,
        result: result,
        latency: const Duration(milliseconds: 200),
        occurredAtUtc: occurred,
      );

      final map = event.toMap();

      // The mirror/transient pairing is reported only as enum names — never as
      // raw participant ids, voice clone ids, tokens, or audio.
      expect(map['capability'], 'sessionVoiceMirror');
      expect(map['privacyScope'], 'participantTransient');
      expect(map.containsKey('text'), isFalse);
      expect(map.containsKey('language'), isFalse);
      expect(map.containsKey('voiceId'), isFalse);
      expect(map.containsKey('speed'), isFalse);
      expect(map.containsKey('audio'), isFalse);
      expect(map.containsKey('participantId'), isFalse);
      expect(map.containsKey('voiceCloneId'), isFalse);
      expect(map.containsKey('token'), isFalse);

      // No mirror/transient value carries the private sentinels either.
      for (final sentinel in [
        'mirror-secret-spoken-phrase-7c2a',
        'clone-id-secret-7c2a',
      ]) {
        expect(
          map['capability'].toString(),
          isNot(contains(sentinel)),
          reason: 'capability leaks sentinel "$sentinel"',
        );
        expect(
          map['privacyScope'].toString(),
          isNot(contains(sentinel)),
          reason: 'privacyScope leaks sentinel "$sentinel"',
        );
      }
    });
  });

  test('toMap returns a fresh map on every call', () {
    final request = _request();
    final result = VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
      requestId: 'req-abc',
      modelVersion: 'omnivoice-2026-07',
    );
    final event = VoiceTelemetryEvent.succeeded(
      request: request,
      result: result,
      latency: const Duration(milliseconds: 250),
      occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
    );

    final first = event.toMap();
    final originalLatency = first['latencyMs'];
    final originalOutcome = first['outcome'];
    first['latencyMs'] = -999999;
    first['outcome'] = 'tampered';
    first['schemaVersion'] = 'tampered';

    final second = event.toMap();
    expect(identical(first, second), isFalse);
    expect(second['latencyMs'], originalLatency);
    expect(second['outcome'], originalOutcome);
    expect(second['schemaVersion'], _schemaVersion);
  });

  group('VoiceTelemetrySink', () {
    test('NoopVoiceTelemetrySink.record completes without throwing', () async {
      final request = _request();
      final result = VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
      );
      final event = VoiceTelemetryEvent.succeeded(
        request: request,
        result: result,
        latency: const Duration(milliseconds: 10),
        occurredAtUtc: DateTime.utc(2026, 7, 24, 10, 30),
      );

      final sink = NoopVoiceTelemetrySink();
      await expectLater(sink.record(event), completes);
    });
  });
}

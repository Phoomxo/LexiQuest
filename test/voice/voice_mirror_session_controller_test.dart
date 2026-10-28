import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_mirror_gateway.dart';
import 'package:vocab_learning_app/voice/voice_mirror_session_controller.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

const _sessionId = 'session-abc';
final _wavBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);

/// A controllable gateway fake that records every call and can inject failures.
final class _FakeGateway implements VoiceMirrorClient {
  _FakeGateway();

  VoiceMirrorLease? lease;
  VoiceAudio? audio;
  VoiceFailure? enrollFailure;
  VoiceFailure? heartbeatFailure;
  VoiceFailure? synthesizeFailure;
  VoiceFailure? deleteFailure;

  final enrollCalls = <Uint8List>[];
  final heartbeatCalls = <String>[];
  final synthesizeCalls = <_SynthesizeCall>[];
  final deleteCalls = <String>[];

  @override
  Future<VoiceMirrorLease> enroll({required Uint8List wavBytes}) async {
    enrollCalls.add(wavBytes);
    final error = enrollFailure;
    if (error != null) throw error;
    return lease ?? _defaultLease();
  }

  @override
  Future<VoiceMirrorLease> heartbeat({required String sessionId}) async {
    heartbeatCalls.add(sessionId);
    final error = heartbeatFailure;
    if (error != null) throw error;
    return lease ?? _defaultLease();
  }

  @override
  Future<VoiceAudio> synthesize({
    required String sessionId,
    required String contentId,
    required String text,
    required String language,
  }) async {
    synthesizeCalls.add(
      _SynthesizeCall(
        sessionId: sessionId,
        contentId: contentId,
        text: text,
        language: language,
      ),
    );
    final error = synthesizeFailure;
    if (error != null) throw error;
    return audio ?? _defaultAudio();
  }

  @override
  Future<void> delete({required String sessionId}) async {
    deleteCalls.add(sessionId);
    final error = deleteFailure;
    if (error != null) throw error;
  }
}

final class _SynthesizeCall {
  const _SynthesizeCall({
    required this.sessionId,
    required this.contentId,
    required this.text,
    required this.language,
  });

  final String sessionId;
  final String contentId;
  final String text;
  final String language;
}

VoiceMirrorLease _defaultLease() => const VoiceMirrorLease(
  sessionId: _sessionId,
  leaseExpiresAtEpochMs: 1000,
  absoluteExpiresAtEpochMs: 2000,
);

VoiceAudio _defaultAudio() => VoiceAudio(
  bytes: Uint8List.fromList([9, 9, 9]),
  requestId: 'req',
  engine: VoiceEngine.voxCpmMirror,
  modelVersion: '2.0.3',
  sampleRate: 48000,
);

void main() {
  group('consent', () {
    test('starting without consent throws consentMissing', () async {
      final controller = VoiceMirrorSessionController(
        gateway: _FakeGateway(),
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await expectLater(
        controller.start(enrollmentWav: _wavBytes),
        throwsA(_failure(VoiceFailureCategory.consentMissing)),
      );
    });

    test('granting consent allows a session to start', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);

      expect(controller.isActive, isTrue);
      expect(gateway.enrollCalls.single, _wavBytes);
    });

    test('withdrawing consent ends the active session', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.withdrawConsent();

      expect(controller.isActive, isFalse);
      expect(controller.hasConsent, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });

    test('synthesizing without consent throws consentMissing', () async {
      final controller = VoiceMirrorSessionController(
        gateway: _FakeGateway(),
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await expectLater(
        controller.synthesize(
          contentId: 'word-cat',
          text: 'Cat',
          language: 'en',
        ),
        throwsA(_failure(VoiceFailureCategory.consentMissing)),
      );
    });
  });

  group('lifecycle', () {
    test('start then end deletes the session once', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.end();

      expect(controller.isActive, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });

    test('end is idempotent', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.end();
      await controller.end();

      expect(gateway.deleteCalls, [_sessionId]);
    });

    test('account change ends the active session', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.onAccountChanged();

      expect(controller.isActive, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });

    test('activity leave ends the active session', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.onActivityLeave();

      expect(controller.isActive, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });

    test(
      'synthesize without an active session throws sessionExpired',
      () async {
        final controller = VoiceMirrorSessionController(
          gateway: _FakeGateway(),
          now: () => DateTime.fromMillisecondsSinceEpoch(0),
        );

        await controller.grantConsent();

        await expectLater(
          controller.synthesize(
            contentId: 'word-cat',
            text: 'Cat',
            language: 'en',
          ),
          throwsA(_failure(VoiceFailureCategory.sessionExpired)),
        );
      },
    );
  });

  group('expiry', () {
    test(
      'synthesizing after the absolute lifetime throws sessionExpired',
      () async {
        final gateway = _FakeGateway();
        var clock = DateTime.fromMillisecondsSinceEpoch(0);
        final controller = VoiceMirrorSessionController(
          gateway: gateway,
          now: () => clock,
        );

        await controller.grantConsent();
        await controller.start(enrollmentWav: _wavBytes);

        clock = DateTime.fromMillisecondsSinceEpoch(2001);

        await expectLater(
          controller.synthesize(
            contentId: 'word-cat',
            text: 'Cat',
            language: 'en',
          ),
          throwsA(_failure(VoiceFailureCategory.sessionExpired)),
        );
        expect(controller.isActive, isFalse);
      },
    );

    test('heartbeat renews the lease before it expires', () async {
      final gateway = _FakeGateway();
      var clock = DateTime.fromMillisecondsSinceEpoch(900);
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => clock,
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);

      await controller.renewLease();

      expect(gateway.heartbeatCalls, [_sessionId]);
    });
  });

  group('quota', () {
    test('blocks synthesis after the request quota is exhausted', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
        maxRequests: 1,
        maxCharacters: 1000,
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.synthesize(
        contentId: 'word-cat',
        text: 'Cat',
        language: 'en',
      );

      await expectLater(
        controller.synthesize(
          contentId: 'word-dog',
          text: 'Dog',
          language: 'en',
        ),
        throwsA(_failure(VoiceFailureCategory.rateLimited)),
      );
      expect(gateway.synthesizeCalls.length, 1);
    });

    test('blocks synthesis after the character quota is exhausted', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
        maxRequests: 100,
        maxCharacters: 3,
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.synthesize(
        contentId: 'word-cat',
        text: 'Cat',
        language: 'en',
      );

      await expectLater(
        controller.synthesize(
          contentId: 'word-dog',
          text: 'Dog',
          language: 'en',
        ),
        throwsA(_failure(VoiceFailureCategory.rateLimited)),
      );
      expect(gateway.synthesizeCalls.length, 1);
    });
  });

  group('background', () {
    test('five continuous paused minutes end the session', () async {
      final gateway = _FakeGateway();
      var clock = DateTime.fromMillisecondsSinceEpoch(0);
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => clock,
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);

      controller.onAppLifecycleStateChanged(AppLifecycleState.paused);
      // Advance just under five minutes: still active.
      clock = clock.add(const Duration(minutes: 4, seconds: 59));
      controller.onAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(controller.isActive, isTrue);

      // Cross the threshold: ends the session.
      clock = clock.add(const Duration(seconds: 2));
      controller.onAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(controller.isActive, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });

    test('resuming cancels the background countdown', () async {
      final gateway = _FakeGateway();
      var clock = DateTime.fromMillisecondsSinceEpoch(0);
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => clock,
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);

      controller.onAppLifecycleStateChanged(AppLifecycleState.paused);
      controller.onAppLifecycleStateChanged(AppLifecycleState.resumed);
      clock = clock.add(const Duration(minutes: 6));
      controller.onAppLifecycleStateChanged(AppLifecycleState.resumed);

      expect(controller.isActive, isTrue);
      expect(gateway.deleteCalls, isEmpty);
    });
  });

  group('cleanup', () {
    test(
      'a failed delete reports cleanupIncomplete and clears the session',
      () async {
        final gateway = _FakeGateway()
          ..deleteFailure = const VoiceFailure(
            category: VoiceFailureCategory.unknown,
            message: 'delete failed',
          );
        final controller = VoiceMirrorSessionController(
          gateway: gateway,
          now: () => DateTime.fromMillisecondsSinceEpoch(0),
        );

        await controller.grantConsent();
        await controller.start(enrollmentWav: _wavBytes);

        await expectLater(
          controller.end(),
          throwsA(_failure(VoiceFailureCategory.cleanupIncomplete)),
        );

        expect(controller.isActive, isFalse);
        // Retrying end after a cleanup failure is a no-op (session already gone).
        await controller.end();
        expect(gateway.deleteCalls.length, 1);
      },
    );

    test('dispose ends an active session', () async {
      final gateway = _FakeGateway();
      final controller = VoiceMirrorSessionController(
        gateway: gateway,
        now: () => DateTime.fromMillisecondsSinceEpoch(0),
      );

      await controller.grantConsent();
      await controller.start(enrollmentWav: _wavBytes);
      await controller.dispose();

      expect(controller.isActive, isFalse);
      expect(gateway.deleteCalls, [_sessionId]);
    });
  });
}

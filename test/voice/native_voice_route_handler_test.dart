// RED phase: defines the behavior contract for NativeVoiceRouteHandler before
// its implementation exists. This file is expected NOT to compile until the
// handler is added under lib/voice/.
//
// Scope: the descriptor the handler advertises, speak delegation to its
// VoiceProvider, stop delegation, and that cancellation is honoured before any
// provider call. No plugins or network are exercised; a deterministic fake
// VoiceProvider stands in for the real native TTS backend.
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/native_voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';

VoiceRequest _request({
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) {
  return VoiceRequest.create(
    text: 'Good morning.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1,
    contentId: 'phrase-001',
    contentType: 'phrase',
    mode: VoiceMode.practice,
    capability: capability,
    privacyScope: privacyScope,
  );
}

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

/// Minimal deterministic VoiceProvider: records speak/stop calls and optionally
/// fails speak.
class _RecordingVoiceProvider implements VoiceProvider {
  _RecordingVoiceProvider({this.speakFailure});

  final List<VoiceRequest> speakCalls = <VoiceRequest>[];
  int stopCount = 0;

  final VoiceFailure? speakFailure;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    speakCalls.add(request);
    final failure = speakFailure;
    if (failure != null) {
      throw failure;
    }
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

void main() {
  group('descriptor', () {
    test('advertises the native Tts engine with standard speech capabilities '
        'and no caching', () {
      final handler = NativeVoiceRouteHandler(_RecordingVoiceProvider());

      final descriptor = handler.descriptor;

      expect(descriptor.engine, VoiceEngine.nativeTts);
      expect(descriptor.supports(VoiceCapability.standardTargetSpeech), isTrue);
      expect(descriptor.supports(VoiceCapability.dynamicTargetSpeech), isTrue);
      expect(descriptor.privacyScope, VoicePrivacyScope.standardContent);
      expect(descriptor.allowsStandardCache, isFalse);
    });
  });

  group('speak delegation', () {
    test('forwards the request to the provider and reports a native, '
        'uncached result', () async {
      final provider = _RecordingVoiceProvider();
      final handler = NativeVoiceRouteHandler(provider);

      final result = await handler.speak(_request(), _NeverCancelledToken());

      expect(provider.speakCalls.single, isA<VoiceRequest>());
      expect(provider.stopCount, 0);

      expect(result.requestedEngine, VoiceEngine.nativeTts);
      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
    });

    test(
      'surfaces the provider failure category without swallowing it',
      () async {
        final provider = _RecordingVoiceProvider(
          speakFailure: const VoiceFailure(
            category: VoiceFailureCategory.synthesis,
            message: 'Native engine failed to synthesize.',
          ),
        );
        final handler = NativeVoiceRouteHandler(provider);

        await expectLater(
          handler.speak(_request(), _NeverCancelledToken()),
          throwsA(_failure(VoiceFailureCategory.synthesis)),
        );

        expect(provider.speakCalls.single, isA<VoiceRequest>());
      },
    );
  });

  group('stop delegation', () {
    test('forwards stop to the provider exactly once', () async {
      final provider = _RecordingVoiceProvider();
      final handler = NativeVoiceRouteHandler(provider);

      await handler.stop();

      expect(provider.stopCount, 1);
      expect(provider.speakCalls, isEmpty);
    });
  });

  group('cancellation', () {
    test('cancels before delegating to the provider', () async {
      final provider = _RecordingVoiceProvider();
      final handler = NativeVoiceRouteHandler(provider);

      await expectLater(
        handler.speak(_request(), _AlwaysCancelledToken()),
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );

      expect(provider.speakCalls, isEmpty);
      expect(provider.stopCount, 0);
    });
  });
}

/// A cancellation handle that never reports cancellation.
class _NeverCancelledToken implements VoiceCancellationToken {
  @override
  bool get isCancelled => false;

  @override
  void throwIfCancelled() {}
}

/// A cancellation handle that is always already cancelled, so speak must abort
/// before touching the provider.
class _AlwaysCancelledToken implements VoiceCancellationToken {
  @override
  bool get isCancelled => true;

  @override
  void throwIfCancelled() {
    throw const VoiceFailure(
      category: VoiceFailureCategory.cancelled,
      message: 'The native voice request was cancelled before playback.',
    );
  }
}

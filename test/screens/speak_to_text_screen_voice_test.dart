import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/speak_to_text_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;
  VoicePlaybackResult? resultToReturn;
  Object? errorToThrow;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    if (errorToThrow != null) {
      throw errorToThrow!;
    }
    return resultToReturn ??
        const VoicePlaybackResult(
          requestedEngine: VoiceEngine.omniVoice,
          actualEngine: VoiceEngine.omniVoice,
          usedFallback: false,
          cacheHit: false,
          requestId: 'test-req-123',
          modelVersion: '0.2.1',
        );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  testWidgets(
    'SpeakToTextScreen automatically speaks word on start using VoiceProvider',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: SpeakToTextScreen(
            correctWord: 'apple',
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      final req = fakeVoice.spokenRequests.first;
      expect(req.text, 'apple');
      expect(req.language, 'en');
      expect(req.mode, VoiceMode.practice);
      expect(req.contentId, 'apple');
      expect(req.contentType, 'vocabulary_word');
    },
  );

  testWidgets('Tapping audio button replays speech via VoiceProvider', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'banana',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 1);

    // Find and tap speaker / audio replay button
    final speakerFinder = find.byIcon(Icons.volume_up);
    expect(speakerFinder, findsOneWidget);

    await tester.tap(speakerFinder);
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 2);
    expect(fakeVoice.spokenRequests[1].text, 'banana');
  });

  testWidgets('Disposing SpeakToTextScreen calls stop on VoiceProvider', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Replace widget to trigger dispose
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(fakeVoice.stopCalls, greaterThanOrEqualTo(1));
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _LifecycleSpeechGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: SpeakToTextScreen(
          correctWord: 'cat',
          voice: VoiceUseCases(FakeVoiceProvider()),
          speechPractice: SpeechPracticeUseCases(gateway),
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();

    expect(gateway.cancelCalls, 1);
  });
}

final class _LifecycleSpeechGateway implements SpeechRecognitionGateway {
  int cancelCalls = 0;

  @override
  bool get isListening => false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {}

  @override
  Future<void> stop() async {}
}

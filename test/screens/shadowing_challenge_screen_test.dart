import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('uses real transcript provenance and never fabricates pitch', (
    tester,
  ) async {
    final voice = _FakeVoice();
    final speech = SpeechPracticeUseCases(_FakeSpeechGateway());
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Practice makes perfect',
          voice: VoiceUseCases(voice),
          speechPractice: speech,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('shadowing-play-reference')));
    await tester.pumpAndSettle();
    expect(voice.requests.single.text, 'Practice makes perfect');

    await tester.tap(find.byKey(const ValueKey('shadowing-listen-button')));
    await tester.pumpAndSettle();

    expect(
      find.text('ข้อความที่ได้ยิน: Practice makes perfect'),
      findsOneWidget,
    );
    expect(find.textContaining('ความเหมือนของข้อความ: 100%'), findsOneWidget);
    expect(
      find.textContaining('ไม่ได้ส่งข้อมูล pitch หรือ phoneme'),
      findsOneWidget,
    );
    expect(find.textContaining('Pitch Contour'), findsNothing);
  });

  testWidgets('cancels microphone when app leaves foreground', (tester) async {
    final gateway = _FakeSpeechGateway();
    final speech = SpeechPracticeUseCases(gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: ShadowingChallengeScreen(
          referenceSentence: 'Keep going',
          voice: VoiceUseCases(_FakeVoice()),
          speechPractice: speech,
        ),
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(gateway.cancelCalls, 1);
  });
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  int cancelCalls = 0;
  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    isListening = false;
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
  }) async {
    isListening = true;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'Practice makes perfect',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'device-stt',
        locale: locale,
      ),
    );
    isListening = false;
  }

  @override
  Future<void> stop() async {
    isListening = false;
  }
}

final class _FakeVoice implements VoiceProvider {
  final List<VoiceRequest> requests = [];

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

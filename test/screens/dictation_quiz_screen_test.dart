import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

void main() {
  testWidgets(
    'DictationQuizScreen automatically plays word at 1.0x speed on start',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(
            targetWord: 'elephant',
            voice: VoiceUseCases(fakeVoice),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fakeVoice.spokenRequests.length, 1);
      final req = fakeVoice.spokenRequests.first;
      expect(req.text, 'elephant');
      expect(req.speed, 1.0);
    },
  );

  testWidgets('Tapping Slow-Mo button triggers 0.75x speed request', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(
          targetWord: 'elephant',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slowMoFinder = find.byIcon(Icons.slow_motion_video);
    expect(slowMoFinder, findsOneWidget);

    await tester.tap(slowMoFinder);
    await tester.pumpAndSettle();

    expect(fakeVoice.spokenRequests.length, 2);
    expect(fakeVoice.spokenRequests[1].speed, 0.75);
  });

  testWidgets('Typing correct word displays success feedback', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(
          targetWord: 'elephant',
          voice: VoiceUseCases(fakeVoice),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inputFinder = find.byType(TextField);
    await tester.enterText(inputFinder, 'elephant');
    await tester.tap(find.text('ตรวจคำตอบ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ถูกต้อง!'), findsOneWidget);
  });
}

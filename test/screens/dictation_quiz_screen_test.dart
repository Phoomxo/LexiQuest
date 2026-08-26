import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/dictation_quiz_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class FakeVoiceProvider implements VoiceProvider {
  final List<VoiceRequest> spokenRequests = [];
  final Completer<void> stopEntered = Completer<void>();
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
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

void main() {
  test('f13 dictation delegates correctness to its typed native adapter', () {
    final source = File(
      'lib/screens/dictation_quiz_screen.dart',
    ).readAsStringSync();
    expect(source, contains('DictationModeAdapter'));
    expect(source, contains('.evaluate('));
    expect(source, contains('_lifecycle!.complete('));
    expect(source, isNot(contains('userInput == expected')));
  });

  testWidgets(
    'DictationQuizScreen automatically plays word at 1.0x speed on start',
    (WidgetTester tester) async {
      final fakeVoice = FakeVoiceProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(
            targetWord: 'elephant',
            voice: VoiceUseCases(
              provider: fakeVoice,
              disposeProvider: () async {},
            ),
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

  testWidgets('background stops the automatic dictation playback', (
    tester,
  ) async {
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(targetWord: 'elephant', voice: voice),
        ),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.runAsync(
        () => provider.stopEntered.future.timeout(
          const Duration(milliseconds: 250),
        ),
      );

      expect(provider.stopCalls, 1);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('post-frame autoplay cannot begin while app is inactive', (
    tester,
  ) async {
    final provider = FakeVoiceProvider();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(targetWord: 'late', voice: voice),
        ),
      );
      await tester.pump();

      expect(provider.spokenRequests, isEmpty);
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(
        () => voice.dispose().timeout(const Duration(seconds: 1)),
      );
    }
  });

  testWidgets('Tapping Slow-Mo button triggers 0.75x speed request', (
    WidgetTester tester,
  ) async {
    final fakeVoice = FakeVoiceProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(
          targetWord: 'elephant',
          voice: VoiceUseCases(
            provider: fakeVoice,
            disposeProvider: () async {},
          ),
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
          voice: VoiceUseCases(
            provider: fakeVoice,
            disposeProvider: () async {},
          ),
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

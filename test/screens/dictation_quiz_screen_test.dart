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
  Object? playbackError;
  Completer<void>? allowPlayback;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    spokenRequests.add(request);
    await allowPlayback?.future;
    if (playbackError != null) throw playbackError!;
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
  testWidgets('blank dictation cannot submit by button or keyboard', (
    tester,
  ) async {
    final voice = VoiceUseCases(
      provider: FakeVoiceProvider(),
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(targetWord: 'bag', voice: voice),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(ElevatedButton, 'ตรวจคำตอบ');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('ลองใหม่อีกครั้ง!'), findsNothing);
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'bag');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
  });
  testWidgets(
    'replaying during pending audio ignores superseded cancellation',
    (tester) async {
      final provider = FakeVoiceProvider()..allowPlayback = Completer<void>();
      final voice = VoiceUseCases(
        provider: provider,
        disposeProvider: () async {},
      );
      addTearDown(voice.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DictationQuizScreen(targetWord: 'station', voice: voice),
        ),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.volume_up));
      await tester.pump();
      provider.allowPlayback!.complete();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'station');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('media-dependency-unavailable')),
        findsNothing,
      );
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'ตรวจคำตอบ'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets('pending initial audio cannot submit before failed start', (
    tester,
  ) async {
    final provider = FakeVoiceProvider()
      ..allowPlayback = Completer<void>()
      ..playbackError = StateError('delayed audio failure');
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(targetWord: 'station', voice: voice),
      ),
    );
    await tester.pump();
    final check = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'ตรวจคำตอบ'),
    );
    final locked = check.onPressed == null;
    provider.allowPlayback!.complete();
    await tester.pumpAndSettle();
    expect(locked, isTrue);
    expect(
      find.byKey(const ValueKey('media-dependency-unavailable')),
      findsOneWidget,
    );
  });
  testWidgets('failed dictation audio offers a text activity without scoring', (
    tester,
  ) async {
    final provider = FakeVoiceProvider()
      ..playbackError = StateError('device unavailable');
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    addTearDown(voice.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: DictationQuizScreen(targetWord: 'station', voice: voice),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('media-dependency-unavailable')),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('ตรวจคำตอบ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
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

  testWidgets(
    'f38 final review: voice-present dictation remains operable at 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final voice = VoiceUseCases(
        provider: FakeVoiceProvider(),
        disposeProvider: () async {},
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: DictationQuizScreen(targetWord: 'station', voice: voice),
        ),
      );
      await tester.pumpAndSettle();

      final layoutExceptions = <Object>[];
      while (true) {
        final exception = tester.takeException();
        if (exception == null) break;
        layoutExceptions.add(exception);
      }
      expect(
        layoutExceptions,
        isEmpty,
        reason: 'the real voice-present surface must not overflow at 200%',
      );

      final normalAudio = find.widgetWithText(
        ElevatedButton,
        'ความเร็วปกติ (1.0x)',
      );
      final slowAudio = find.widgetWithText(
        OutlinedButton,
        'ฟังแบบช้า (0.75x)',
      );
      final input = find.byType(TextField);
      final checkAnswer = find.widgetWithText(ElevatedButton, 'ตรวจคำตอบ');
      expect(
        find.ancestor(of: checkAnswer, matching: find.byType(Scrollable)),
        findsOneWidget,
        reason: 'narrow 200% content needs a real responsive scroll surface',
      );
      for (final control in <Finder>[
        normalAudio,
        slowAudio,
        input,
        checkAnswer,
      ]) {
        expect(control, findsOneWidget);
        await tester.ensureVisible(control);
        await tester.pump();
        expect(
          control.hitTestable(),
          findsOneWidget,
          reason: 'every audio, input, and check action must remain reachable',
        );
      }
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
    await tester.pump();
    await tester.tap(find.text('ตรวจคำตอบ'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ถูกต้อง!'), findsOneWidget);
  });
}

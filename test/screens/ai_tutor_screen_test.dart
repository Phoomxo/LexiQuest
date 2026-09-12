import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets('R15 visual Thai reply and offline large=$large', (
      tester,
    ) async {
      await (FontLoader(
            M3Theme.thaiFontFamily,
          )..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
          .load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.physicalSize = Size(large ? 320 : 390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundary = GlobalKey();
      final tutor = _FakeAiTutor()
        ..replyText =
            'ลองพูดว่า **I would like a coffee.**\n'
            '- would like ใช้สั่งอย่างสุภาพ\n'
            'ลองแต่งประโยคของคุณเอง 😀';
      await tester.pumpWidget(
        MaterialApp(
          theme: large ? M3Theme.darkTheme : M3Theme.lightTheme,
          home: RepaintBoundary(
            key: boundary,
            child: MediaQuery(
              data: MediaQueryData(
                disableAnimations: true,
                textScaler: TextScaler.linear(large ? 2 : 1),
              ),
              child: AiTutorScreen(aiTutor: tutor),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String state) async {
        if (Platform.environment['LEXIQUEST_R15_VISUAL_QA'] != '1') return;
        await tester.runAsync(() async {
          final rendered =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await rendered.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final variant =
              Platform.environment['LEXIQUEST_R15_VISUAL_VARIANT'] ?? 'after';
          final file = File(
            'build/verification/r15-ai-visual/$variant-$large-$state.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          rendered.dispose();
        });
      }

      await capture('empty');
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'ช่วยอธิบายการสั่งกาแฟ',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      await capture('reply');
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await capture('reply-end');
      expect(find.text(tutor.replyText), findsOneWidget);
      expect(tester.takeException(), isNull);
      tutor.replyFailure = const AiTutorException(AiFailureCode.offline);
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'คำถามต่อไป',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ai-tutor-error')),
        160,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await capture('offline');
      expect(find.byKey(const ValueKey('ai-tutor-error')), findsOneWidget);
      expect(
        tester.getSize(find.byType(ListView)).height,
        greaterThan(300),
        reason:
            'Large text and offline status must leave a usable scrolling reading area.',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'R15 completed pairs survive busy and new chat fences late replies',
    (tester) async {
      final tutor = _FakeAiTutor()..replyText = 'ไทย **ครบ**\n- คำตอบ 😀';
      await tester.pumpWidget(MaterialApp(home: AiTutorScreen(aiTutor: tutor)));
      await tester.pumpAndSettle();
      Future<void> send(String text) async {
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          text,
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pump();
      }

      await send('คำถามหนึ่ง');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'ไทย **ครบ**\n- คำตอบ 😀',
        ),
        findsOneWidget,
      );
      tutor.replyGate = Completer<void>();
      tutor.ignoreCancellation = true;
      await send('คำถามสอง');
      expect(tutor.contexts.last?.priorTurns.map((t) => t.text), [
        'คำถามหนึ่ง',
        'ไทย **ครบ**\n- คำตอบ 😀',
      ]);
      expect(find.text('คำถามสอง'), findsOneWidget);
      await tester.tap(find.byTooltip('เริ่มบทสนทนาใหม่'));
      await tester.pump();
      expect(tutor.lastCancellation?.isCancelled, isTrue);
      tutor.replyGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('คำถามสอง'), findsNothing);
      expect(find.text('ไทย **ครบ**\n- คำตอบ 😀'), findsNothing);
      tutor.replyGate = null;
      await send('ใหม่');
      await tester.pumpAndSettle();
      expect(tutor.contexts.last?.priorTurns, isEmpty);
      expect(
        tutor.contexts.last?.sessionId,
        isNot(tutor.contexts.first?.sessionId),
      );
    },
  );

  testWidgets('R15 scenario and level intent changes start empty context', (
    tester,
  ) async {
    final tutor = _FakeAiTutor();
    await tester.pumpWidget(MaterialApp(home: AiTutorScreen(aiTutor: tutor)));
    await tester.pumpAndSettle();
    Future<void> send() async {
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'Hello',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
    }

    await send();
    final firstSession = tutor.contexts.last!.sessionId;
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สั่งอาหารในคาเฟ่').last);
    await tester.pumpAndSettle();
    await send();
    expect(tutor.contexts.last!.priorTurns, isEmpty);
    expect(tutor.contexts.last!.sessionId, isNot(firstSession));
    await tester.tap(find.byKey(const ValueKey('ai-tutor-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B2').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-intent')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('อธิบาย').last);
    await tester.pumpAndSettle();
    await send();
    expect(tutor.contexts.last!.cefrLevel, 'B2');
    expect(tutor.contexts.last!.intent, TutorIntent.explanation);
    expect(tutor.contexts.last!.priorTurns, isEmpty);
  });

  testWidgets('R15 failed and cancelled questions never become context pairs', (
    tester,
  ) async {
    final tutor = _FakeAiTutor()
      ..replyFailure = const AiTutorException(AiFailureCode.offline);
    await tester.pumpWidget(MaterialApp(home: AiTutorScreen(aiTutor: tutor)));
    await tester.pumpAndSettle();
    for (final question in ['failed question', 'successful question']) {
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        question,
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      if (question == 'failed question') {
        expect(find.text('Live Gemini reply'), findsNothing);
        expect(find.text(question), findsOneWidget);
      }
      tutor.replyFailure = null;
    }
    expect(tutor.contexts.last!.priorTurns, isEmpty);
    tutor.replyGate = Completer<void>();
    tutor.ignoreCancellation = true;
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'cancelled question',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pump();
    tutor.replyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Live Gemini reply'), findsOneWidget);
  });

  testWidgets('R15 owner changes during reply discard old result and draft', (
    tester,
  ) async {
    final tutor = _FakeAiTutor()..replyGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: AiTutorScreen(aiTutor: tutor)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'private A',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();
    tutor.scopeId = 'scope-b';
    tutor.replyGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('private A'), findsNothing);
    expect(find.text('Live Gemini reply'), findsNothing);
  });

  testWidgets(
    'R15 owner scope change clears previous chat before next request',
    (tester) async {
      final tutor = _FakeAiTutor();
      await tester.pumpWidget(MaterialApp(home: AiTutorScreen(aiTutor: tutor)));
      await tester.pumpAndSettle();
      for (final text in ['owner A private', 'owner B question']) {
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          text,
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pumpAndSettle();
        tutor.scopeId = 'scope-b';
      }
      expect(tutor.messages, ['owner A private']);
      expect(find.text('owner A private'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'owner B confirmed',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      expect(tutor.contexts.last?.priorTurns, isEmpty);
      expect(tutor.contexts.last?.scopeId, 'scope-b');
      expect(find.text('owner A private'), findsNothing);
    },
  );

  for (final restart in [false, true]) {
    testWidgets(
      'intentional pending voice cancellation is silent restart=$restart',
      (tester) async {
        final gate = Completer<void>();
        final provider = _FakeVoice()
          ..firstSpeakGate = gate
          ..firstSpeakFailure = StateError('synthetic stale failure');
        final voice = VoiceUseCases(
          provider: provider,
          disposeProvider: () async {},
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: AiTutorScreen(aiTutor: _FakeAiTutor(), voice: voice),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('ai-tutor-input')),
            'Hello',
          );
          await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('ฟังคำตอบ'));
          await tester.pump();
          expect(provider.requests, hasLength(1));
          await tester.tap(find.byTooltip(restart ? 'ฟังคำตอบ' : 'หยุดอ่าน'));
          await tester.pumpAndSettle();
          expect(provider.stopCalls, greaterThanOrEqualTo(1));
          expect(provider.requests, hasLength(restart ? 2 : 1));
          expect(find.byKey(const ValueKey('ai-tutor-error')), findsNothing);
          gate.complete();
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('ai-tutor-error')), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.runAsync(() => voice.dispose());
        }
      },
    );
  }
  testWidgets(
    'BYOK disclosure states bounded Gemini retry and no provider fallback',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: AiTutorSettingsScreen(aiTutor: _FakeAiTutor())),
      );
      await tester.pumpAndSettle();

      final details = find.text('รายละเอียดการเชื่อมต่อและการเก็บรหัส');
      await tester.scrollUntilVisible(
        details,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.textContaining('รวมไม่เกิน 3 ครั้ง'), findsOneWidget);
      expect(
        find.textContaining('จะไม่เปลี่ยนไปใช้ผู้ให้บริการอื่น'),
        findsOneWidget,
      );
      expect(
        find.textContaining('no automatic fallback or retry'),
        findsNothing,
      );
    },
  );

  testWidgets('shows only live provider reply and model provenance', (
    tester,
  ) async {
    final tutor = _FakeAiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Welcome to the interview'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'My name is Phet and I am a developer',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();

    expect(tutor.messages, ['My name is Phet and I am a developer']);
    expect(find.text('Live Gemini reply'), findsOneWidget);
    expect(find.text('รุ่น AI: gemini-test'), findsOneWidget);
    expect(find.textContaining('Grammar:'), findsNothing);
  });

  testWidgets('provider failure is explicit and never becomes canned success', (
    tester,
  ) async {
    final tutor = _FakeAiTutor()
      ..replyFailure = const AiTutorException(
        AiFailureCode.providerUnavailable,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Hello',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ai-tutor-error')), findsOneWidget);
    expect(
      find.textContaining('greatest strength in team collaboration'),
      findsNothing,
    );
    expect(find.text('Live Gemini reply'), findsNothing);
  });

  testWidgets('microphone transcript is editable and waits for explicit send', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway();
    final tutor = _FakeAiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: tutor,
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pumpAndSettle();

    expect(tutor.messages, isEmpty);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('ai-tutor-input')))
          .controller!
          .text,
      'I have real project experience',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Reviewed transcript',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(tutor.messages, ['Reviewed transcript']);
    expect(find.text('Live Gemini reply'), findsOneWidget);
  });

  testWidgets('reply playback waits for play and offers stop', (tester) async {
    final provider = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          aiTutor: _FakeAiTutor(),
          voice: VoiceUseCases(
            provider: provider,
            disposeProvider: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Hello',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(provider.requests, isEmpty);
    await tester.tap(find.byTooltip('ฟังคำตอบ'));
    await tester.pumpAndSettle();
    expect(provider.requests.single.text, 'Live Gemini reply');
    await tester.tap(find.byTooltip('หยุดอ่าน'));
    await tester.pumpAndSettle();
    expect(provider.stopCalls, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('backgrounding cancels microphone', (tester) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    final speech = SpeechPracticeUseCases(speechGateway);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: voice,
            aiTutor: _FakeAiTutor(),
            speechPractice: speech,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(speechGateway.cancelCalls, 1);
      await tester.runAsync(() async {
        await speechGateway.cancelCompleted.future.timeout(
          const Duration(milliseconds: 250),
        );
        await Future<void>.delayed(Duration.zero);
      });
    } finally {
      if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await Future.wait<void>([
          voice.dispose(),
          speech.dispose(),
        ]).timeout(const Duration(seconds: 2));
      });
    }
  });

  testWidgets(
    'lifecycle cleanup attempts voice stop after speech cancel failure',
    (tester) async {
      final speechGateway = _FakeSpeechGateway(
        emitResult: false,
        cancelError: StateError('recognizer cancel failed'),
      );
      final voiceProvider = _FakeVoice();
      final voice = VoiceUseCases(
        provider: voiceProvider,
        disposeProvider: () async {},
      );
      final speech = SpeechPracticeUseCases(speechGateway);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AiTutorScreen(
              voice: voice,
              aiTutor: _FakeAiTutor(),
              speechPractice: speech,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          'Please reply',
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byTooltip('ฟังคำตอบ'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
        await tester.pump();

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        await tester.runAsync(
          () => voiceProvider.stopEntered.future.timeout(
            const Duration(milliseconds: 250),
          ),
        );

        expect(speechGateway.cancelCalls, 1);
        expect(voiceProvider.stopCalls, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await voice.dispose().timeout(const Duration(seconds: 1));
          try {
            await speech.dispose().timeout(const Duration(seconds: 1));
          } on Object {
            // The recognizer cleanup failure is deliberately injected.
          }
        });
      }
    },
  );

  testWidgets('background cancels and fences an in-flight AI generation', (
    tester,
  ) async {
    final replyGate = Completer<void>();
    final tutor = _FakeAiTutor()
      ..replyGate = replyGate
      ..ignoreCancellation = true;
    final provider = _FakeVoice();
    final voice = VoiceUseCases(
      provider: provider,
      disposeProvider: () async {},
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(voice: voice, aiTutor: tutor),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'late request',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pump();
      expect(tutor.lastCancellation, isNotNull);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      expect(tutor.lastCancellation!.isCancelled, isTrue);
      replyGate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Live Gemini reply'), findsNothing);
      expect(provider.requests, isEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (!replyGate.isCompleted) replyGate.complete();
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

  testWidgets('unmount consumes a speech-session release failure', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway(
      emitResult: false,
      cancelError: StateError('recognizer release failed'),
    );
    final voice = VoiceUseCases(
      provider: _FakeVoice(),
      disposeProvider: () async {},
    );
    final speech = SpeechPracticeUseCases(speechGateway);
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: voice,
          aiTutor: _FakeAiTutor(),
          speechPractice: speech,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(
      () => speechGateway.cancelEntered.future.timeout(
        const Duration(milliseconds: 250),
      ),
    );

    expect(speechGateway.cancelCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      await voice.dispose().timeout(const Duration(seconds: 1));
      try {
        await speech.dispose().timeout(const Duration(seconds: 1));
      } on Object {
        // The recognizer cleanup failure is deliberately injected.
      }
    });
  });

  testWidgets(
    'speech facade rebind releases old session and uses replacement',
    (tester) async {
      final oldGateway = _FakeSpeechGateway()..emitResult = false;
      final newGateway = _FakeSpeechGateway()..emitResult = false;
      final voice = VoiceUseCases(
        provider: _FakeVoice(),
        disposeProvider: () async {},
      );
      Future<void> pump(SpeechPracticeUseCases speech) => tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: voice,
            aiTutor: _FakeAiTutor(),
            speechPractice: speech,
          ),
        ),
      );

      await pump(SpeechPracticeUseCases(oldGateway));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();
      expect(oldGateway.startCalls, 1);

      await pump(SpeechPracticeUseCases(newGateway));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
      await tester.pump();

      expect(oldGateway.cancelCalls, 1);
      expect(newGateway.startCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opening AI provider settings cancels active microphone', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(
            provider: _FakeVoice(),
            disposeProvider: () async {},
          ),
          aiTutor: _FakeAiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่าผู้ให้บริการ AI'));
    await tester.pumpAndSettle();

    expect(speechGateway.cancelCalls, 1);
    final unavailableFinder = find.byType(ProductionFeatureUnavailable);
    expect(unavailableFinder, findsOneWidget);
    expect(
      tester.widget<ProductionFeatureUnavailable>(unavailableFinder).reason,
      ProductionFeatureUnavailableReason.missingRegistry,
    );
    expect(
      ModalRoute.of(tester.element(unavailableFinder))?.settings.name,
      'ai-tutor/settings',
    );
  });

  testWidgets('opening settings invalidates delayed reply and prevents TTS', (
    tester,
  ) async {
    final gate = Completer<void>();
    final tutor = _FakeAiTutor()..replyGate = gate;
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(provider: voice, disposeProvider: () async {}),
          aiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'A delayed message',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่าผู้ให้บริการ AI'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(voice.requests, isEmpty);
    expect(find.text('Live Gemini reply'), findsNothing);
  });
}

final class _FakeAiTutor implements AiTutorController {
  final List<String> messages = [];
  final List<TutorRequestContext?> contexts = [];
  String scopeId = 'scope-a';
  String replyText = 'Live Gemini reply';
  AiTutorException? replyFailure;
  Completer<void>? replyGate;
  AiCancellation? lastCancellation;
  bool ignoreCancellation = false;
  bool hasKey = true;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {}

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<AiTutorSettingsStatus> loadSettings() async => AiTutorSettingsStatus(
    hasKey: hasKey,
    contextScopeId: scopeId,
    providerConsent: true,
    shareLearningSummary: false,
    providerId: AiProviderId.gemini,
    model: 'gemini-test',
  );

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async => const [AiModel(id: 'gemini-test')];

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) async => const [AiModel(id: 'gemini-test')];

  @override
  Future<void> removeKey() async {}

  @override
  Future<List<AiUsageSummary>> loadUsage() async => const [];

  @override
  Future<void> clearUsage() async {}

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    TutorRequestContext? context,
    AiCancellation? cancellation,
  }) async {
    messages.add(learnerMessage);
    contexts.add(context);
    lastCancellation = cancellation;
    await replyGate?.future;
    if (!ignoreCancellation && cancellation?.isCancelled == true) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    final failure = replyFailure;
    if (failure != null) throw failure;
    return AiTutorReply(
      text: replyText,
      providerId: AiProviderId.gemini,
      model: 'gemini-test',
      generatedAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {}
}

final class _FakeSpeechGateway implements SpeechRecognitionGateway {
  _FakeSpeechGateway({this.emitResult = true, this.cancelError});

  bool emitResult;
  final Object? cancelError;
  final Completer<void> cancelEntered = Completer<void>();
  final Completer<void> cancelCompleted = Completer<void>();
  int cancelCalls = 0;
  int startCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    if (!cancelEntered.isCompleted) cancelEntered.complete();
    isListening = false;
    final error = cancelError;
    if (!cancelCompleted.isCompleted) cancelCompleted.complete();
    if (error != null) throw error;
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
    startCalls += 1;
    isListening = true;
    if (!emitResult) return;
    onEvent(
      SpeechRecognitionEvent(
        transcript: 'I have real project experience',
        isFinal: true,
        recognizedAtUtc: DateTime.utc(2026, 7, 30),
        engine: 'platform-speech-recognizer',
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
  Completer<void>? firstSpeakGate;
  Object? firstSpeakFailure;
  final List<VoiceRequest> requests = [];
  final Completer<void> stopEntered = Completer<void>();
  int stopCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      await firstSpeakGate?.future;
      final failure = firstSpeakFailure;
      if (failure != null) throw failure;
    }
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    if (!stopEntered.isCompleted) stopEntered.complete();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/device_permission_center_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  testWidgets('permanent microphone denial is announced and opens recovery', (
    tester,
  ) async {
    final permission = Completer<MediaPermissionState>()
      ..complete(MediaPermissionState.permanentlyDenied);
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
          speechPractice: SpeechPracticeUseCases(
            _FakeSpeechGateway()..permissionGate = permission,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pumpAndSettle();

    final error = find.byKey(const ValueKey('ai-tutor-error'));
    expect(
      find.ancestor(
        of: error,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsAtLeastNWidgets(1),
    );
    await tester.tap(find.text('เปิดศูนย์สิทธิ์อุปกรณ์'));
    await tester.pumpAndSettle();
    expect(find.byType(DevicePermissionCenterScreen), findsOneWidget);
  });

  testWidgets('main-menu tutor has no source target action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('ai-tutor-practice-target')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('ai-tutor-word-target')), findsNothing);
  });

  testWidgets(
    'word seed is cleared immediately when matching-owner controller is replaced',
    (tester) async {
      final original = _FakeGeminiTutor();
      final replacement = _FakeGeminiTutor();
      final seed = TutorWordDraft(
        controller: original,
        ownerScope: original.scope!,
        ownerEpoch: original.epoch,
        text: 'Old controller private draft',
      );
      Widget screen(GeminiTutorController? controller) => MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: controller,
          wordDraft: seed,
        ),
      );
      await tester.pumpWidget(screen(original));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      expect(tester.widget<TextField>(input).controller!.text, seed.text);
      await tester.pumpWidget(screen(replacement));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.pumpWidget(screen(original));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(original.messages, isEmpty);
    },
  );

  testWidgets(
    'missing initial controller consumes seed and cannot seed on later availability',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      final seed = TutorWordDraft(
        controller: tutor,
        ownerScope: tutor.scope!,
        ownerEpoch: tutor.epoch,
        text: 'Initially unavailable private draft',
      );
      Widget screen(GeminiTutorController? controller) => MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: controller,
          wordDraft: seed,
        ),
      );
      await tester.pumpWidget(screen(null));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.textContaining('เตรียมคำถามไม่ได้'), findsOneWidget);
      await tester.pumpWidget(screen(tutor));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tutor.messages, isEmpty);
    },
  );

  for (final invalid in ['owner', 'absent', 'epoch', 'controller', 'length']) {
    testWidgets('word draft rejects $invalid mismatch without exposing text', (
      tester,
    ) async {
      final tutor = _FakeGeminiTutor();
      final seed = TutorWordDraft(
        controller: tutor,
        ownerScope: tutor.scope!,
        ownerEpoch: tutor.epoch,
        text: invalid == 'length' ? 'x' * 501 : 'Private owner A question',
      );
      if (invalid == 'owner') tutor.changeScope();
      if (invalid == 'absent') tutor.scope = null;
      if (invalid == 'epoch') tutor.epoch += 1;
      final shownTutor = invalid == 'controller' ? _FakeGeminiTutor() : tutor;
      final voice = _FakeVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: VoiceUseCases(voice),
            geminiTutor: shownTutor,
            wordDraft: seed,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('ai-tutor-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(find.textContaining('เตรียมคำถามไม่ได้'), findsOneWidget);
      expect(find.text('กลับไปฝึกคำศัพท์'), findsOneWidget);
      expect(shownTutor.messages, isEmpty);
      expect(voice.requests, isEmpty);
    });
  }

  testWidgets('pending seed cannot overwrite editing followed by clearing', (
    tester,
  ) async {
    final settings = Completer<void>();
    final tutor = _FakeGeminiTutor()..settingsGate = settings;
    final seed = TutorWordDraft(
      controller: tutor,
      ownerScope: tutor.scope!,
      ownerEpoch: tutor.epoch,
      text: 'Deferred private word question',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
          wordDraft: seed,
        ),
      ),
    );
    await tester.pump();
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    await tester.enterText(input, 'Learner intention');
    await tester.enterText(input, '');
    settings.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(tutor.messages, isEmpty);
  });

  testWidgets('word seed does not return on rebuild settings or new round', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor();
    final seed = TutorWordDraft(
      controller: tutor,
      ownerScope: tutor.scope!,
      ownerEpoch: tutor.epoch,
      text: 'Word question once only',
      wordId: 'word-station',
      spelling: 'station',
    );
    final voice = VoiceUseCases(_FakeVoice());
    Widget screen(Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: AiTutorScreen(voice: voice, geminiTutor: tutor, wordDraft: seed),
    );
    await tester.pumpWidget(screen(Brightness.light));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-tutor-word-target')), findsOneWidget);
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    await tester.enterText(input, 'Edited private draft');
    await tester.pumpWidget(screen(Brightness.dark));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Edited private draft',
    );
    await tester.tap(find.byTooltip('ตั้งค่าผู้ช่วย AI'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Edited private draft',
    );
    await tester.tap(find.text('เริ่มรอบใหม่'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(screen(Brightness.light));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    expect(find.byKey(const ValueKey('ai-tutor-word-target')), findsNothing);
    expect(tutor.messages, isEmpty);
  });

  testWidgets(
    'owner ABA and controller replacement cannot resurrect a word seed',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      final ownerA = tutor.scope;
      final seed = TutorWordDraft(
        controller: tutor,
        ownerScope: ownerA!,
        ownerEpoch: tutor.epoch,
        text: 'Private A word draft',
        wordId: 'word-station',
        spelling: 'station',
      );
      Widget screen(_FakeGeminiTutor selected) => MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: selected,
          wordDraft: seed,
        ),
      );
      await tester.pumpWidget(screen(tutor));
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      expect(tester.widget<TextField>(input).controller!.text, seed.text);
      expect(
        find.byKey(const ValueKey('ai-tutor-word-target')),
        findsOneWidget,
      );
      tutor.changeScope();
      await tester.pumpAndSettle();
      tutor.scope = ownerA;
      tutor.changes.add(++tutor.epoch);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('ai-tutor-word-target')), findsNothing);
      await tester.pumpWidget(screen(_FakeGeminiTutor()));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      await tester.pumpWidget(screen(tutor));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(tutor.messages, isEmpty);
    },
  );

  for (final failure in ['key', 'consent', 'offline']) {
    testWidgets(
      'seeded draft keeps honest $failure failure and requires Send',
      (tester) async {
        final tutor = _FakeGeminiTutor()
          ..hasKey = failure != 'key'
          ..providerConsent = failure != 'consent';
        if (failure == 'offline') {
          tutor.replyFailure = const GeminiException(GeminiFailureCode.offline);
        }
        final voice = _FakeVoice();
        final seed = TutorWordDraft(
          controller: tutor,
          ownerScope: tutor.scope!,
          ownerEpoch: tutor.epoch,
          text: 'Visible question about station',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AiTutorScreen(
              voice: VoiceUseCases(voice),
              geminiTutor: tutor,
              wordDraft: seed,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byKey(const ValueKey('ai-tutor-input'));
        expect(tutor.messages, isEmpty);
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(input).controller!.text, seed.text);
        expect(find.byKey(const ValueKey('ai-tutor-error')), findsOneWidget);
        expect(tutor.messages.length, failure == 'offline' ? 1 : 0);
        expect(voice.requests, isEmpty);
      },
    );
  }

  testWidgets('owner-bound word draft is visible once and never sent on open', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor();
    final voice = _FakeVoice();
    final seed = TutorWordDraft(
      controller: tutor,
      ownerScope: tutor.scope!,
      ownerEpoch: tutor.epoch,
      text: 'Help me understand the English word "station".',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(voice),
          geminiTutor: tutor,
          wordDraft: seed,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    expect(tester.widget<TextField>(input).controller!.text, seed.text);
    expect(tutor.messages, isEmpty);
    expect(voice.requests, isEmpty);
    expect(find.text('ลองส่งแล้ว 0/8 ครั้งในหน้านี้'), findsOneWidget);
    await tester.enterText(input, 'Edited visible question only');
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(tutor.messages, ['Edited visible question only']);
  });

  testWidgets('typed send takes ownership from a delayed microphone start', (
    tester,
  ) async {
    final permission = Completer<MediaPermissionState>();
    final speech = _FakeSpeechGateway()..permissionGate = permission;
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
          speechPractice: SpeechPracticeUseCases(speech),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'Typed while permission pending',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    permission.complete(MediaPermissionState.granted);
    await tester.pumpAndSettle();
    expect(tutor.messages, ['Typed while permission pending']);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'เริ่มรอบใหม่'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('ai-tutor-mic')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('ai-tutor-input')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
    'a reopened page starts a new local session using the same controller',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      Widget screen() => MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
        ),
      );
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'Synthetic question',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      expect(find.text('ลองส่งแล้ว 1/8 ครั้งในหน้านี้'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text('ลองส่งแล้ว 0/8 ครั้งในหน้านี้'), findsOneWidget);
      expect(find.text('Live Gemini reply'), findsNothing);
      expect(tutor.messages.length, 1);
    },
  );

  testWidgets('mode and round actions have Android sized touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final finder in [
      find.widgetWithText(ChoiceChip, 'คิดทีละขั้น'),
      find.widgetWithText(ChoiceChip, 'อธิบายให้เลย'),
      find.widgetWithText(TextButton, 'เริ่มรอบใหม่'),
      find.widgetWithText(TextButton, 'กลับไปฝึกคำศัพท์'),
    ]) {
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets(
    'selected direct mode reaches controller without changing learner text',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: VoiceUseCases(_FakeVoice()),
            geminiTutor: tutor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'คิดทีละขั้น'))
            .selected,
        isTrue,
      );
      await tester.tap(find.text('อธิบายให้เลย'));
      await tester.enterText(
        find.byKey(const ValueKey('ai-tutor-input')),
        'Explain synthetic input',
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      expect(tutor.messages, ['Explain synthetic input']);
      expect(tutor.modes, [GeminiTutorMode.direct]);
    },
  );

  testWidgets('offline retries consume attempts and cannot exceed eight', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor()
      ..replyFailure = const GeminiException(GeminiFailureCode.offline);
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    await tester.enterText(input, 'Retry synthetic input');
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    for (var turn = 1; turn <= 8; turn++) {
      await tester.ensureVisible(find.text('ลองส่งอีกครั้ง'));
      await tester.tap(find.text('ลองส่งอีกครั้ง'));
      await tester.pumpAndSettle();
    }
    expect(tutor.messages.length, 8);
    expect(voice.requests, isEmpty);
    expect(find.textContaining('ครบ 8 ครั้ง'), findsOneWidget);
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Retry synthetic input',
    );
    expect(find.text('คุณ'), findsNothing);
  });

  testWidgets(
    'missing consent and overlong composing draft do not spend an attempt',
    (tester) async {
      final tutor = _FakeGeminiTutor()..providerConsent = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: VoiceUseCases(_FakeVoice()),
            geminiTutor: tutor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      await tester.enterText(input, 'Synthetic input without consent');
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      expect(tutor.messages, isEmpty);
      expect(find.text('ลองส่งแล้ว 0/8 ครั้งในหน้านี้'), findsOneWidget);
      tester.widget<TextField>(input).controller!.value = TextEditingValue(
        text: 'x' * 501,
        composing: const TextRange(start: 0, end: 501),
      );
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pumpAndSettle();
      expect(tutor.messages, isEmpty);
      expect(find.textContaining('500 ตัวอักษร'), findsOneWidget);
      expect(find.text('ลองส่งแล้ว 0/8 ครั้งในหน้านี้'), findsOneWidget);
    },
  );

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '2x text and IME retain draft and mode at $size $brightness',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final tutor = _FakeGeminiTutor();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              builder: (_, child) => MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 200),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: AiTutorScreen(
                voice: VoiceUseCases(_FakeVoice()),
                geminiTutor: tutor,
                wordDraft: TutorWordDraft(
                  controller: tutor,
                  ownerScope: tutor.scope!,
                  ownerEpoch: tutor.epoch,
                  text: 'Help me understand the English word "station".',
                  wordId: 'word-station',
                  spelling: 'station',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('ai-tutor-practice-target')),
          );
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(
            find.widgetWithText(ChoiceChip, 'อธิบายให้เลย'),
          );
          expect(
            find.widgetWithText(ChoiceChip, 'อธิบายให้เลย').hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.text('อธิบายให้เลย'));
          final input = find.byKey(const ValueKey('ai-tutor-input'));
          await tester.ensureVisible(input);
          await tester.enterText(input, 'Editable synthetic draft');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.widget<TextField>(input).controller!.text,
            'Editable synthetic draft',
          );
          expect(
            tester
                .widget<ChoiceChip>(
                  find.widgetWithText(ChoiceChip, 'อธิบายให้เลย'),
                )
                .selected,
            isTrue,
          );
          expect(tutor.messages, isEmpty);
        },
      );
    }
  }

  testWidgets(
    'eight attempts bound this screen session and retain ninth draft',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      final voice = _FakeVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      final send = find.byKey(const ValueKey('ai-tutor-send'));
      for (var turn = 0; turn < 8; turn++) {
        expect(input.hitTestable(), findsOneWidget);
        await tester.enterText(input, 'Synthetic question $turn');
        await tester.tap(send);
        await tester.pumpAndSettle();
        expect(
          find.text('Live Gemini reply').last.hitTestable(),
          findsOneWidget,
        );
      }
      expect(input.hitTestable(), findsOneWidget);
      await tester.enterText(input, 'Unsent ninth question');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(tutor.messages.length, 8);
      expect(voice.requests.length, 8);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Unsent ninth question',
      );
      expect(find.textContaining('ครบ 8 ครั้ง'), findsOneWidget);
      await tester.ensureVisible(find.text('เริ่มรอบใหม่'));
      await tester.tap(find.text('เริ่มรอบใหม่'));
      await tester.pumpAndSettle();
      expect(input.hitTestable(), findsOneWidget);
      await tester.enterText(input, 'Explicit new round');
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(tutor.messages.length, 9);
    },
  );

  testWidgets('composer stays visible above the keyboard at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            viewInsets: const EdgeInsets.only(bottom: 200),
          ),
          child: child!,
        ),
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ผู้ช่วย AI'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ai-tutor-input')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ai-tutor-send')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('route title fits Back and settings action at 2x', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AiTutorScreen(
                    voice: VoiceUseCases(_FakeVoice()),
                    geminiTutor: _FakeGeminiTutor(),
                  ),
                ),
              ),
              child: const Text('เปิดผู้ช่วย'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดผู้ช่วย'));
    await tester.pumpAndSettle();

    expect(find.byType(BackButton), findsOneWidget);
    expect(find.byTooltip('ตั้งค่าผู้ช่วย AI'), findsOneWidget);
    final title = find.text('ผู้ช่วย AI');
    expect(
      tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
      isFalse,
    );
    expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 96);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel keeps draft but cannot reset or send until old reply settles',
    (tester) async {
      final gate = Completer<void>();
      final tutor = _FakeGeminiTutor()..replyGate = gate;
      final voice = _FakeVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byKey(const ValueKey('ai-tutor-input'));
      await tester.enterText(input, 'Delayed synthetic draft');
      await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
      await tester.pump();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pump();
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Delayed synthetic draft',
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('ai-tutor-send')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'เริ่มรอบใหม่'))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(voice.requests, isEmpty);
      expect(find.text('Live Gemini reply'), findsNothing);
      expect(tutor.messages.length, 1);
    },
  );

  testWidgets('shows two readable tutor modes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('คิดทีละขั้น'), findsOneWidget);
    expect(find.text('อธิบายให้เลย'), findsOneWidget);
  });

  testWidgets('failed send keeps editable draft and explicit retry', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor()
      ..replyFailure = const GeminiException(GeminiFailureCode.offline);
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ai-tutor-input'));
    await tester.enterText(input, 'Synthetic failed question');
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Synthetic failed question',
    );
    expect(find.text('ลองส่งอีกครั้ง'), findsOneWidget);
    await tester.enterText(input, 'Edited synthetic question');
    tutor.replyFailure = null;
    await tester.tap(find.text('ลองส่งอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(tutor.messages, [
      'Synthetic failed question',
      'Edited synthetic question',
    ]);
    expect(find.text('Live Gemini reply'), findsOneWidget);
  });

  testWidgets('practice CTA opens existing chooser without sending to AI', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('กลับไปฝึกคำศัพท์'));
    await tester.pumpAndSettle();
    expect(find.byType(ChooseModeScreen), findsOneWidget);
    expect(tutor.messages, isEmpty);
  });

  testWidgets(
    'failed microphone cleanup before send does not dispatch Gemini or escape UI',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      final speech = _FakeSpeechGateway()..failCancel = true;
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(
            voice: VoiceUseCases(_FakeVoice()),
            geminiTutor: tutor,
            speechPractice: SpeechPracticeUseCases(speech),
          ),
        ),
      );
      await tester.pumpAndSettle();
      try {
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          'Synthetic input',
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(tutor.messages, isEmpty);
        expect(
          find.text(
            'ระบบเสียงหรือผู้ช่วยฝึกภาษาไม่พร้อมใช้งาน ข้อมูลการเรียนในเครื่องยังใช้ได้',
          ),
          findsOneWidget,
        );
      } finally {
        speech.failCancel = false;
      }
    },
  );
  testWidgets(
    'scope invalidation contains audio cleanup failures without leaking an exception',
    (tester) async {
      final tutor = _FakeGeminiTutor();
      final voice = _FakeVoice();
      await tester.pumpWidget(
        MaterialApp(
          home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
        ),
      );
      await tester.pumpAndSettle();
      voice.failStop = true;
      try {
        tutor.changeScope();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('หยุดเสียงไม่สำเร็จ กรุณาลองอีกครั้ง'),
          findsOneWidget,
        );
      } finally {
        voice.failStop = false;
      }
    },
  );
  testWidgets('shows only live provider reply and model provenance', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
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
    expect(find.text('ตอบโดย Gemini'), findsOneWidget);
    expect(find.textContaining('gemini-test'), findsNothing);
    expect(find.textContaining('Grammar:'), findsNothing);
  });

  testWidgets('provider failure is explicit and never becomes canned success', (
    tester,
  ) async {
    final tutor = _FakeGeminiTutor()
      ..replyFailure = const GeminiException(
        GeminiFailureCode.providerUnavailable,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
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

  testWidgets('microphone transcript comes from speech adapter', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway();
    final tutor = _FakeGeminiTutor();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: tutor,
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
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pumpAndSettle();
    expect(tutor.messages, ['I have real project experience']);
    expect(find.text('Live Gemini reply'), findsOneWidget);
  });

  testWidgets('backgrounding cancels microphone', (tester) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(speechGateway.cancelCalls, 1);
  });

  testWidgets('opening Gemini settings cancels active microphone', (
    tester,
  ) async {
    final speechGateway = _FakeSpeechGateway()..emitResult = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(
          voice: VoiceUseCases(_FakeVoice()),
          geminiTutor: _FakeGeminiTutor(),
          speechPractice: SpeechPracticeUseCases(speechGateway),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ai-tutor-mic')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่าผู้ช่วย AI'));
    await tester.pumpAndSettle();

    expect(speechGateway.cancelCalls, 1);
    expect(find.text('เชื่อมต่อ Gemini'), findsOneWidget);
  });

  testWidgets('opening settings invalidates delayed reply and prevents TTS', (
    tester,
  ) async {
    final gate = Completer<void>();
    final tutor = _FakeGeminiTutor()..replyGate = gate;
    final voice = _FakeVoice();
    await tester.pumpWidget(
      MaterialApp(
        home: AiTutorScreen(voice: VoiceUseCases(voice), geminiTutor: tutor),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ai-tutor-input')),
      'A delayed message',
    );
    await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
    await tester.pump();

    await tester.tap(find.byTooltip('ตั้งค่าผู้ช่วย AI'));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();

    expect(voice.requests, isEmpty);
    expect(find.text('Live Gemini reply'), findsNothing);
  });

  for (final scopeChange in [true, false]) {
    testWidgets(
      '${scopeChange ? 'scope invalidation' : 'background'} rejects late reply and TTS',
      (tester) async {
        final gate = Completer<void>();
        final tutor = _FakeGeminiTutor()..replyGate = gate;
        final voice = _FakeVoice();
        await tester.pumpWidget(
          MaterialApp(
            home: AiTutorScreen(
              voice: VoiceUseCases(voice),
              geminiTutor: tutor,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('ai-tutor-input')),
          'Synthetic A message',
        );
        await tester.tap(find.byKey(const ValueKey('ai-tutor-send')));
        await tester.pump();
        if (scopeChange) {
          tutor.changeScope();
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        await tester.pump();
        gate.complete();
        await tester.pumpAndSettle();
        expect(find.text('Live Gemini reply'), findsNothing);
        expect(voice.requests, isEmpty);
        if (scopeChange) {
          expect(find.text('Synthetic A message'), findsNothing);
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('ai-tutor-input')))
                .controller!
                .text,
            isEmpty,
          );
        } else {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      },
    );
  }
}

final class _FakeGeminiTutor implements GeminiTutorController {
  @override
  GeminiScope? scope = const GeminiScope(
    ownerId: 'synthetic-A',
    firebaseUid: null,
    isAnonymous: true,
  );
  @override
  int epoch = 0;
  final changes = StreamController<int>.broadcast(sync: true);
  @override
  Stream<int> get invalidations => changes.stream;
  void changeScope() {
    scope = const GeminiScope(
      ownerId: 'synthetic-B',
      firebaseUid: null,
      isAnonymous: true,
    );
    hasKey = false;
    changes.add(++epoch);
  }

  final List<String> messages = [];
  final List<GeminiTutorMode> modes = [];
  GeminiException? replyFailure;
  Completer<void>? replyGate;
  bool hasKey = true;
  bool providerConsent = true;
  Completer<void>? settingsGate;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    GeminiCancellation? cancellation,
  }) async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<GeminiSettingsStatus> loadSettings() async {
    await settingsGate?.future;
    return GeminiSettingsStatus(
      hasKey: hasKey,
      providerConsent: providerConsent,
      shareLearningSummary: false,
    );
  }

  @override
  Future<void> removeKey() async {}

  @override
  Future<GeminiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    GeminiCancellation? cancellation,
  }) async {
    messages.add(learnerMessage);
    modes.add(mode);
    await replyGate?.future;
    final failure = replyFailure;
    if (failure != null) throw failure;
    return GeminiTutorReply(
      text: 'Live Gemini reply',
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
  Completer<MediaPermissionState>? permissionGate;
  bool failCancel = false;
  bool emitResult = true;
  int cancelCalls = 0;

  @override
  bool isListening = false;

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    if (failCancel) throw StateError('synthetic-cancel-failure');
    isListening = false;
  }

  @override
  Future<void> initialize({
    required SpeechFailureCallback onFailure,
    required void Function(String status) onStatus,
  }) async {}

  @override
  Future<MediaPermissionState> requestPermission() async =>
      await permissionGate?.future ?? MediaPermissionState.granted;

  @override
  Future<void> start({
    required String locale,
    required SpeechEventCallback onEvent,
  }) async {
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
  bool failStop = false;
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
  Future<void> stop() async {
    if (failStop) throw StateError('synthetic-stop-failure');
  }
}

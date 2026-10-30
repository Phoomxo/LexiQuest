import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/features/voice/application/voice_use_cases.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_service_factory.dart';

import '../support/sentence_scramble_ui_harness.dart';

void main() {
  testWidgets(
    'saved ACK freezes the full sentence before feedback and returns stored finish summary',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        final bank = f.bank.toList();
        expect(await f.count(tester, 'learning_sessions'), 1);
        expect(find.byKey(const ValueKey('sentence-feedback')), findsNothing);
        f.repository.answerGate = Completer<void>();
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceUntil(tester, () => f.repository.answers.isNotEmpty);
        expect(find.byKey(const ValueKey('sentence-feedback')), findsNothing);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('sentence-response')),
              )
              .enabled,
          isFalse,
        );
        final clear = tester.widget<ButtonStyleButton>(
          find.byKey(const ValueKey('sentence-clear')),
        );
        expect(clear.onPressed, isNull);
        expect(f.bank, bank);
        expect(await f.count(tester, 'answer_attempts'), 0);
        f.repository.release();
        await sentenceSaved(tester, f);
        expect(find.byKey(const ValueKey('sentence-feedback')), findsOneWidget);
        expect(f.repository.answers.single.isCorrect, isTrue);
        expect(
          f.repository.answers.single.providerProvenance,
          f.session.providerProvenance,
        );
        expect(
          f.repository.answers.single.evidenceContext.evidenceClass.name,
          'recreational',
        );
        expect(
          f.repository.answers.single.evidenceContext.engagementAllowed,
          isFalse,
        );
        await sentenceTap(tester, const ValueKey('sentence-finish'));
        await sentenceUntil(tester, () => f.summary != null);
        expect(
          (f.summary!.state, f.summary!.correctCount, f.summary!.wrongCount),
          ('completed', 1, 0),
        );
        expect(await f.count(tester, 'answer_attempts'), 1);
        for (final table in [
          'srs_states',
          'points_ledger_entries',
          'reward_transactions',
          'achievement_unlocks',
          'events_v2',
          'assessment_runs',
        ]) {
          expect(await f.count(tester, table), 0, reason: table);
        }
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'lost start answer and finish ACK retries use original handle ID time bank and end',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        f.repository.loseStart = true;
        await mountSentenceUi(tester, f, ready: false);
        await sentenceRetry(tester, f);
        await sentenceTap(tester, const ValueKey('sentence-retry'));
        await sentenceReady(tester, f);
        expect(
          identical(f.repository.starts.first, f.repository.starts.last),
          isTrue,
        );
        final bank = f.bank.toList();
        f.repository.loseAnswer = true;
        await sentenceType(tester, 'wrong');
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceRetry(tester, f);
        final original = f.repository.answers.single;
        await sentenceTap(tester, const ValueKey('sentence-retry'));
        await sentenceSaved(tester, f);
        expect(
          identical(f.repository.answers.first, f.repository.answers.last),
          isTrue,
        );
        expect(f.repository.answers.last.occurredAtUtc, original.occurredAtUtc);
        expect(f.bank, bank);
        f.repository.loseFinish = true;
        await sentenceTap(tester, const ValueKey('sentence-finish'));
        await sentenceRetry(tester, f);
        final close = f.repository.finishes.single;
        await sentenceTap(tester, const ValueKey('sentence-retry'));
        await sentenceUntil(tester, () => f.summary != null);
        expect(
          identical(f.repository.finishes.first, f.repository.finishes.last),
          isTrue,
        );
        expect(f.repository.finishes.last.endedAtUtc, close.endedAtUtc);
        expect(f.summary!.wrongCount, 1);
        expect(await f.count(tester, 'learning_sessions'), 1);
        expect(await f.count(tester, 'answer_attempts'), 1);
        expect(await f.count(tester, 'outbox_operations'), 1);
        expect(f.core.provider.requests, hasLength(1));
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'owned meaning cue is vocabulary meaning and not an invented sentence translation',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(
        tester,
        meaning: 'ข้อมูลสังเคราะห์4582',
      );
      final semantics = tester.ensureSemantics();
      try {
        await mountSentenceUi(tester, f, language: 'en');
        final cue = find.byKey(const ValueKey('sentence-meaning-cue'));
        await sentenceReveal(tester, cue);
        final copy = tester.widget<Text>(cue).data!;
        expect(copy, contains('ข้อมูลสังเคราะห์4582'));
        expect(
          copy.toLowerCase(),
          anyOf(contains('vocabulary'), contains('word')),
        );
        expect(copy.toLowerCase(), isNot(contains('translation')));
        expect(tester.getSemantics(cue).label, copy);
        expect(f.voice.spokenRequests, isEmpty);
      } finally {
        semantics.dispose();
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'duplicate chunks and standalone punctuation use indexed pieces with Undo and Clear',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(
        tester,
        sentence: 'school — school feels calm.',
      );
      try {
        await mountSentenceUi(tester, f);
        final bank = f.bank.toList();
        expect(bank.where((piece) => piece == 'school'), hasLength(2));
        expect(bank, contains('—'));
        for (var index = 0; index < bank.length; index++) {
          await sentenceTap(tester, ValueKey('sentence-token-$index'));
          await sentenceTap(tester, ValueKey('sentence-token-$index'));
        }
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          bank.join(' '),
        );
        await sentenceTap(tester, const ValueKey('sentence-undo'));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          bank.take(bank.length - 1).join(' '),
        );
        await sentenceTap(tester, const ValueKey('sentence-clear'));
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          '',
        );
        expect(f.bank, bank);
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'stale reused and out-of-range drop indices cannot duplicate pieces',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        final target = tester.widget<DragTarget<int>>(
          find.byKey(const ValueKey('sentence-slot-0')),
        );
        expect(
          target.onWillAcceptWithDetails!(
            DragTargetDetails(data: -1, offset: Offset.zero),
          ),
          isFalse,
        );
        expect(
          target.onWillAcceptWithDetails!(
            DragTargetDetails(data: f.bank.length, offset: Offset.zero),
          ),
          isFalse,
        );
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 0, offset: Offset.zero),
        );
        await tester.pump();
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 0, offset: Offset.zero),
        );
        target.onAcceptWithDetails!(
          DragTargetDetails(data: 999, offset: Offset.zero),
        );
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          f.bank.first,
        );
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'real Tab and Enter activate indexed tokens and typed alternative saves whole sentence',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        final first = find.byKey(const ValueKey('sentence-token-0'));
        await sentenceReveal(tester, first);
        tester.widget<OutlinedButton>(first).focusNode!.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final second = tester.widget<OutlinedButton>(
          find.byKey(const ValueKey('sentence-token-1')),
        );
        expect(second.focusNode!.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('sentence-arranged')))
              .data,
          f.bank[1],
        );
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets('reduced motion applies actual drag drop immediately', (
    tester,
  ) async {
    final f = await SentenceScrambleUiFixture.open(tester);
    try {
      await mountSentenceUi(tester, f, reducedMotion: true);
      final source = find.byType(Draggable<int>).first;
      final target = find.byKey(const ValueKey('sentence-slot-0'));
      await tester.ensureVisible(source);
      await tester.pump();
      final drag = await tester.startGesture(tester.getCenter(source));
      await drag.moveBy(const Offset(0, -30));
      await drag.moveTo(tester.getCenter(target));
      await tester.pump();
      await drag.up();
      await tester.pump();
      final decorated = tester.widget<DecoratedBox>(
        find.descendant(of: target, matching: find.byType(DecoratedBox)).first,
      );
      expect(
        (decorated.decoration as BoxDecoration).color,
        Theme.of(tester.element(target)).colorScheme.primaryContainer,
      );
      expect(
        tester
            .widget<AnimatedContainer>(
              find
                  .descendant(
                    of: target,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .duration,
        Duration.zero,
      );
    } finally {
      await f.close(tester);
    }
  });

  for (final stage in ['start', 'save', 'finish']) {
    for (final loss in ['aba', 'lifecycle', 'route']) {
      testWidgets(
        '$stage pending $loss hides old content and cannot add a late canonical fact',
        (tester) async {
          final f = await SentenceScrambleUiFixture.open(tester);
          try {
            await _pending(tester, f, stage);
            await _invalidate(tester, f, loss);
            f.repository.release();
            await tester.runAsync(f.repository.settle);
            tester.binding.scheduleForcedFrame();
            await tester.pump();
            expect(
              await f.count(tester, 'learning_sessions'),
              stage == 'start' ? 0 : 1,
            );
            expect(
              await f.count(tester, 'answer_attempts'),
              stage == 'finish' ? 1 : 0,
            );
            if (stage != 'start') {
              final row = (await tester.runAsync(
                () => f.core.storage.session(f.session.id),
              ))!;
              expect(row['state'], 'active');
              expect(row['ended_at_utc_ms'], isNull);
            }
            expect(
              find.byKey(
                const ValueKey('sentence-feedback'),
                skipOffstage: false,
              ),
              findsNothing,
            );
            expect(
              find.textContaining(
                'synthetic owned vocabulary meaning',
                skipOffstage: false,
              ),
              findsNothing,
            );
            expect(f.summary, isNull);
          } finally {
            await f.close(tester);
          }
        },
      );
    }
  }

  for (final loss in ['null', 'error', 'done', 'dependencies', 'dispose']) {
    testWidgets('pending save $loss cannot reveal a private late receipt', (
      tester,
    ) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await _pending(tester, f, 'save');
        await _invalidate(tester, f, loss);
        f.repository.release();
        await tester.runAsync(f.repository.settle);
        await tester.pump();
        expect(await f.count(tester, 'answer_attempts'), 0);
        expect(
          find.byKey(const ValueKey('sentence-feedback'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.textContaining('SYNTHETIC_PRIVATE_CANARY', skipOffstage: false),
          findsNothing,
        );
      } finally {
        await f.close(tester);
      }
    });
  }

  testWidgets(
    'synchronous null to same owner during build never restores old input or throws during-frame setState',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        await sentenceType(tester, 'SYNTHETIC_PRIVATE_INPUT');
        SchedulerPhase? phase;
        f.onRebuild = () {
          phase = SchedulerBinding.instance.schedulerPhase;
          f.owners.add(null);
          f.owners.add(configuredOwnerId);
        };
        f.rebuild.value++;
        await tester.pump();
        await tester.pump();
        expect(phase, SchedulerPhase.persistentCallbacks);
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('sentence-response'), skipOffstage: false),
          findsNothing,
        );
        expect(
          find.textContaining('SYNTHETIC_PRIVATE_INPUT', skipOffstage: false),
          findsNothing,
        );
        expect(f.repository.starts, hasLength(1));
        expect(f.repository.answers, isEmpty);
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'missing owner observation cannot start and pre-start system Back can leave',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f, ready: false, emitOwner: false);
        await tester.pump(const Duration(milliseconds: 50));
        expect(f.repository.starts, isEmpty);
        expect(await f.count(tester, 'learning_sessions'), 0);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SentenceScrambleScreen), findsNothing);
        expect(f.repository.finishes, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'idle Back confirmation cancel preserves draft and keeps the native round usable',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        await sentenceType(tester, 'partially arranged answer');
        final bank = f.bank.toList();
        await sentenceTap(tester, const ValueKey('sentence-back'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('sentence-back-keep')),
          findsOneWidget,
        );
        await sentenceTap(tester, const ValueKey('sentence-back-keep'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('sentence-response')),
              )
              .controller!
              .text,
          'partially arranged answer',
        );
        expect(f.bank, bank);
        expect(f.repository.finishes, isEmpty);
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
        expect(f.repository.starts, hasLength(1));
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'saved system Back warns about retained answers and no resume then leaves without finishing',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f, language: 'en');
        await sentenceType(tester, 'wrong');
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        final dialog = find.byType(AlertDialog);
        expect(
          find.descendant(of: dialog, matching: _textContaining('saved')),
          findsWidgets,
        );
        expect(
          find.descendant(of: dialog, matching: _textContaining('resume')),
          findsWidgets,
        );
        await sentenceTap(tester, const ValueKey('sentence-back-leave'));
        await tester.pumpAndSettle();
        expect(find.byType(SentenceScrambleScreen), findsNothing);
        expect(await f.count(tester, 'answer_attempts'), 1);
        final row = (await tester.runAsync(
          () => f.core.storage.session(f.session.id),
        ))!;
        expect(row['state'], 'active');
        expect(row['ended_at_utc_ms'], isNull);
        expect(f.repository.finishes, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final stage in ['start', 'save', 'finish']) {
    testWidgets(
      'actual $stage in-flight ACK disables app and system Back only until delivery',
      (tester) async {
        final f = await SentenceScrambleUiFixture.open(tester);
        try {
          await _pending(tester, f, stage);
          final back = find.byKey(const ValueKey('sentence-back'));
          await tester.ensureVisible(back);
          await tester.pump();
          await tester.tap(back.hitTestable());
          await tester.pump();
          await tester.binding.handlePopRoute();
          await tester.pump();
          expect(find.byType(SentenceScrambleScreen), findsOneWidget);
          expect(
            find.byKey(const ValueKey('sentence-back-keep')),
            findsNothing,
          );
          f.repository.release();
          await tester.runAsync(f.repository.settle);
          await tester.pump();
          if (stage == 'finish') {
            await sentenceUntil(tester, () => f.summary != null);
          } else {
            if (stage == 'start') {
              await sentenceReady(tester, f);
            }
            await sentenceTap(tester, const ValueKey('sentence-back'));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('sentence-back-keep')),
              findsOneWidget,
            );
            await sentenceTap(tester, const ValueKey('sentence-back-keep'));
          }
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'stale leave callback from covered own dialog cannot pop a newer route',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        await sentenceTap(tester, const ValueKey('sentence-back'));
        await tester.pumpAndSettle();
        final leave = tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('sentence-back-leave')),
            )
            .onPressed!;
        unawaited(
          f.navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Newer outer route')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        leave();
        await tester.pumpAndSettle();
        expect(find.text('Newer outer route'), findsOneWidget);
        expect(f.repository.finishes, isEmpty);
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language 320px 200 percent long token and actual IME retain reachable controls',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final f = await SentenceScrambleUiFixture.open(
          tester,
          sentence: 'school ${'extraordinary' * 8} travels calmly.',
        );
        try {
          await mountSentenceUi(tester, f, language: language, scale: 2);
          final tile = find.byKey(const ValueKey('sentence-token-0'));
          await sentenceReveal(tester, tile);
          expect(tile.hitTestable(), findsOneWidget);
          await tester.tap(tile.hitTestable());
          expect(tester.takeException(), isNull);
          await sentenceType(tester, f.session.content.sentence);
          tester.view.viewInsets = const FakeViewPadding(bottom: 220);
          await tester.pump();
          await sentenceTap(tester, const ValueKey('sentence-save'));
          await sentenceSaved(tester, f);
          expect(
            find.byKey(const ValueKey('sentence-finish')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets(
    'voice absent and sentences beyond VoiceRequest500 never create default playback while typed play continues',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(
        tester,
        sentence: 'school ${'a' * 600}.',
      );
      try {
        await mountSentenceUi(tester, f);
        final listen = find.byKey(const ValueKey('sentence-listen-original'));
        if (listen.evaluate().isNotEmpty) {
          expect(tester.widget<ButtonStyleButton>(listen).onPressed, isNull);
        }
        expect(f.voice.spokenRequests, isEmpty);
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'missing borrowed voice leaves typed mode available without implicit provider creation',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f, includeVoice: false);
        final listen = find.byKey(const ValueKey('sentence-listen-original'));
        if (listen.evaluate().isNotEmpty) {
          expect(tester.widget<ButtonStyleButton>(listen).onPressed, isNull);
        }
        await sentenceType(tester, f.session.content.sentence);
        await sentenceTap(tester, const ValueKey('sentence-save'));
        await sentenceSaved(tester, f);
        expect(f.repository.answers.single.isCorrect, isTrue);
        expect(f.voice.spokenRequests, isEmpty);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final loss in ['null', 'route', 'lifecycle']) {
    testWidgets(
      'owned playback $loss stops once and late voice ACK cannot restore content',
      (tester) async {
        final f = await SentenceScrambleUiFixture.open(tester);
        try {
          f.voice.gate = Completer<VoicePlaybackResult>();
          await mountSentenceUi(tester, f);
          expect(f.voice.spokenRequests, isEmpty);
          await sentenceTap(tester, const ValueKey('sentence-listen-original'));
          await sentenceUntil(tester, () => f.voice.spokenRequests.isNotEmpty);
          await _invalidate(tester, f, loss);
          await tester.pump();
          expect(f.voice.stops, 1);
          f.voice.release();
          await tester.pump();
          expect(
            find.byKey(
              const ValueKey('sentence-response'),
              skipOffstage: false,
            ),
            findsNothing,
          );
        } finally {
          await f.close(tester);
        }
        expect(
          f.voice.stops,
          1,
          reason:
              'disposal must not stop another playback after ownership was cleared',
        );
      },
    );
  }

  testWidgets(
    'voice error is fixed copy and only an explicit retry creates another request',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        f.voice.rejectNext = true;
        await mountSentenceUi(tester, f);
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await tester.pump();
        expect(f.voice.spokenRequests, hasLength(1));
        expect(find.textContaining('SYNTHETIC_PRIVATE_VOICE'), findsNothing);
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => f.voice.spokenRequests.length == 2);
        await sentenceTap(tester, const ValueKey('sentence-stop'));
        expect(await f.count(tester, 'answer_attempts'), 0);
      } finally {
        await f.close(tester);
      }
    },
  );

  for (final stage in ['start', 'save', 'finish']) {
    testWidgets(
      '$stage lost ACK error allows Back cancel without a new native operation',
      (tester) async {
        final f = await SentenceScrambleUiFixture.open(tester);
        try {
          if (stage == 'start') {
            f.repository.loseStart = true;
            await mountSentenceUi(tester, f, ready: false);
          } else {
            await mountSentenceUi(tester, f);
            await sentenceType(tester, f.session.content.sentence);
            if (stage == 'save') {
              f.repository.loseAnswer = true;
            }
            await sentenceTap(tester, const ValueKey('sentence-save'));
            if (stage == 'finish') {
              await sentenceSaved(tester, f);
              f.repository.loseFinish = true;
              await sentenceTap(tester, const ValueKey('sentence-finish'));
            }
          }
          await sentenceRetry(tester, f);
          final operations = (
            f.repository.starts.length,
            f.repository.answers.length,
            f.repository.finishes.length,
          );
          await sentenceTap(tester, const ValueKey('sentence-back'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('sentence-back-keep')),
            findsOneWidget,
          );
          await sentenceTap(tester, const ValueKey('sentence-back-keep'));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('sentence-retry')), findsOneWidget);
          expect((
            f.repository.starts.length,
            f.repository.answers.length,
            f.repository.finishes.length,
          ), operations);
          expect(f.summary, isNull);
        } finally {
          await f.close(tester);
        }
      },
    );
  }

  testWidgets('Replay waits for the prior owned Stop before another Speak', (
    tester,
  ) async {
    final f = await SentenceScrambleUiFixture.open(tester);
    try {
      await mountSentenceUi(tester, f);
      await sentenceTap(tester, const ValueKey('sentence-listen-original'));
      await sentenceUntil(tester, () => f.voice.spokenRequests.length == 1);
      f.voice.stopGate = Completer<void>();
      await sentenceTap(tester, const ValueKey('sentence-listen-original'));
      expect(f.voice.stops, 1);
      expect(f.voice.spokenRequests, hasLength(1));
      f.voice.stopGate!.complete();
      await sentenceUntil(tester, () => f.voice.spokenRequests.length == 2);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets('manual Stop then Replay waits for the original pending stop', (
    tester,
  ) async {
    final f = await SentenceScrambleUiFixture.open(tester);
    try {
      await mountSentenceUi(tester, f);
      await sentenceTap(tester, const ValueKey('sentence-listen-original'));
      await sentenceUntil(tester, () => f.voice.spokenRequests.length == 1);
      await tester.pumpAndSettle();
      f.voice.stopGate = Completer<void>();
      await sentenceTap(tester, const ValueKey('sentence-stop'));
      expect(f.voice.stops, 1);
      final replay = find.byKey(const ValueKey('sentence-listen-original'));
      await tester.ensureVisible(replay);
      await tester.pump();
      await tester.tap(replay.hitTestable());
      await tester.pump();
      expect(f.voice.spokenRequests, hasLength(1));
      expect(f.voice.stops, 1);
      f.voice.stopGate!.complete();
      await sentenceUntil(tester, () => f.voice.spokenRequests.length == 2);
    } finally {
      await f.close(tester);
    }
  });

  testWidgets(
    'retained Stop intent during Replay wait cancels the pending new Speak',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      try {
        await mountSentenceUi(tester, f);
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => f.voice.spokenRequests.length == 1);
        await tester.pumpAndSettle();
        final stop = find.byKey(const ValueKey('sentence-stop'));
        await sentenceReveal(tester, stop);
        final stopIntent = tester.widget<ButtonStyleButton>(stop).onPressed!;
        f.voice.stopGate = Completer<void>();
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        expect(f.voice.stops, 1);
        expect(f.voice.spokenRequests, hasLength(1));
        stopIntent();
        await tester.pump();
        expect(f.voice.stops, 1);
        f.voice.stopGate!.complete();
        final replay = find.byKey(const ValueKey('sentence-listen-original'));
        await sentenceUntil(
          tester,
          () => tester.widget<ButtonStyleButton>(replay).onPressed != null,
        );
        expect(f.voice.spokenRequests, hasLength(1));
        expect(f.voice.stops, 1);
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => f.voice.spokenRequests.length == 2);
      } finally {
        await f.close(tester);
      }
    },
  );

  testWidgets(
    'disposing a current screen stops only its explicitly owned playback once',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      var closed = false;
      try {
        await mountSentenceUi(tester, f);
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => f.voice.spokenRequests.isNotEmpty);
        expect(f.voice.stops, 0);
        await f.close(tester);
        closed = true;
        expect(f.voice.stops, 1);
      } finally {
        if (!closed) {
          await f.close(tester);
        }
      }
    },
  );

  testWidgets(
    'borrowed actual managed voice remains usable after the screen is disposed',
    (tester) async {
      final f = await SentenceScrambleUiFixture.open(tester);
      final native = _NativeAdapter();
      final player = _PlayerAdapter();
      final service = VoiceServiceFactory.create(
        config: AppConfig.fromValues(
          voiceApiUrl: 'https://synthetic.invalid',
          isDebug: true,
        ),
        client: MockClient((_) async => http.Response('', 503)),
        firebaseTokenReader: _TokenReader(),
        nativeTtsAdapter: native,
        audioPlayerAdapter: player,
      );
      var fixtureClosed = false;
      try {
        await mountSentenceUi(tester, f, voice: VoiceUseCases(service));
        await sentenceTap(tester, const ValueKey('sentence-listen-original'));
        await sentenceUntil(tester, () => native.spoken.isNotEmpty);
        await f.close(tester);
        fixtureClosed = true;
        expect(player.disposals, 0);
        final result = await tester.runAsync(
          () => service.speak(
            VoiceRequest.create(
              text: 'Synthetic subsequent use.',
              language: 'en',
              voiceId: 'teacher_female',
              speed: 1,
              contentId: 'synthetic-borrowed-proof',
              contentType: 'sentence_scramble',
              mode: VoiceMode.practice,
            ),
          ),
        );
        expect(result!.actualEngine, VoiceEngine.nativeTts);
        expect(native.spoken.last, 'Synthetic subsequent use.');
        expect(player.disposals, 0);
      } finally {
        if (!fixtureClosed) {
          await f.close(tester);
        }
        await tester.runAsync(service.dispose);
      }
      expect(player.disposals, 1);
    },
  );
}

Future<void> _pending(
  WidgetTester tester,
  SentenceScrambleUiFixture f,
  String stage,
) async {
  if (stage == 'start') {
    f.repository.startGate = Completer<void>();
    await mountSentenceUi(tester, f, ready: false);
    await sentenceUntil(tester, () => f.repository.starts.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    return;
  }
  await mountSentenceUi(tester, f);
  await sentenceType(tester, f.session.content.sentence);
  if (stage == 'save') {
    f.repository.answerGate = Completer<void>();
    await sentenceTap(tester, const ValueKey('sentence-save'));
    await sentenceUntil(tester, () => f.repository.answers.isNotEmpty);
    return;
  }
  await sentenceTap(tester, const ValueKey('sentence-save'));
  await sentenceSaved(tester, f);
  f.repository.finishGate = Completer<void>();
  await sentenceTap(tester, const ValueKey('sentence-finish'));
  await sentenceUntil(tester, () => f.repository.finishes.isNotEmpty);
}

Future<void> _invalidate(
  WidgetTester tester,
  SentenceScrambleUiFixture f,
  String loss,
) async {
  switch (loss) {
    case 'null':
      f.owners.add(null);
    case 'aba':
      f.owners.add(configuredOtherOwnerId);
      f.owners.add(configuredOwnerId);
    case 'error':
      f.owners.addError(StateError('SYNTHETIC_PRIVATE_CANARY'));
    case 'done':
      await tester.runAsync(f.owners.close);
    case 'lifecycle':
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    case 'route':
      unawaited(
        f.navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('Outer overlay')),
          ),
        ),
      );
    case 'dependencies':
      f.dependencies.value = f.createDependencies();
    case 'dispose':
      await tester.pumpWidget(const SizedBox.shrink());
  }
  tester.binding.scheduleForcedFrame();
  await tester.pump();
}

Finder _textContaining(String value) => find.byWidgetPredicate(
  (widget) =>
      widget is Text && (widget.data ?? '').toLowerCase().contains(value),
);

final class _NativeAdapter implements NativeTtsAdapter {
  final spoken = <String>[];
  @override
  Future<void> setLanguage(String language) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setPitch(double pitch) async {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}
}

final class _PlayerAdapter implements AudioPlayerAdapter {
  int disposals = 0;
  @override
  Future<void> playBytes(Uint8List bytes) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class _TokenReader implements FirebaseTokenReader {
  @override
  Future<String?> readIdToken({required bool forceRefresh}) async =>
      'synthetic-voice-token';
}

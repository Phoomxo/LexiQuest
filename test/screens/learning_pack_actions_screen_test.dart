import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

import 'learning_pack_test_support.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  testWidgets(
    'one-word pack starts and finishes the canonical owned SRS caller',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        await tester.runAsync(() => h.seed(syntheticPackUiContent()));
        await tester.pumpWidget(h.app());
        await openPackUiDetail(tester);
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        await tapPackUi(tester, 'pack-practice-0');
        await untilPackUi(
          tester,
          () => find.byKey(const Key('srs-card')).evaluate().isNotEmpty,
        );
        final screen = tester.widget<SrsFlashcardsScreen>(
          find.byType(SrsFlashcardsScreen),
        );
        expect(screen.wordList, isNull);
        expect(screen.sourceWordIds, hasLength(1));
        expect(screen.expectedOwnerId, 'synthetic-actions-owner');
        expect(screen.learning, same(h.learning));
        expect(await tester.runAsync(() => h.count('learning_sessions')), 1);
        await tapPackUi(tester, 'srs-flip');
        await tester.pump(const Duration(milliseconds: 450));
        await tapPackUi(tester, 'srs-got');
        await untilPackUi(
          tester,
          () => find.byKey(const Key('srs-next')).evaluate().isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('answer_attempts')), 1);
        await tapPackUi(tester, 'srs-next');
        await untilPackUi(
          tester,
          () => find.byType(SrsFlashcardsScreen).evaluate().isEmpty,
        );
        await idlePackUi(tester);
        expect(await tester.runAsync(() => h.count('srs_states')), 1);
        final answer = (await tester.runAsync(h.canonicalAnswer))!;
        expect(answer.read<String>('prompt_mode'), 'srsRecall');
        expect(answer.read<String>('activity_type'), 'srsReview');
        expect(answer.read<String>('word_id'), screen.sourceWordIds!.single);
        expect(answer.read<String>('owner_id'), screen.expectedOwnerId);
        expect(answer.read<String>('state'), 'completed');
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'rich card reaches existing speech, saved word and report writers',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        await tester.runAsync(() => h.seed(syntheticPackUiContent()));
        await tester.pumpWidget(h.app());
        await openPackUiDetail(tester);
        await tapPackUi(tester, 'pack-word-cat');
        await untilPackUi(
          tester,
          () => find.text('A small pet that meows.').evaluate().isNotEmpty,
        );
        expect(find.text('The cat sleeps.'), findsOneWidget);
        expect(find.text('แมวนอนหลับ'), findsOneWidget);
        expect(find.text('Picture a sleeping cat.'), findsOneWidget);
        expect(find.text('Listen for the final sound.'), findsOneWidget);
        expect(find.text('Say it, then use it in a sentence.'), findsOneWidget);
        await tapPackUi(tester, 'pack-word-speak');
        await untilPackUi(tester, () => h.voice.requests.isNotEmpty);
        expect(h.voice.requests.single.text, 'cat');
        expect(h.voice.requests.single.mode, VoiceMode.practice);
        expect(h.voice.requests.single.contentType, 'vocabulary_word');
        await untilPackUi(tester, () {
          final action = find.byKey(const ValueKey('pack-word-save'));
          return action.evaluate().isNotEmpty &&
              tester.widget<OutlinedButton>(action).onPressed != null;
        });
        await tapPackUi(tester, 'pack-word-save');
        await untilPackUi(
          tester,
          () => find.text('บันทึกสถานะคำแล้ว').evaluate().isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('saved_words')), 1);
        await tapPackUi(tester, 'pack-word-report');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('word-report-reason:incorrectMeaning'))
              .evaluate()
              .isNotEmpty,
        );
        await tapPackUi(tester, 'word-report-reason:incorrectMeaning');
        await tapPackUi(tester, 'word-report-review');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('word-report-confirm'))
              .evaluate()
              .isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('word_reports')), 0);
        await tapPackUi(tester, 'word-report-confirm');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('word-report-queued'))
              .evaluate()
              .isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('word_reports')), 1);
        expect(await tester.runAsync(() => h.count('learning_sessions')), 0);
        expect(await tester.runAsync(() => h.count('answer_attempts')), 0);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'retained install action cannot write after owner B or owner ABA',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        final pack = syntheticPackUiContent();
        await tester.pumpWidget(
          h.app(
            pickFile: () async =>
                XFile.fromData(pack.bytes, name: 'synthetic.json'),
          ),
        );
        await packUiReady(tester);
        await tapPackUi(tester, 'pack-import');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('pack-confirm-install'))
              .evaluate()
              .isNotEmpty,
        );
        final retained = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('pack-confirm-install')),
            )
            .onPressed!;
        await tester.runAsync(() => h.switchOwner('synthetic-actions-other'));
        await packUiReady(tester);
        retained();
        await tester.pump();
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        await tester.runAsync(() => h.switchOwner('synthetic-actions-owner'));
        await packUiReady(tester);
        retained();
        await tester.pump();
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          0,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'lost installation acknowledgement retries the same immutable intent',
    (tester) async {
      final h = (await tester.runAsync(
        () => LearningPackUiHarness.open(loseAck: true),
      ))!;
      try {
        final pack = syntheticPackUiContent();
        await tester.pumpWidget(
          h.app(
            pickFile: () async =>
                XFile.fromData(pack.bytes, name: 'synthetic.json'),
          ),
        );
        await packUiReady(tester);
        await tapPackUi(tester, 'pack-import');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('pack-confirm-install'))
              .evaluate()
              .isNotEmpty,
        );
        await tapPackUi(tester, 'pack-confirm-install');
        await idlePackUi(tester);
        await revealPackUi(tester, 'pack-retry');
        await untilPackUi(tester, () {
          final button = find.byKey(const ValueKey('pack-retry'));
          return button.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(button).onPressed != null;
        });
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          1,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 1);
        await tapPackUi(tester, 'pack-retry');
        await untilPackUi(
          tester,
          () => find.text('ติดตั้งแพ็กบทเรียนแล้ว').evaluate().isNotEmpty,
        );
        expect(h.repository.imports, hasLength(2));
        expect(h.repository.imports[1], same(h.repository.imports[0]));
        expect(
          await tester.runAsync(() => h.count('learning_pack_versions')),
          1,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_imports')), 1);
        expect(
          await tester.runAsync(() => h.count('lexical_content_snapshots')),
          1,
        );
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  testWidgets(
    'cached-only installation uses the stored revision; cache removal retains learning',
    (tester) async {
      final h = (await tester.runAsync(LearningPackUiHarness.open))!;
      try {
        final pack = syntheticPackUiContent();
        await tester.pumpWidget(
          h.app(
            pickFile: () async =>
                XFile.fromData(pack.bytes, name: 'synthetic.json'),
          ),
        );
        await packUiReady(tester);
        await tapPackUi(tester, 'pack-import');
        await untilPackUi(
          tester,
          () => find
              .byKey(const ValueKey('pack-cache-preview'))
              .evaluate()
              .isNotEmpty,
        );
        await tapPackUi(tester, 'pack-cache-preview');
        await untilPackUi(
          tester,
          () => find.text('เก็บไฟล์ออฟไลน์แล้ว').evaluate().isNotEmpty,
        );
        await idlePackUi(tester);
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 0);
        await tapPackUi(tester, 'pack-install-cached');
        await untilPackUi(
          tester,
          () => find.text('ติดตั้งแพ็กบทเรียนแล้ว').evaluate().isNotEmpty,
        );
        await idlePackUi(tester);
        expect(h.repository.imports.last.expectedRevision, 1);
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 1);
        await tapPackUi(tester, 'pack-remove');
        await untilPackUi(
          tester,
          () => find.text('ลบไฟล์แพ็กออฟไลน์?').evaluate().isNotEmpty,
        );
        expect(
          find.text(
            'ลบเฉพาะไฟล์แพ็กและการปักหมุด คำศัพท์ การ์ด สื่อ และประวัติการเรียนยังอยู่',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'ลบไฟล์แพ็ก'));
        await untilPackUi(
          tester,
          () => find
              .text('ลบเฉพาะไฟล์แพ็กแล้ว การ์ด สื่อ และประวัติการเรียนยังอยู่')
              .evaluate()
              .isNotEmpty,
        );
        expect(await tester.runAsync(() => h.count('vocabulary_words')), 1);
        expect(
          await tester.runAsync(() => h.count('lexical_content_snapshots')),
          1,
        );
        final stored = (await tester.runAsync(h.stored))!;
        expect(stored.cacheState, PackCacheState.notCached);
        expect(stored.isPinned, isFalse);
        await tapPackUi(tester, 'pack-word-cat');
        await untilPackUi(
          tester,
          () => find.text('A small pet that meows.').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
      } catch (error, stack) {
        h.recordFailure(error, stack, tester);
        rethrow;
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await closePackUi(tester, h);
      }
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'catalog and actions remain reachable at 320px, 200% text, keyboard, $brightness',
      (tester) async {
        final h = (await tester.runAsync(LearningPackUiHarness.open))!;
        tester.view.physicalSize = const Size(320, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          await tester.runAsync(() => h.seed(syntheticPackUiContent()));
          await tester.pumpWidget(
            h.app(brightness: brightness, largeText: true),
          );
          await packUiReady(tester);
          await tapPackUi(tester, 'pack-search');
          await tester.enterText(
            find.byKey(const ValueKey('pack-search')),
            'nothing',
          );
          await tester.pump();
          expect(find.text('Synthetic actions pack'), findsNothing);
          await tester.enterText(
            find.byKey(const ValueKey('pack-search')),
            'Synthetic',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await openPackUiDetail(tester);
          await tapPackUi(tester, 'pack-word-cat');
          await untilPackUi(
            tester,
            () => find.text('A small pet that meows.').evaluate().isNotEmpty,
          );
          await tapPackUi(tester, 'pack-word-speak');
          await untilPackUi(tester, () => h.voice.requests.isNotEmpty);
          expect(find.textContaining('synthetic-actions-owner'), findsNothing);
          expect(tester.takeException(), isNull);
        } catch (error, stack) {
          h.recordFailure(error, stack, tester);
          rethrow;
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await closePackUi(tester, h);
        }
      },
    );
  }
}

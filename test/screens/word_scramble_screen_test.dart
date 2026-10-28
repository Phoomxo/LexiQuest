import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/sentence_scramble_screen.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

import '../support/accessibility_semantics_test_support.dart';
import '../support/fail_once_learning_test_fixture.dart';

void main() {
  test(
    'B05 FORM11 construction preserves case punctuation and spacing rules',
    () {
      const word = WordScrambleModeAdapter();
      const sentence = SentenceScrambleModeAdapter();
      expect(
        word.evaluate(target: 'letter', response: 'letter').isCorrect,
        isTrue,
      );
      expect(
        word.evaluate(target: 'letter', response: 'Letter').isCorrect,
        isFalse,
      );
      expect(
        sentence
            .evaluate(target: 'I can can.', response: ' I  can can. ')
            .isCorrect,
        isTrue,
      );
      expect(
        sentence
            .evaluate(target: 'I can can.', response: 'I can can')
            .isCorrect,
        isFalse,
      );
    },
  );

  for (final wordMode in [true, false]) {
    testWidgets(
      'B05 native route retirement fences retained submit word=$wordMode',
      (tester) async {
        final repository = FailOnceLearningRepository(failFirst: false);
        final learning = buildFailOnceLearningUseCases(
          repository: repository,
          idPrefix: 'retired-native',
        );
        final adapter = wordMode
            ? const WordScrambleModeAdapter()
            : const SentenceScrambleModeAdapter();
        final controller = UnifiedLessonController(
          learning: learning,
          adapter: adapter,
        );
        addTearDown(controller.dispose);
        final lifecycle = UnifiedLessonRouteLifecycle(
          controller,
          learning,
          () => DateTime.utc(2026, 9, 13),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: UnifiedLessonShell(
              controller: controller,
              routeLifecycle: lifecycle,
              builder: (_) => wordMode
                  ? WordScrambleScreen(
                      word: 'ab',
                      ownerId: 'owner-1',
                      sessionId: 'session-1',
                      wordId: 'word-1',
                      evidenceAdapter: CurrentActivityEvidenceAdapter(
                        learning: learning,
                      ),
                    )
                  : SentenceScrambleScreen(
                      targetSentence: 'I can.',
                      ownerId: 'owner-1',
                      sessionId: 'session-1',
                      wordId: 'word-1',
                      evidenceAdapter: CurrentActivityEvidenceAdapter(
                        learning: learning,
                      ),
                    ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (wordMode) {
          final letters = createStableScramble('ab');
          for (final value in ['a', 'b']) {
            tester
                .widget<GestureDetector>(
                  find.byKey(ValueKey('word-letter-${letters.indexOf(value)}')),
                )
                .onTap!();
            await tester.pump();
          }
        } else {
          for (final value in ['I', 'can.']) {
            final token = find.byWidgetPredicate(
              (widget) =>
                  widget is ChoiceChip && (widget.label as Text).data == value,
            );
            tester.widget<ChoiceChip>(token).onSelected!(true);
            await tester.pump();
          }
        }
        final VoidCallback retained = wordMode
            ? tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'ตรวจสอบคำตอบ'),
                  )
                  .onPressed!
            : tester
                  .widget<ElevatedButton>(find.byType(ElevatedButton))
                  .onPressed!;
        final retirement = lifecycle.retire();
        retained();
        await tester.runAsync(() => retirement);
        await tester.pumpAndSettle();
        expect(
          repository.commands,
          isEmpty,
          reason: 'owner/route retirement closes input synchronously',
        );
      },
    );
  }

  for (final width in <double>[320, 390, 840]) {
    testWidgets(
      'B05 letter occurrence keyboard undo and single evidence width=$width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = FailOnceLearningRepository(failFirst: false);
        final learning = buildFailOnceLearningUseCases(
          repository: repository,
          idPrefix: 'letter',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: width == 320 ? ThemeData.dark() : ThemeData.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(width == 320 ? 2 : 1),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: WordScrambleScreen(
              word: 'letter',
              meaning: 'จดหมาย',
              partOfSpeech: 'noun',
              ownerId: 'owner-1',
              sessionId: 'session-1',
              wordId: 'word-letter',
              evidenceAdapter: CurrentActivityEvidenceAdapter(
                learning: learning,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final letters = createStableScramble('letter');
        final used = <int>{};
        for (var slot = 0; slot < 6; slot++) {
          final index = letters
              .asMap()
              .entries
              .firstWhere(
                (entry) =>
                    entry.value == 'letter'[slot] && !used.contains(entry.key),
              )
              .key;
          used.add(index);
          final tile = find.byKey(ValueKey('word-letter-$index'));
          final target = find.byKey(ValueKey('word-slot-$slot'));
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          if (slot == 2) {
            await tester.drag(
              tile,
              tester.getCenter(target) - tester.getCenter(tile),
            );
          } else {
            await tester.tap(tile);
          }
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: target, matching: find.text('letter'[slot])),
            findsOneWidget,
          );
          if (slot == 3) {
            final slotText = find.descendant(
              of: target,
              matching: find.text('t'),
            );
            Focus.of(tester.element(slotText)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(
              find.descendant(of: target, matching: find.text('t')),
              findsNothing,
            );
            expect(tile.hitTestable(), findsOneWidget);
            Focus.of(tester.element(tile)).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expect(
              find.descendant(of: target, matching: find.text('t')),
              findsOneWidget,
            );
          }
          expect(
            repository.commands,
            isEmpty,
            reason: 'tiles do not write evidence',
          );
          expect(tester.takeException(), isNull);
        }
        final submit = find.widgetWithText(FilledButton, 'ตรวจสอบคำตอบ');
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        final retained = tester.widget<FilledButton>(submit).onPressed!;
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(repository.commands, hasLength(1));
        expect(
          repository.commands.single.evidenceContext.evidenceClass,
          EvidenceClass.recreational,
        );
        retained();
        await tester.pumpAndSettle();
        expect(
          repository.commands,
          hasLength(1),
          reason: 'late completion callback must not write another answer',
        );
        await tester.pumpWidget(const SizedBox());
        retained();
        await tester.pump();
        expect(repository.commands, hasLength(1));
      },
    );
  }

  testWidgets('B05 empty block spelling is unavailable', (tester) async {
    final repository = FailOnceLearningRepository(failFirst: false);
    final learning = buildFailOnceLearningUseCases(
      repository: repository,
      idPrefix: 'empty-word',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WordScrambleScreen(
          word: '   ',
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-1',
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('word-scramble-unavailable')),
      findsOneWidget,
    );
    expect(find.byType(DragTarget<int>), findsNothing);
    expect(find.text('ตรวจสอบคำตอบ'), findsNothing);
    expect(repository.commands, isEmpty);
  });

  testWidgets(
    'letter cards expose context and undo returns the same duplicate letter',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: WordScrambleScreen(
            word: 'aba',
            meaning: 'คำศัพท์ตัวอย่าง',
            partOfSpeech: 'noun',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('คำศัพท์ตัวอย่าง'), findsOneWidget);
      final letters = createStableScramble('aba');
      final index = letters.indexOf('a');
      final letter = find.byKey(ValueKey<String>('word-letter-$index'));
      final slot = find.byKey(const ValueKey<String>('word-slot-0'));
      await tester.tap(letter);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: slot, matching: find.text('a')),
        findsOneWidget,
      );
      await tester.tap(slot);
      await tester.pumpAndSettle();
      expect(find.descendant(of: slot, matching: find.text('a')), findsNothing);
      expect(letter.hitTestable(), findsOneWidget);
      await tester.tap(letter);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: slot, matching: find.text('a')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('f13 word scramble delegates correctness to its typed adapter', () {
    final source = File(
      'lib/screens/word_scramble_screen.dart',
    ).readAsStringSync();
    expect(source, contains('WordScrambleModeAdapter'));
    expect(source, contains('_modeAdapter.evaluate('));
    expect(source, contains('_lifecycle!.complete('));
    expect(source, isNot(contains('userAnswer.join() == widget.word')));
  });

  test('stable scramble is deterministic and preserves every character', () {
    final first = createStableScramble('learning');
    final second = createStableScramble('learning');

    expect(first, second);
    expect(first.join(), isNot('learning'));
    expect(first.toList()..sort(), 'learning'.split('')..sort());
  });

  test('stable scramble handles one-character and repeated words', () {
    expect(createStableScramble('a'), ['a']);
    expect(createStableScramble('aaa'), ['a', 'a', 'a']);
  });

  test('successful scramble has no hidden follow-on route in source', () {
    final source = File(
      'lib/screens/word_scramble_screen.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('FillInTheBlanksScreen')));
    expect(source, isNot(contains('learning/fill-blanks')));
    expect(source, isNot(contains('Future.delayed')));
  });

  testWidgets(
    'f38 ultra review: word completion follows response semantics',
    (tester) => withAccessibilitySemantics(tester, () async {
      await tester.pumpWidget(
        const MaterialApp(home: WordScrambleScreen(word: 'ab')),
      );
      await tester.pumpAndSettle();

      final targets = find.byType(DragTarget<int>);
      await tester.drag(
        find.text('a'),
        tester.getCenter(targets.at(0)) - tester.getCenter(find.text('a')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('b'),
        tester.getCenter(targets.at(1)) - tester.getCenter(find.text('b')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ตรวจสอบคำตอบ'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(WordScrambleScreen), findsOneWidget);
      expect(find.byType(FillInTheBlanksScreen), findsNothing);
      final root = find.byType(WordScrambleScreen);
      expectInsideAccessibilityRole(
        scope: root,
        descendant: find.byKey(
          const ValueKey<String>('word-scramble-complete'),
        ),
        role: AccessibilitySemanticRole.feedback,
        reason: 'completion is feedback and must follow the response region',
      );
      expectRenderedAccessibilityTraversal(
        tester,
        scope: root,
        roles: const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ],
      );
    }),
  );

  testWidgets('f38 final review: word completion waits for durable retry', (
    tester,
  ) async {
    final repository = FailOnceLearningRepository();
    final learning = buildFailOnceLearningUseCases(
      repository: repository,
      idPrefix: 'word-scramble',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: WordScrambleScreen(
          word: 'ab',
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-1',
          evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final targets = find.byType(DragTarget<int>);
    await tester.drag(
      find.text('a'),
      tester.getCenter(targets.at(0)) - tester.getCenter(find.text('a')),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.text('b'),
      tester.getCenter(targets.at(1)) - tester.getCenter(find.text('b')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตรวจสอบคำตอบ'));
    await tester.pump();
    await tester.pump();

    expect(repository.commands, hasLength(1));
    expect(
      find.byKey(const ValueKey<String>('word-scramble-complete')),
      findsNothing,
      reason: 'completion cannot publish before its evidence is durable',
    );
    expect(find.text('ถูกต้อง'), findsNothing);
    final retry = find.text('ลองบันทึกผลอีกครั้ง');
    expect(retry, findsOneWidget);
    final first = repository.commands.single;

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.commands, hasLength(2));
    final retried = repository.commands.last;
    expect(retried.id, first.id);
    expect(retried.occurredAtUtc, first.occurredAtUtc);
    expect(retried.responseTimeMs, first.responseTimeMs);
    expect(retried.evidenceContext.toJson(), first.evidenceContext.toJson());
    expect(
      find.byKey(const ValueKey<String>('word-scramble-complete')),
      findsOneWidget,
    );
    expect(retry, findsNothing);
  });

  testWidgets(
    'f38 role completion: durable incorrect word answer has local ordered feedback',
    (tester) => withAccessibilitySemantics(tester, () async {
      final repository = FailOnceLearningRepository(failFirst: false);
      final learning = buildFailOnceLearningUseCases(
        repository: repository,
        idPrefix: 'word-incorrect',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WordScrambleScreen(
            word: 'ab',
            ownerId: 'owner-1',
            sessionId: 'session-1',
            wordId: 'word-1',
            evidenceAdapter: CurrentActivityEvidenceAdapter(learning: learning),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final targets = find.byType(DragTarget<int>);
      await tester.drag(
        find.text('b'),
        tester.getCenter(targets.at(0)) - tester.getCenter(find.text('b')),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('a'),
        tester.getCenter(targets.at(1)) - tester.getCenter(find.text('a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ตรวจสอบคำตอบ'));
      await tester.pump();
      await tester.pump();

      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.isCorrect, isFalse);
      final root = find.byType(WordScrambleScreen);
      expect(
        accessibilityRoleRegion(root, AccessibilitySemanticRole.feedback),
        findsOneWidget,
      );
      final localFeedback = find.descendant(
        of: root,
        matching: find.text('ยังไม่ถูก ลองอีกครั้ง'),
      );
      expect(
        localFeedback,
        findsOneWidget,
        reason: 'SnackBar overlay is not the canonical in-screen feedback',
      );
      expectInsideAccessibilityRole(
        scope: root,
        descendant: localFeedback,
        role: AccessibilitySemanticRole.feedback,
      );
      expectRenderedAccessibilityTraversal(
        tester,
        scope: root,
        roles: const <AccessibilitySemanticRole>[
          AccessibilitySemanticRole.prompt,
          AccessibilitySemanticRole.responseAndInput,
          AccessibilitySemanticRole.feedback,
          AccessibilitySemanticRole.navigation,
        ],
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ตรวจสอบคำตอบ'),
            )
            .onPressed,
        isNotNull,
        reason: 'an incorrect committed arrangement remains retryable',
      );
      expect(repository.commands, hasLength(1));
    }),
  );
}

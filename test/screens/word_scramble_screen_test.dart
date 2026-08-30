import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/accessibility/domain/accessibility_policy.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

import '../support/accessibility_semantics_test_support.dart';
import '../support/fail_once_learning_test_fixture.dart';

void main() {
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

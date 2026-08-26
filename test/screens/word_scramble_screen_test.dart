import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/fill_in_the_blanks_screen.dart';
import 'package:vocab_learning_app/screens/word_scramble_screen.dart';

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

  testWidgets('successful scramble remains on its honest completion screen', (
    tester,
  ) async {
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
  });
}

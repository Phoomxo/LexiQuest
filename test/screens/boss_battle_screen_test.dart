import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/boss_battle_screen.dart';

void main() {
  test(
    'boss source requires questions and makes no synthetic reward claim',
    () {
      final source = File(
        'lib/screens/boss_battle_screen.dart',
      ).readAsStringSync();

      expect(source, contains('required this.questions'));
      for (final forbidden in <String>[
        'RankService',
        'rankService',
        '_earnedXp',
        '_earnedCoins',
        'C1',
        'ephemeral',
        'meticulous',
        'sustainable',
        'ประจำวัน',
      ]) {
        expect(source, isNot(contains(forbidden)));
      }
    },
  );

  testWidgets('one real question can complete the boss challenge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BossBattleScreen(
          bossName: 'Vocabulary Challenge',
          questions: [
            {'word': 'ephemeral', 'translation': 'ชั่วคราว'},
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vocabulary Challenge'), findsOneWidget);
    expect(find.text('HP: 1 / 1'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ephemeral');
    await tester.tap(find.text('โจมตีบอส!'));
    await tester.pumpAndSettle();

    expect(find.text('HP: 0 / 1'), findsOneWidget);
    expect(find.textContaining('ชัยชนะ'), findsOneWidget);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('เหรียญ'), findsNothing);
  });
}
